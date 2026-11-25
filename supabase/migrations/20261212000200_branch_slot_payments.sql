-- 0.18.3 · Un solo pago: plan + cupos de sede (docs/plan-0.18.3.md punto 3; precios y
-- reglas aprobados el 23 nov en docs/plan-sedes.md)
--
-- • branch_slot_prices: precio de cada cupo por plan, para cambiarlo sin publicar la app.
--   Cupo anual = 10 meses. «Desde 3»: si se compran 3 o más en la misma compra, todos
--   van al precio con descuento.
-- • branch_slot_quote: la ÚNICA cuenta del precio de los cupos. La usa pro-checkout para
--   cobrar y la pantalla Pro para mostrar el total; la app no calcula precios.
-- • pro_payments guarda cuántos cupos se pagaron y hasta cuándo, tal como se cotizaron.
-- • pro_apply_payment, al aprobarse el pago, crea la suscripción y los cupos.
--
-- Tres casos:
-- 1. Plan + n cupos: los n cupos van con el periodo nuevo del plan y vencen con él. Si el
--    plan vigente aún no termina (renovación), los cupos que falten hoy (n menos los que
--    ya tiene) se dan desde hoy hasta que empiece el periodo nuevo, cobrando esos días.
-- 2. Solo cupos, a mitad del periodo: se pagan los días que faltan del plan (precio ×
--    días / días del periodo, redondeado a $100 por cupo). Con menos de 7 días se pide
--    renovar el plan con los cupos en un solo pago (caso 1).
-- 3. Renovar: es el caso 1; la app trae ya marcados los cupos que tiene.
--
-- La app vieja (0.18.2) no manda cupos: todo sigue igual para ella.

create table if not exists public.branch_slot_prices (
  kind text primary key check (kind in ('business', 'services')),
  month_price integer not null check (month_price > 0),
  year_price integer not null check (year_price > 0),
  bulk_month_price integer not null check (bulk_month_price > 0),
  bulk_year_price integer not null check (bulk_year_price > 0),
  bulk_from integer not null default 3 check (bulk_from >= 2),
  updated_at timestamptz not null default now()
);
alter table public.branch_slot_prices enable row level security;
insert into public.branch_slot_prices (kind, month_price, year_price, bulk_month_price, bulk_year_price) values
  ('business', 14900, 149000, 12900, 129000),
  ('services', 24900, 249000, 21900, 219000)
on conflict (kind) do nothing;

alter table public.pro_payments add column if not exists branch_slots integer not null default 0;
alter table public.pro_payments add column if not exists slot_gap integer not null default 0;
alter table public.pro_payments add column if not exists slots_ends_at timestamptz;
alter table public.pro_payments add column if not exists slot_amount_in_cents bigint;
alter table public.branch_slots add column if not exists payment_reference text;
create unique index if not exists branch_slots_payment_part
  on public.branch_slots (payment_reference, starts_at) where payment_reference is not null;

-- Desde cuándo corre un plan nuevo de [p_kind]: al terminar el vigente del mismo tipo
-- (antes estaba dentro de pro_apply_payment; ahora lo usan también las cuentas de cupos)
create or replace function public._plan_period_start(p_kind text, p_business_id text, p_email text)
returns timestamptz
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when p_kind = 'business' then
      greatest(now(), coalesce((public.business_pro_until(p_business_id) ->> 'ends_at')::timestamptz, now()))
    when p_kind = 'services' then
      greatest(now(), coalesce((
        select max(s.ends_at) from public.subscriptions s
         where s.kind = 'services' and s.business_id = p_business_id and s.ends_at > now()), now()))
    else
      greatest(now(), coalesce((
        select max(s.ends_at) from public.subscriptions s
         where s.kind = 'global' and lower(s.owner_email) = lower(p_email) and s.ends_at > now()), now()))
  end;
$$;

create or replace function public._plan_period_end(p_from timestamptz, p_period text)
returns timestamptz
language sql
immutable
set search_path = ''
as $$
  select case p_period
    when 'week' then p_from + interval '7 days'
    when 'month' then p_from + interval '30 days'
    else p_from + interval '365 days'
  end;
$$;

-- Precio de [p_days] días de un cupo: precio × días / días del periodo, a $100
create or replace function public._slot_prorate(p_unit integer, p_days integer, p_period_days integer)
returns integer
language sql
immutable
set search_path = ''
as $$
  select (round(p_unit::numeric * greatest(p_days, 0) / greatest(p_period_days, 1) / 100) * 100)::integer;
$$;

-- Días que faltan hasta [p_end], contando el día empezado
create or replace function public._days_until(p_end timestamptz)
returns integer
language sql
stable
set search_path = ''
as $$
  select greatest(ceil(extract(epoch from (p_end - now())) / 86400.0), 0)::integer;
$$;

-- Cuánto cuestan [p_slots] cupos para [p_business_id].
-- p_plan_id = un plan de pro_plans (caso 1) o null (caso 2: solo cupos).
-- Devuelve { ok, error?, kind, period, slots, unit, amount (pesos), ends_at, ... }
create or replace function public.branch_slot_quote(p_business_id text, p_plan_id text, p_slots integer)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_email text := lower(coalesce(auth.jwt() ->> 'email', ''));
  v_plan public.pro_plans;
  v_pro jsonb := public.business_pro_until(p_business_id);
  v_price public.branch_slot_prices;
  v_kind text;
  v_period text;
  v_bulk boolean := coalesce(p_slots, 0) >= 3;
  v_unit integer;
  v_from timestamptz;
  v_end timestamptz;
  v_held integer;
  v_gap integer := 0;
  v_gap_days integer := 0;
  v_gap_amount integer := 0;
  v_days integer;
