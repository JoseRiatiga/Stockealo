-- Stockealo Pro: plan anual en vez de permanente y precios nuevos (versión 0.9.2)
--
-- • Agrega el periodo 'year' (365 días) a planes y pagos
-- • Oculta los planes permanentes (quien ya lo tiene lo conserva; el dueño se puede
--   dar uno con un código permanente desde el panel)
-- • Precios nuevos en COP:
--     Pro Negocio: semanal 9.900 · mensual 29.900 · anual 299.000 (antes 358.800)
--     Pro Global:  semanal 19.900 · mensual 59.900 · anual 599.000 (antes 718.800)
-- No borra datos.

alter table public.pro_plans drop constraint if exists pro_plans_period_check;
alter table public.pro_plans add constraint pro_plans_period_check
  check (period in ('week', 'month', 'year', 'lifetime'));

alter table public.pro_payments drop constraint if exists pro_payments_period_check;
alter table public.pro_payments add constraint pro_payments_period_check
  check (period in ('week', 'month', 'year', 'lifetime'));

update public.pro_plans set price = 9900,  regular_price = null, label = null,           sort = 3 where id = 'business_week_cop';
update public.pro_plans set price = 29900, regular_price = null, label = 'Más elegido', sort = 2 where id = 'business_month_cop';
update public.pro_plans set price = 19900, regular_price = null, label = null,           sort = 6 where id = 'global_week_cop';
update public.pro_plans set price = 59900, regular_price = null, label = 'Más elegido', sort = 5 where id = 'global_month_cop';
update public.pro_plans set active = false where period = 'lifetime';

insert into public.pro_plans (id, kind, period, currency, price, regular_price, label, sort) values
  ('business_year_cop', 'business', 'year', 'COP', 299000, 358800, '2 meses gratis', 1),
  ('global_year_cop',   'global',   'year', 'COP', 599000, 718800, '2 meses gratis', 4)
on conflict (id) do update set
  price = excluded.price, regular_price = excluded.regular_price, label = excluded.label,
  sort = excluded.sort, active = true;

update public.pro_settings
   set value = 'Precios en pesos colombianos (COP), sujetos a cambios sin previo aviso. Los cambios no afectan los planes ya adquiridos.'
 where key = 'legal_notice';

-- El pago aprobado de un plan anual suma 365 días
create or replace function public.pro_apply_payment(
  p_reference text, p_transaction_id text, p_status text, p_method text, p_amount_in_cents bigint, p_currency text
)
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
    if v_pay.kind = 'business' then
      v_from := greatest(now(), coalesce((public.business_pro_until(v_pay.business_id) ->> 'ends_at')::timestamptz, now()));
    else
      v_from := greatest(now(), coalesce((
        select max(s.ends_at) from public.subscriptions s
         where s.kind = 'global' and lower(s.owner_email) = lower(v_pay.user_email) and s.ends_at > now()), now()));
    end if;
    v_end := case v_pay.period
      when 'week' then v_from + interval '7 days'
      when 'month' then v_from + interval '30 days'
      when 'year' then v_from + interval '365 days'
      else null
    end;
    insert into public.subscriptions (kind, business_id, owner_email, source, starts_at, ends_at)
    values (v_pay.kind, case when v_pay.kind = 'business' then v_pay.business_id end,
            v_pay.user_email, 'gateway', now(), v_end)
    returning id into v_sub;
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
revoke all on function public.pro_apply_payment(text, text, text, text, bigint, text) from public, anon, authenticated;
grant execute on function public.pro_apply_payment(text, text, text, text, bigint, text) to service_role;
