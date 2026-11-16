-- 0.16.0, fase 7: cupones
--
-- A · Cupones Pro: los crea el dueño de Stockealo en el panel. Descuento en % o en
--     pesos al pagar Pro o Pro Servicios con Wompi. El precio lo fija el servidor
--     (pro-checkout) y el uso se cuenta cuando el pago queda APROBADO.
-- B · Cupones de la tienda: cada negocio los suyos. Gratis 1 activo; varios con Pro.
--     El comprador lo escribe en el carrito, la nube lo revisa y recalcula el
--     descuento al crear el pedido. Una vez por teléfono.

-- ---------------------------------------------------------------------------
-- A · Cupones Pro
-- ---------------------------------------------------------------------------
create table if not exists public.pro_coupons (
  code text primary key check (code ~ '^[A-Z0-9-]{4,32}$'),
  percent numeric check (percent is null or (percent > 0 and percent <= 90)),
  amount numeric check (amount is null or amount > 0),
  -- En qué planes sirve (kind de pro_plans)
  kinds text[] not null default array['business', 'services'],
  max_uses integer check (max_uses is null or max_uses > 0),
  uses integer not null default 0,
  first_purchase_only boolean not null default false,
  expires_at timestamptz,
  active boolean not null default true,
  note text,
  created_at timestamptz not null default now(),
  check ((percent is null) <> (amount is null))
);
alter table public.pro_coupons enable row level security;
revoke all on public.pro_coupons from anon, authenticated;

alter table public.pro_payments add column if not exists coupon_code text;
alter table public.pro_payments add column if not exists regular_amount_in_cents bigint;

