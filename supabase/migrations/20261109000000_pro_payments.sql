-- Stockealo Pro: pagos en línea con Wompi (versión 0.9.2)
--
-- Flujo:
--   1. La app llama a la función pro-checkout: crea un pago PENDING con una
--      referencia única y arma el enlace de Wompi firmado (firma de integridad).
--   2. El cliente paga en Wompi (Nequi, PSE, tarjeta, Bancolombia).
--   3. Wompi avisa a la función wompi-webhook; esta verifica la firma del evento y
--      llama a pro_apply_payment, que activa Pro una sola vez.
--   4. La app consulta pro_payment_status hasta ver el resultado.
--
-- Seguridad:
--   • pro_payments no tiene acceso directo; solo funciones
--   • pro_apply_payment solo la llama el servidor (service_role), nunca la app
--   • el valor pagado debe coincidir con el del pedido para activar Pro
-- No modifica tablas existentes.

create table if not exists public.pro_payments (
  reference text primary key,
  business_id text references public.businesses (id) on delete set null,
  kind text not null check (kind in ('business', 'global')),
  plan_id text not null,
  period text not null check (period in ('week', 'month', 'lifetime')),
  amount_in_cents bigint not null check (amount_in_cents > 0),
  currency text not null,
  user_email text not null,
  status text not null default 'PENDING' check (status in ('PENDING', 'APPROVED', 'DECLINED', 'VOIDED', 'ERROR')),
  wompi_transaction_id text,
  payment_method text,
  subscription_id uuid references public.subscriptions (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists pro_payments_created_idx on public.pro_payments (created_at desc);
alter table public.pro_payments enable row level security;
revoke all on public.pro_payments from anon, authenticated;

-- Llave pública de Wompi (es pública por diseño; los secretos van en Edge Functions)
insert into public.pro_settings (key, value)
values ('wompi_public_key', 'pub_test_acN1Bq8OtIhWlS9fmpp8ebCxOGRk1qUF')
on conflict (key) do nothing;

-- ---------------------------------------------------------------------------
-- Aplicar el resultado de Wompi (solo el servidor). Idempotente.
-- ---------------------------------------------------------------------------
create or replace function public.pro_apply_payment(
  p_reference text,
  p_transaction_id text,
  p_status text,
  p_method text,
  p_amount_in_cents bigint,
  p_currency text
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

  -- Ya aprobado: no se vuelve a activar (Wompi puede avisar más de una vez)
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
    -- Los días se suman desde que vence el Pro que ya tenga
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
      else null
    end;

    insert into public.subscriptions (kind, business_id, owner_email, source, starts_at, ends_at)
    values (v_pay.kind,
            case when v_pay.kind = 'business' then v_pay.business_id end,
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

-- ---------------------------------------------------------------------------
-- Estado de un pago para la app (solo quien lo inició)
-- ---------------------------------------------------------------------------
create or replace function public.pro_payment_status(p_reference text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_pay public.pro_payments;
begin
  select * into v_pay from public.pro_payments
   where reference = p_reference and lower(user_email) = lower(coalesce(auth.email(), ''));
  if not found then
    return null;
  end if;
  return jsonb_build_object('reference', v_pay.reference, 'status', v_pay.status, 'kind', v_pay.kind,
                            'period', v_pay.period, 'amount_in_cents', v_pay.amount_in_cents);
end;
$$;
revoke all on function public.pro_payment_status(text) from public, anon;
grant execute on function public.pro_payment_status(text) to authenticated;

-- ---------------------------------------------------------------------------
-- Panel: lista de pagos y llave pública editable
-- ---------------------------------------------------------------------------
create or replace function public.admin_list_payments(p_limit integer default 100)
returns table (
  reference text,
  business_name text,
  user_email text,
  kind text,
  period text,
  amount_in_cents bigint,
  currency text,
  status text,
  payment_method text,
  wompi_transaction_id text,
  created_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform public.admin_guard();
  return query
    select p.reference, b.name, p.user_email, p.kind, p.period, p.amount_in_cents, p.currency, p.status,
           p.payment_method, p.wompi_transaction_id, p.created_at
      from public.pro_payments p
      left join public.businesses b on b.id = p.business_id
     order by p.created_at desc
     limit least(greatest(coalesce(p_limit, 100), 1), 500);
end;
$$;
revoke all on function public.admin_list_payments(integer) from public, anon;
grant execute on function public.admin_list_payments(integer) to authenticated;

create or replace function public.admin_set_setting(p_key text, p_value text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform public.admin_guard();
  if p_key not in ('nequi_number', 'nequi_name', 'whatsapp', 'founder_slots', 'founder_until', 'legal_notice',
                   'wompi_public_key') then
    raise exception 'invalid_setting';
  end if;
  insert into public.pro_settings (key, value) values (p_key, nullif(trim(coalesce(p_value, '')), ''))
  on conflict (key) do update set value = excluded.value;
end;
$$;
