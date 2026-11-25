-- 0.18.3 · Subir de Pro a Pro Servicios con descuento (docs/plan-0.18.3.md punto 4 y
-- pregunta C, aprobados el 24 nov)
--
-- • Se descuenta lo que le queda de Pro pagado en línea: lo pagado por cada periodo ×
--   días que le faltan / días del periodo; el total, redondeado a $100.
-- • Solo cuenta el Pro pagado con Wompi. El Pro dado a mano o con código no da descuento
--   ni se corta: sigue como está.
-- • Al aprobarse el pago, ese Pro se corta hoy (si no, tendría el descuento y además esos
--   días de Pro después). Se guarda la fecha en que vencía para poder devolverlo a mano.
-- • Si con el descuento el pago queda en menos de $10.000 (Pro anual a Pro Servicios
--   mensual), se pide elegir Pro Servicios anual: así nunca se pierde lo pagado.
-- • El descuento no se suma a un cupón.
-- • Solo si la app lo pide (upgrade: true en pro-checkout): la app 0.18.2 sigue igual.

alter table public.pro_payments add column if not exists upgrade_credit_in_cents bigint;
alter table public.pro_payments add column if not exists upgrade_subs uuid[];
-- Lo que se cortó al aprobarse: [{ id, ends_at (la fecha en que vencía) }]
alter table public.pro_payments add column if not exists upgrade_cut jsonb;
-- true = al aprobarse ya no estaba todo el Pro descontado (por ejemplo, dos pagos de
-- subida a la vez): revisar a mano
alter table public.pro_payments add column if not exists upgrade_review boolean not null default false;

-- Lo que le queda del Pro pagado en línea de [p_business_id]: { credit (pesos), subs }.
-- Cada suscripción pagada cubre su periodo hasta su ends_at (las renovaciones se
-- encadenan, así que su periodo es [ends_at − días, ends_at]).
create or replace function public._pro_upgrade_credit(p_business_id text)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  with paid as (
    select s.id,
           s.ends_at,
           case pp.period when 'week' then 7 when 'month' then 30 else 365 end as period_days,
           greatest(pp.amount_in_cents - coalesce(pp.slot_amount_in_cents, 0), 0) / 100.0 as paid
      from public.subscriptions s
      join public.pro_payments pp on pp.subscription_id = s.id and pp.status = 'APPROVED'
     where s.kind = 'business'
       and s.business_id = p_business_id
       and s.source = 'gateway'
       and s.ends_at is not null
       and s.ends_at > now()
       and pp.period in ('week', 'month', 'year')
  ), left_days as (
    select id, period_days, paid,
           least(period_days,
                 greatest(ceil(extract(epoch from (ends_at - greatest(now(), ends_at - make_interval(days => period_days)))) / 86400.0), 0)
           ) as days
      from paid
  )
  select jsonb_build_object(
    'credit', coalesce((round(sum(paid * days / period_days) / 100) * 100)::integer, 0),
    'subs', coalesce(jsonb_agg(id) filter (where days > 0), '[]'::jsonb))
    from left_days;
$$;
revoke all on function public._pro_upgrade_credit(text) from public, anon, authenticated;

-- Precio de [p_plan_id] (Pro Servicios) para [p_business_id] con el descuento por su Pro.
-- La usan la pantalla Pro para mostrarlo y pro-checkout para cobrar: es la misma cuenta.
-- Devuelve { ok, error?, price, credit, amount, subs }
create or replace function public.pro_upgrade_quote(p_business_id text, p_plan_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_email text := lower(coalesce(auth.jwt() ->> 'email', ''));
  v_plan public.pro_plans;
  v_credit jsonb;
  v_amount integer;
begin
  if v_email <> '' and not exists (
    select 1 from public.business_members m
     where m.business_id = p_business_id and lower(m.user_email) = v_email and m.role in ('OWNER', 'ADMIN')
  ) then
    return jsonb_build_object('ok', false, 'error', 'not_allowed');
  end if;
  select * into v_plan from public.pro_plans where id = p_plan_id and active;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'plan_not_found');
  end if;
  -- Solo al pasar a Pro Servicios, y no al renovarlo: con Pro Servicios vigente su Pro ya
  -- va por dentro y el periodo nuevo empieza cuando termine
  if v_plan.kind <> 'services' or exists (
    select 1 from public.subscriptions s
     where s.kind = 'services' and s.business_id = p_business_id and (s.ends_at is null or s.ends_at > now())
  ) then
    return jsonb_build_object('ok', true, 'price', v_plan.price, 'credit', 0, 'amount', v_plan.price, 'subs', '[]'::jsonb);
  end if;
  v_credit := public._pro_upgrade_credit(p_business_id);
  v_amount := v_plan.price::integer - (v_credit ->> 'credit')::integer;
  if (v_credit ->> 'credit')::integer > 0 and v_amount < 10000 then
    return jsonb_build_object('ok', false, 'error', 'upgrade_choose_year',
      'price', v_plan.price, 'credit', (v_credit ->> 'credit')::integer);
  end if;
  return jsonb_build_object('ok', true, 'price', v_plan.price, 'credit', (v_credit ->> 'credit')::integer,
    'amount', v_amount, 'subs', v_credit -> 'subs');