begin
  -- Desde la app: solo el dueño o un administrador del negocio. pro-checkout llama con
  -- la llave de servicio (sin correo) y ya revisó el permiso.
  if v_email <> '' and not exists (
    select 1 from public.business_members m
     where m.business_id = p_business_id and lower(m.user_email) = v_email and m.role in ('OWNER', 'ADMIN')
  ) then
    return jsonb_build_object('ok', false, 'error', 'not_allowed');
  end if;
  if p_slots is null or p_slots < 0 or p_slots > 50 then
    return jsonb_build_object('ok', false, 'error', 'bad_slots');
  end if;
  select coalesce(sum(s.slots), 0) into v_held from public.branch_slots s
   where s.business_id = p_business_id and s.starts_at <= now() and s.ends_at > now();

  if p_plan_id is not null then
    -- Caso 1: plan + cupos
    select * into v_plan from public.pro_plans where id = p_plan_id and active;
    if not found then
      return jsonb_build_object('ok', false, 'error', 'plan_not_found');
    end if;
    if v_plan.kind not in ('business', 'services') then
      return jsonb_build_object('ok', false, 'error', 'slots_not_allowed');
    end if;
    v_kind := v_plan.kind;
    v_period := v_plan.period;
    if v_period not in ('month', 'year') then
      return jsonb_build_object('ok', false, 'error', 'slots_not_allowed');
    end if;
    select * into v_price from public.branch_slot_prices where kind = v_kind;
    v_unit := case when v_period = 'year'
                   then case when v_bulk then v_price.bulk_year_price else v_price.year_price end
                   else case when v_bulk then v_price.bulk_month_price else v_price.month_price end end;
    v_from := public._plan_period_start(v_kind, p_business_id, null);
    v_end := public._plan_period_end(v_from, v_period);
    -- Renovación: los cupos que falten hoy, desde hoy hasta el periodo nuevo
    if v_from > now() + interval '1 hour' then
      v_gap := greatest(p_slots - v_held, 0);
      v_gap_days := public._days_until(v_from);
      v_gap_amount := v_gap * public._slot_prorate(v_unit, v_gap_days, case when v_period = 'year' then 365 else 30 end);
    end if;
    return jsonb_build_object(
      'ok', true, 'kind', v_kind, 'period', v_period, 'slots', p_slots, 'held', v_held,
      'unit', v_unit, 'period_amount', p_slots * v_unit,
      'gap', v_gap, 'gap_days', v_gap_days, 'gap_amount', v_gap_amount,
      'amount', p_slots * v_unit + v_gap_amount,
      'starts_at', v_from, 'ends_at', v_end);
  end if;

  -- Caso 2: solo cupos, con el plan vigente
  if not coalesce((v_pro ->> 'active')::boolean, false) then
    return jsonb_build_object('ok', false, 'error', 'no_plan');
  end if;
  if coalesce((v_pro ->> 'services')::boolean, false) then
    v_kind := 'services';
    v_end := (v_pro ->> 'services_ends_at')::timestamptz;
  elsif exists (select 1 from public.subscriptions s
                 where s.kind = 'business' and s.business_id = p_business_id
                   and s.starts_at <= now() and (s.ends_at is null or s.ends_at > now())) then
    v_kind := 'business';
    v_end := (select case when bool_or(s.ends_at is null) then null else max(s.ends_at) end
                from public.subscriptions s
               where s.kind = 'business' and s.business_id = p_business_id and (s.ends_at is null or s.ends_at > now()));
  else
    -- Pro Global: los cupos van con un plan del negocio
    return jsonb_build_object('ok', false, 'error', 'slots_not_allowed');
  end if;
  if v_end is null then
    return jsonb_build_object('ok', false, 'error', 'slots_not_allowed');
  end if;
  v_days := public._days_until(v_end);
  if v_days < 7 then
    return jsonb_build_object('ok', false, 'error', 'renew_with_plan', 'kind', v_kind, 'days', v_days, 'ends_at', v_end);
  end if;
  -- El periodo del plan vigente: anual si se pagó anual; si no (o fue dado), mensual
  v_period := coalesce((
    select pp.period from public.subscriptions s
      join public.pro_payments pp on pp.subscription_id = s.id
     where s.kind = v_kind and s.business_id = p_business_id and s.ends_at = v_end
     limit 1), 'month');
  if v_period <> 'year' then v_period := 'month'; end if;
  select * into v_price from public.branch_slot_prices where kind = v_kind;
  v_unit := case when v_period = 'year'
                 then case when v_bulk then v_price.bulk_year_price else v_price.year_price end
                 else case when v_bulk then v_price.bulk_month_price else v_price.month_price end end;
  return jsonb_build_object(
    'ok', true, 'kind', v_kind, 'period', v_period, 'slots', p_slots, 'held', v_held,
    'unit', v_unit, 'days', v_days,
    'amount', p_slots * public._slot_prorate(v_unit, v_days, case when v_period = 'year' then 365 else 30 end),
    'starts_at', now(), 'ends_at', v_end);
end;
$$;
revoke all on function public.branch_slot_quote(text, text, integer) from public, anon;
grant execute on function public.branch_slot_quote(text, text, integer) to authenticated, service_role;

-- Igual que antes, más los cupos. Un pago con plan_id = 'branch_slots' es solo de cupos
-- y no crea suscripción.
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
         updated_at = now()
   where reference = p_reference;
  return jsonb_build_object('status', p_status, 'subscription_id', v_sub);
end;
$$;