-- Precio con el cupón para una cuenta y un plan. Lanza el motivo si no sirve.
-- Solo lo usan pro-checkout (con la llave de servicio) y pro_coupon_quote.
create or replace function public.pro_coupon_price(p_code text, p_plan_id text, p_email text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_coupon public.pro_coupons;
  v_plan public.pro_plans;
  v_price numeric;
begin
  select * into v_plan from public.pro_plans where id = p_plan_id;
  if not found then raise exception 'plan_not_found'; end if;
  select * into v_coupon from public.pro_coupons where code = upper(trim(coalesce(p_code, '')));
  if not found or not v_coupon.active then raise exception 'coupon_not_found'; end if;
  if v_coupon.expires_at is not null and v_coupon.expires_at <= now() then raise exception 'coupon_expired'; end if;
  if v_coupon.max_uses is not null and v_coupon.uses >= v_coupon.max_uses then raise exception 'coupon_used_up'; end if;
  if not (v_plan.kind = any (v_coupon.kinds)) then raise exception 'coupon_wrong_plan'; end if;
  -- Una vez por cuenta
  if exists (select 1 from public.pro_payments p
              where p.coupon_code = v_coupon.code and p.status = 'APPROVED' and lower(p.user_email) = lower(p_email)) then
    raise exception 'coupon_already_used';
  end if;
  if v_coupon.first_purchase_only and exists (
       select 1 from public.pro_payments p where p.status = 'APPROVED' and lower(p.user_email) = lower(p_email)) then
    raise exception 'coupon_first_purchase';
  end if;
  v_price := case
    when v_coupon.percent is not null then round(v_plan.price * (100 - v_coupon.percent) / 100)
    else v_plan.price - v_coupon.amount
  end;
  -- Wompi no cobra montos muy bajos: para regalar Pro están los códigos canjeables
  if v_price < 1500 then raise exception 'coupon_too_big'; end if;
  return jsonb_build_object('code', v_coupon.code, 'regular', v_plan.price, 'price', v_price,
                            'percent', v_coupon.percent, 'amount', v_coupon.amount);
end;
$$;
revoke all on function public.pro_coupon_price(text, text, text) from public, anon, authenticated;

-- Vista previa en la pantalla Pro: el precio con el cupón para quien pregunta
create or replace function public.pro_coupon_quote(p_code text, p_plan_id text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_email text := lower(coalesce(auth.jwt() ->> 'email', ''));
begin
  if v_email = '' then raise exception 'not_authenticated'; end if;
  return public.pro_coupon_price(p_code, p_plan_id, v_email);
end;
$$;
revoke all on function public.pro_coupon_quote(text, text) from public, anon;
grant execute on function public.pro_coupon_quote(text, text) to authenticated;

-- El pago aprobado cuenta el uso del cupón (una sola vez: el pago APROBADO ya no vuelve a entrar)
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
    if v_pay.kind = 'business' then
      v_from := greatest(now(), coalesce((public.business_pro_until(v_pay.business_id) ->> 'ends_at')::timestamptz, now()));
    elsif v_pay.kind = 'services' then
      v_from := greatest(now(), coalesce((
        select max(s.ends_at) from public.subscriptions s
         where s.kind = 'services' and s.business_id = v_pay.business_id and s.ends_at > now()), now()));
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
    values (v_pay.kind, case when v_pay.kind in ('business', 'services') then v_pay.business_id end,
            v_pay.user_email, 'gateway', now(), v_end)
    returning id into v_sub;
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

-- Panel
create or replace function public.admin_save_pro_coupon(
  p_code text, p_percent numeric, p_amount numeric, p_kinds text[],
  p_max_uses integer default null, p_first_purchase_only boolean default false,
  p_valid_days integer default null, p_note text default null
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_code text := upper(trim(coalesce(p_code, '')));
begin
  perform public.admin_require('OWNER', 'save_pro_coupon',
    jsonb_build_object('code', v_code, 'percent', p_percent, 'amount', p_amount, 'kinds', p_kinds, 'max_uses', p_max_uses));
  if v_code !~ '^[A-Z0-9-]{4,32}$' then raise exception 'invalid_code'; end if;
  if (p_percent is null) = (p_amount is null) then raise exception 'invalid_discount'; end if;
  if p_kinds is null or cardinality(p_kinds) = 0 or not (p_kinds <@ array['business', 'services', 'global']) then
    raise exception 'invalid_kinds';
  end if;
  if p_valid_days is not null and (p_valid_days < 1 or p_valid_days > 3650) then raise exception 'invalid_valid_days'; end if;
  if exists (select 1 from public.pro_codes where code = v_code) then raise exception 'code_taken'; end if;
  insert into public.pro_coupons (code, percent, amount, kinds, max_uses, first_purchase_only, expires_at, note)
  values (v_code, p_percent, p_amount, p_kinds, p_max_uses, coalesce(p_first_purchase_only, false),
          case when p_valid_days is not null then now() + make_interval(days => p_valid_days) end,
          nullif(left(trim(coalesce(p_note, '')), 200), ''));
  return v_code;
exception when unique_violation then
  raise exception 'code_taken';
end;
$$;
revoke all on function public.admin_save_pro_coupon(text, numeric, numeric, text[], integer, boolean, integer, text) from public, anon;
grant execute on function public.admin_save_pro_coupon(text, numeric, numeric, text[], integer, boolean, integer, text) to authenticated;

create or replace function public.admin_list_pro_coupons()
returns setof public.pro_coupons
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform public.admin_require('SUPPORT', null, null);
  return query select * from public.pro_coupons order by created_at desc limit 200;
end;
$$;
revoke all on function public.admin_list_pro_coupons() from public, anon;
grant execute on function public.admin_list_pro_coupons() to authenticated;

create or replace function public.admin_set_pro_coupon_active(p_code text, p_active boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform public.admin_require('OWNER', 'set_pro_coupon_active', jsonb_build_object('code', upper(trim(p_code)), 'active', p_active));
  update public.pro_coupons set active = coalesce(p_active, false) where code = upper(trim(p_code));
end;
$$;
revoke all on function public.admin_set_pro_coupon_active(text, boolean) from public, anon;
grant execute on function public.admin_set_pro_coupon_active(text, boolean) to authenticated;

-- ---------------------------------------------------------------------------
-- B · Cupones de la tienda
-- ---------------------------------------------------------------------------
create table if not exists public.store_coupons (
  id uuid primary key default gen_random_uuid(),
  business_id text not null references public.businesses (id) on delete cascade,
  code text not null check (code ~ '^[A-Z0-9-]{3,24}$'),
  percent numeric check (percent is null or (percent > 0 and percent <= 100)),
  amount numeric check (amount is null or amount > 0),
  min_total numeric not null default 0 check (min_total >= 0),
  max_uses integer check (max_uses is null or max_uses > 0),
  uses integer not null default 0,
  expires_at timestamptz,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (business_id, code),
  check ((percent is null) <> (amount is null))
);
alter table public.store_coupons enable row level security;
revoke all on public.store_coupons from anon, authenticated;

-- Quién ya lo usó (una vez por teléfono)
create table if not exists public.store_coupon_uses (
  coupon_id uuid not null references public.store_coupons (id) on delete cascade,
  phone text not null,
  order_id text,
  used_at timestamptz not null default now(),
  primary key (coupon_id, phone)
);
alter table public.store_coupon_uses enable row level security;
revoke all on public.store_coupon_uses from anon, authenticated;

alter table public.store_orders add column if not exists coupon_code text;
alter table public.store_orders add column if not exists discount numeric not null default 0;

-- Solo los números del teléfono, sin el 57 de Colombia adelante
create or replace function public.store_phone_key(p_phone text)
returns text
language sql
immutable
set search_path = ''
as $$
  select nullif(regexp_replace(regexp_replace(coalesce(p_phone, ''), '\D', '', 'g'), '^57(?=\d{10}$)', ''), '');
$$;

-- El descuento de un cupón para un total. Lanza el motivo si no sirve.
create or replace function public.store_coupon_discount(p_business_id text, p_code text, p_total numeric, p_phone text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_coupon public.store_coupons;
  v_phone text := public.store_phone_key(p_phone);
  v_total numeric := greatest(coalesce(p_total, 0), 0);
  v_discount numeric;
begin
  select * into v_coupon from public.store_coupons
   where business_id = p_business_id and code = upper(trim(coalesce(p_code, '')));
  if not found or not v_coupon.active then raise exception 'coupon_not_found'; end if;
  if v_coupon.expires_at is not null and v_coupon.expires_at <= now() then raise exception 'coupon_expired'; end if;
  if v_coupon.max_uses is not null and v_coupon.uses >= v_coupon.max_uses then raise exception 'coupon_used_up'; end if;
  if v_total < v_coupon.min_total then
    raise exception 'coupon_min_total:%', v_coupon.min_total;
  end if;
  if v_phone is not null and exists (select 1 from public.store_coupon_uses u where u.coupon_id = v_coupon.id and u.phone = v_phone) then
    raise exception 'coupon_already_used';
  end if;
  v_discount := case
    when v_coupon.percent is not null then round(v_total * v_coupon.percent / 100)
    else least(v_coupon.amount, v_total)
  end;
  return jsonb_build_object('id', v_coupon.id, 'code', v_coupon.code, 'discount', v_discount,
                            'percent', v_coupon.percent, 'amount', v_coupon.amount, 'min_total', v_coupon.min_total);
end;
$$;
revoke all on function public.store_coupon_discount(text, text, numeric, text) from public, anon, authenticated;

-- Vista previa en el carrito (público): no gasta el cupón
create or replace function public.check_store_coupon(p_slug text, p_code text, p_total numeric, p_phone text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_store public.online_stores;
  v_result jsonb;
begin
  select * into v_store from public.online_stores where slug = lower(trim(coalesce(p_slug, '')));
  if not found or not v_store.enabled then raise exception 'store_not_found'; end if;
  v_result := public.store_coupon_discount(v_store.business_id, p_code, p_total, p_phone);
  return v_result - 'id';
end;
$$;
revoke all on function public.check_store_coupon(text, text, numeric, text) from public;
grant execute on function public.check_store_coupon(text, text, numeric, text) to anon, authenticated;

-- El pedido con cupón: la nube recalcula el descuento y lo gasta (una vez por teléfono)
drop function if exists public.create_store_order(text, text, text, text, jsonb, numeric);
create or replace function public.create_store_order(
  p_slug text, p_customer_name text, p_customer_phone text, p_note text, p_lines jsonb, p_total numeric,
  p_coupon text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_store public.online_stores;
  v_number integer;
  v_id text;
  v_code text;
  v_name text := left(trim(coalesce(p_customer_name, '')), 80);
  v_total numeric := greatest(coalesce(p_total, 0), 0);
  v_coupon jsonb;
  v_discount numeric := 0;
  v_phone text := public.store_phone_key(p_customer_phone);
begin
  select * into v_store from public.online_stores where slug = lower(trim(coalesce(p_slug, '')));
  if not found or not v_store.enabled then
    raise exception 'store_not_found';
  end if;
  if not coalesce((public.business_pro_until(v_store.business_id) ->> 'active')::boolean, false) then
    raise exception 'store_not_found';
  end if;
  if v_name = '' then
    raise exception 'name_required';
  end if;
  if jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) = 0 or jsonb_array_length(p_lines) > 100 then
    raise exception 'invalid_lines';
  end if;
  if nullif(trim(coalesce(p_coupon, '')), '') is not null then
    -- Con cupón, el teléfono es obligatorio: así se usa una vez por cliente
    if v_phone is null then raise exception 'coupon_phone_required'; end if;
    v_coupon := public.store_coupon_discount(v_store.business_id, p_coupon, v_total, v_phone);
    v_discount := least((v_coupon ->> 'discount')::numeric, v_total);
  end if;
  perform pg_advisory_xact_lock(hashtext('store_orders:' || v_store.business_id));
  select coalesce(max(number), 0) + 1 into v_number from public.store_orders where business_id = v_store.business_id;
  v_code := 'T-' || lpad(v_number::text, 4, '0');
  insert into public.store_orders (business_id, number, code, customer_name, customer_phone, note, lines, total, coupon_code, discount)
  values (
    v_store.business_id, v_number, v_code, v_name,
    nullif(left(trim(coalesce(p_customer_phone, '')), 30), ''),
    nullif(left(trim(coalesce(p_note, '')), 500), ''),
    p_lines, v_total - v_discount, v_coupon ->> 'code', v_discount
  )
  returning id into v_id;
  if v_coupon is not null then
    begin
      insert into public.store_coupon_uses (coupon_id, phone, order_id) values ((v_coupon ->> 'id')::uuid, v_phone, v_id);
    exception when unique_violation then
      raise exception 'coupon_already_used';
    end;
    update public.store_coupons set uses = uses + 1 where id = (v_coupon ->> 'id')::uuid;
  end if;
  return jsonb_build_object('id', v_id, 'code', v_code, 'discount', v_discount, 'total', v_total - v_discount);
end;
$$;
revoke all on function public.create_store_order(text, text, text, text, jsonb, numeric, text) from public;
grant execute on function public.create_store_order(text, text, text, text, jsonb, numeric, text) to anon, authenticated;

-- El dueño o un administrador del negocio
create or replace function public.list_my_store_coupons(p_business_id text)
returns setof public.store_coupons
language plpgsql
security definer
set search_path = ''
as $$
begin
  if coalesce(public.my_business_role(p_business_id), '') not in ('OWNER', 'ADMIN') then
    raise exception 'not_allowed';
  end if;
  return query select * from public.store_coupons where business_id = p_business_id order by created_at desc;
end;
$$;
revoke all on function public.list_my_store_coupons(text) from public, anon;
grant execute on function public.list_my_store_coupons(text) to authenticated;

-- Crea o cambia un cupón. Gratis: 1 activo; con Pro, varios.
create or replace function public.save_my_store_coupon(
  p_business_id text, p_id uuid, p_code text, p_percent numeric, p_amount numeric,
  p_min_total numeric default 0, p_max_uses integer default null, p_expires_at timestamptz default null,
  p_active boolean default true
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_code text := upper(trim(coalesce(p_code, '')));
  v_id uuid := p_id;
begin
  if coalesce(public.my_business_role(p_business_id), '') not in ('OWNER', 'ADMIN') then
    raise exception 'not_allowed';
  end if;
  if v_code !~ '^[A-Z0-9-]{3,24}$' then raise exception 'invalid_code'; end if;
  if (p_percent is null) = (p_amount is null) then raise exception 'invalid_discount'; end if;
  if coalesce(p_active, true)
     and not coalesce((public.business_pro_until(p_business_id) ->> 'active')::boolean, false)
     and exists (select 1 from public.store_coupons c
                  where c.business_id = p_business_id and c.active
                    and (c.expires_at is null or c.expires_at > now())
                    and (v_id is null or c.id <> v_id)) then
    raise exception 'coupon_limit';
  end if;
  if v_id is null then
    insert into public.store_coupons (business_id, code, percent, amount, min_total, max_uses, expires_at, active)
    values (p_business_id, v_code, p_percent, p_amount, greatest(coalesce(p_min_total, 0), 0), p_max_uses, p_expires_at, coalesce(p_active, true))
    returning id into v_id;
  else
    update public.store_coupons
       set code = v_code, percent = p_percent, amount = p_amount, min_total = greatest(coalesce(p_min_total, 0), 0),
           max_uses = p_max_uses, expires_at = p_expires_at, active = coalesce(p_active, true)
     where id = v_id and business_id = p_business_id;
    if not found then raise exception 'coupon_not_found'; end if;
  end if;
  return v_id;
exception when unique_violation then
  raise exception 'code_taken';
end;
$$;
revoke all on function public.save_my_store_coupon(text, uuid, text, numeric, numeric, numeric, integer, timestamptz, boolean) from public, anon;
grant execute on function public.save_my_store_coupon(text, uuid, text, numeric, numeric, numeric, integer, timestamptz, boolean) to authenticated;

create or replace function public.delete_my_store_coupon(p_business_id text, p_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if coalesce(public.my_business_role(p_business_id), '') not in ('OWNER', 'ADMIN') then
    raise exception 'not_allowed';
  end if;
  delete from public.store_coupons where id = p_id and business_id = p_business_id;
end;
$$;
revoke all on function public.delete_my_store_coupon(text, uuid) from public, anon;
grant execute on function public.delete_my_store_coupon(text, uuid) to authenticated;