end;
$$;
revoke all on function public.pro_upgrade_quote(text, text) from public, anon;
grant execute on function public.pro_upgrade_quote(text, text) to authenticated, service_role;

-- Igual que en 20261212000200, más el corte del Pro descontado
create or replace function public.pro_apply_payment(p_reference text, p_transaction_id text, p_status text, p_method text, p_amount_in_cents bigint, p_currency text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_pay public.pro_payments;
  v_from timestamptz;
  v_end timestamptz;
  v_sub uuid;
  v_cut jsonb;
begin
  select * into v_pay from public.pro_payments where reference = p_reference for update;
  if not found then
    raise exception 'payment_not_found';
  end if;
  if v_pay.status = 'APPROVED' then
    return jsonb_build_object('status', v_pay.status, 'subscription_id', v_pay.subscription_id);
  end if;
  if p_status = 'APPROVED' and (p_amount_in_cents <> v_pay.amount_in_cents or p_currency <> v_pay.currency) then
    update public.pro_payments
       set status = 'ERROR', wompi_transaction_id = p_transaction_id, payment_method = p_method, updated_at = now()
     where reference = p_reference;
    return jsonb_build_object('status', 'ERROR', 'reason', 'amount_mismatch');
  end if;
  if p_status = 'APPROVED' then
    if v_pay.plan_id = 'branch_slots' then
      -- Solo cupos: desde hoy hasta la fecha cotizada (el fin del plan)
      if v_pay.branch_slots > 0 and v_pay.slots_ends_at > now() then
        insert into public.branch_slots (business_id, slots, starts_at, ends_at, source, payment_reference)
        values (v_pay.business_id, v_pay.branch_slots, now(), v_pay.slots_ends_at, 'gateway', v_pay.reference);
      end if;
    else
      -- Subida a Pro Servicios con descuento: el Pro descontado termina hoy
      if coalesce(v_pay.upgrade_credit_in_cents, 0) > 0 and coalesce(cardinality(v_pay.upgrade_subs), 0) > 0 then
        select coalesce(jsonb_agg(jsonb_build_object('id', s.id, 'ends_at', s.ends_at)), '[]'::jsonb) into v_cut
          from public.subscriptions s
         where s.id = any(v_pay.upgrade_subs) and s.ends_at > now();
        update public.subscriptions set ends_at = now()
         where id = any(v_pay.upgrade_subs) and ends_at > now();
        v_pay.upgrade_cut := v_cut;
        v_pay.upgrade_review := jsonb_array_length(v_cut) < cardinality(v_pay.upgrade_subs);
      end if;
      v_from := public._plan_period_start(v_pay.kind, v_pay.business_id, v_pay.user_email);
      v_end := public._plan_period_end(v_from, v_pay.period);
      insert into public.subscriptions (kind, business_id, owner_email, source, starts_at, ends_at)
      values (v_pay.kind, case when v_pay.kind in ('business', 'services') then v_pay.business_id end,
              v_pay.user_email, 'gateway', now(), v_end)
      returning id into v_sub;
      -- Los cupos del periodo nuevo vencen con el plan
      if v_pay.branch_slots > 0 and v_pay.business_id is not null then
        insert into public.branch_slots (business_id, slots, starts_at, ends_at, source, payment_reference)
        values (v_pay.business_id, v_pay.branch_slots, v_from, v_end, 'gateway', v_pay.reference);
        -- Renovación: los que faltaban hoy, hasta que empiece el periodo nuevo
        if v_pay.slot_gap > 0 and v_from > now() then
          insert into public.branch_slots (business_id, slots, starts_at, ends_at, source, payment_reference)
          values (v_pay.business_id, v_pay.slot_gap, now(), v_from, 'gateway', v_pay.reference);
        end if;
      end if;
    end if;
    if v_pay.coupon_code is not null then
      update public.pro_coupons set uses = uses + 1 where code = v_pay.coupon_code;
    end if;
  end if;
  update public.pro_payments
     set status = case when p_status in ('APPROVED', 'DECLINED', 'VOIDED', 'ERROR') then p_status else 'PENDING' end,
         wompi_transaction_id = p_transaction_id,
         payment_method = p_method,
         subscription_id = coalesce(v_sub, subscription_id),
         upgrade_cut = coalesce(v_pay.upgrade_cut, upgrade_cut),
         upgrade_review = v_pay.upgrade_review,
         updated_at = now()
   where reference = p_reference;
  return jsonb_build_object('status', p_status, 'subscription_id', v_sub);
end;
$$;
