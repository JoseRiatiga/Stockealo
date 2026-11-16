-- 0.16.0: cupones más firmes (revisión de Codex antes de publicar)
--
-- 1. El pedido con cupón ya no confía en el total que manda el navegador: la nube suma
--    las líneas del pedido y calcula el descuento sobre esa suma.
-- 2. El límite gratis (1 cupón activo) no se puede pasar con dos guardados a la vez.
-- 3. El último uso de un cupón de la tienda no lo pueden gastar dos pedidos a la vez.
-- 4. Cupón Pro: los pagos que se están haciendo (últimas 2 horas, de otras cuentas)
--    cuentan para el límite de usos, para que varios pagos a la vez no lo pasen.

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
  v_pending integer;
begin
  select * into v_plan from public.pro_plans where id = p_plan_id;
  if not found then raise exception 'plan_not_found'; end if;
  select * into v_coupon from public.pro_coupons where code = upper(trim(coalesce(p_code, ''))) for update;
  if not found or not v_coupon.active then raise exception 'coupon_not_found'; end if;
  if v_coupon.expires_at is not null and v_coupon.expires_at <= now() then raise exception 'coupon_expired'; end if;
  if v_coupon.max_uses is not null then
    select count(*) into v_pending from public.pro_payments p
     where p.coupon_code = v_coupon.code and p.status = 'PENDING'
       and p.created_at > now() - interval '2 hours'
       and lower(p.user_email) <> lower(p_email);
    if v_coupon.uses + v_pending >= v_coupon.max_uses then raise exception 'coupon_used_up'; end if;
  end if;
  if not (v_plan.kind = any (v_coupon.kinds)) then raise exception 'coupon_wrong_plan'; end if;
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
  if v_price < 1500 then raise exception 'coupon_too_big'; end if;
  return jsonb_build_object('code', v_coupon.code, 'regular', v_plan.price, 'price', v_price,
                            'percent', v_coupon.percent, 'amount', v_coupon.amount);
end;
$$;
revoke all on function public.pro_coupon_price(text, text, text) from public, anon, authenticated;

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
  v_total numeric;
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
  -- El total sale de las líneas del pedido, no de lo que diga el navegador
  select coalesce(sum(greatest(coalesce(
           case when jsonb_typeof(l -> 'subtotal') = 'number' then (l ->> 'subtotal')::numeric end,
           case when jsonb_typeof(l -> 'quantity') = 'number' and jsonb_typeof(l -> 'unit_price') = 'number'
                then (l ->> 'quantity')::numeric * (l ->> 'unit_price')::numeric end,
           0), 0)), 0)
    into v_total
    from jsonb_array_elements(p_lines) as l;
  if nullif(trim(coalesce(p_coupon, '')), '') is not null then
    if v_phone is null then raise exception 'coupon_phone_required'; end if;
    -- Un pedido a la vez por cupón: el último uso no lo gastan dos
    perform 1 from public.store_coupons
     where business_id = v_store.business_id and code = upper(trim(p_coupon)) for update;
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
  -- Uno a la vez por negocio: así el límite gratis no se pasa guardando dos a la vez
  perform pg_advisory_xact_lock(hashtext('store_coupons:' || p_business_id));
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
