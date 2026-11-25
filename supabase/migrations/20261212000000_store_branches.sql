-- 0.18.3 · Tienda por sede (plan aprobado el 24 nov, docs/plan-0.18.3.md)
--
-- • get_public_store trae las sedes que venden (la Principal primero, con la dirección y
--   el teléfono del recibo) y el stock de cada producto en cada sede ('branch_stock',
--   clave '' = Principal). Un producto con stock solo en otra sede ya no se esconde.
--   Sin sedes abiertas, la respuesta es la de siempre (sin 'branches').
-- • El pedido de la tienda guarda en qué sede se pidió (store_orders.branch_id) para
--   que el negocio sepa dónde prepararlo (pregunta A). La app vieja no manda la sede y
--   el pedido queda sin sede, como hoy.

-- Un dato del recibo (ticket_info es texto JSON); null si falta o no se puede leer
create or replace function public._ticket_field(p_info text, p_key text)
returns text
language plpgsql
immutable
set search_path = ''
as $$
begin
  return nullif(left(trim(coalesce(p_info::jsonb ->> p_key, '')), 120), '');
exception when others then
  return null;
end;
$$;

alter table public.store_orders add column if not exists branch_id text;

drop function if exists public.create_store_order(text, text, text, text, jsonb, numeric, text);
create or replace function public.create_store_order(
  p_slug text, p_customer_name text, p_customer_phone text, p_note text, p_lines jsonb, p_total numeric,
  p_coupon text default null, p_branch_id text default null
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
  v_branch text := nullif(trim(coalesce(p_branch_id, '')), '');
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
  -- La sede debe ser de este negocio y estar vendiendo; si no, el pedido va sin sede
  if v_branch is not null and not exists (
    select 1 from public.branches b
     where b.id = v_branch and b.business_id = v_store.business_id and b.status = 'ACTIVE'
  ) then
    v_branch := null;
  end if;
  if jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) = 0 or jsonb_array_length(p_lines) > 100 then
    raise exception 'invalid_lines';
  end if;
  select coalesce(sum(greatest(coalesce(
           case when jsonb_typeof(l -> 'subtotal') = 'number' then (l ->> 'subtotal')::numeric end,
           case when jsonb_typeof(l -> 'quantity') = 'number' and jsonb_typeof(l -> 'unit_price') = 'number'
                then (l ->> 'quantity')::numeric * (l ->> 'unit_price')::numeric end,
           0), 0)), 0)
    into v_total
    from jsonb_array_elements(p_lines) as l;
  if nullif(trim(coalesce(p_coupon, '')), '') is not null then
    if v_phone is null then raise exception 'coupon_phone_required'; end if;
    perform 1 from public.store_coupons
     where business_id = v_store.business_id and code = upper(trim(p_coupon)) for update;
    v_coupon := public.store_coupon_discount(v_store.business_id, p_coupon, v_total, v_phone);
    v_discount := least((v_coupon ->> 'discount')::numeric, v_total);
  end if;
  perform pg_advisory_xact_lock(hashtext('store_orders:' || v_store.business_id));
  select coalesce(max(number), 0) + 1 into v_number from public.store_orders where business_id = v_store.business_id;
  v_code := 'T-' || lpad(v_number::text, 4, '0');
  insert into public.store_orders (business_id, number, code, customer_name, customer_phone, note, lines, total, coupon_code, discount, branch_id)
  values (
    v_store.business_id, v_number, v_code, v_name,
    nullif(left(trim(coalesce(p_customer_phone, '')), 30), ''),
    nullif(left(trim(coalesce(p_note, '')), 500), ''),
    p_lines, v_total - v_discount, v_coupon ->> 'code', v_discount, v_branch
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
grant execute on function public.create_store_order(text, text, text, text, jsonb, numeric, text, text) to anon, authenticated;

create or replace function public.get_public_store(p_slug text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_store public.online_stores;
  v_business public.businesses;
  v_branches boolean;
begin
  select * into v_store from public.online_stores where slug = lower(trim(coalesce(p_slug, '')));
  if not found or not v_store.enabled then
    return null;
  end if;
  select * into v_business from public.businesses where id = v_store.business_id;
  if not found or coalesce(v_business.is_deleted, 0) = 1 then
    return null;
  end if;
  if not coalesce((public.business_pro_until(v_store.business_id) ->> 'active')::boolean, false) then
    return null;
  end if;
  -- Sedes que venden hoy (activas y dentro de los cupos del plan)
  v_branches := exists (
    select 1 from public.branches b
     where b.business_id = v_store.business_id and b.status = 'ACTIVE' and public.branch_usable(b.id)
  );

  return jsonb_build_object(
    'slug', v_store.slug,
    'whatsapp', v_store.whatsapp,
    'welcome', v_store.welcome,
    'template', v_store.template,
    'hero_title', v_store.hero_title,
    'look', coalesce(v_store.look, '{}'::jsonb), 'category_icons', coalesce((select jsonb_object_agg(lower(trim(c.name)), c.icon) from public.categories c where c.business_id = v_store.business_id and c.icon is not null), '{}'::jsonb), 'hero_photos', v_store.hero_photos, 'hero_image_url', case when v_store.hero_image_url like 'https://%' then v_store.hero_image_url end,
    'business', jsonb_build_object(
      'name', v_business.name,
      'logo_url', v_business.logo_url,
      'color', v_business.color,
      'currency', v_business.currency,
      'country', v_business.country, 'time_zone', public.business_time_zone(v_business.id), 'address', case when coalesce((v_store.look ->> 'address')::boolean, true) then public._ticket_address(v_business.ticket_info) end
    ),
    'branches', case when v_branches then (
      select jsonb_build_array(jsonb_build_object(
               'id', '',
               'name', coalesce(nullif(trim(coalesce(v_business.main_branch_name, '')), ''), 'Principal'),
               'address', public._ticket_address(v_business.ticket_info),
               'phone', public._ticket_field(v_business.ticket_info, 'phone'),
               'schedule', null))
             || coalesce(jsonb_agg(jsonb_build_object(
               'id', b.id, 'name', b.name,
               'address', nullif(trim(coalesce(b.address, '')), ''),
               'phone', nullif(trim(coalesce(b.phone, '')), ''),
               'schedule', b.schedule) order by b.created_at), '[]'::jsonb)
        from public.branches b
       where b.business_id = v_store.business_id and b.status = 'ACTIVE' and public.branch_usable(b.id)
    ) end,
    'products', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', p.id,
        'name', p.name,
        'category', p.category, 'brand', nullif(trim(coalesce(p.brand, '')), ''), 'description', nullif(left(trim(coalesce(p.description, '')), 300), ''),
        'price', p.sale_price, 'price_tiers', case when jsonb_typeof(p.price_tiers) = 'array' and jsonb_array_length(p.price_tiers) > 0 then p.price_tiers end,
        'old_price', case when p.compare_price > p.sale_price then p.compare_price end,
        'image_url', case when p.image_url like 'https://%' then p.image_url end,
        'stock', case when v_store.show_stock then p.current_stock end,
        'few', p.current_stock <= 3,
        -- Unidades en cada sede ('' = Principal); solo con sedes. El número exacto solo si
        -- la tienda muestra el stock; si no, 1 = hay y 0 = no hay.
        'branch_stock', case when v_branches then (
          select jsonb_object_agg(k, case when v_store.show_stock then n else least(n, 1) end)
            from (
              select '' as k, greatest(p.current_stock, 0)::int as n
              union all
              select bs.branch_id, greatest(sum(bs.stock), 0)::int
                from public.branch_stock bs
                join public.branches b on b.id = bs.branch_id
               where bs.product_id = p.id and b.status = 'ACTIVE' and public.branch_usable(b.id)
               group by bs.branch_id
            ) s
        ) end,
        'promo', (
          select jsonb_build_object(
            'name', pr.name, 'kind', pr.kind, 'percent_off', pr.percent_off,
            'buy_qty', pr.buy_qty, 'pay_qty', pr.pay_qty, 'ends_at', pr.ends_at
          )
          from public.promotions pr
          where pr.business_id = v_store.business_id and pr.is_active
            and now() >= pr.starts_at and now() < pr.ends_at
            and (pr.scope = 'ALL'
              or (pr.scope = 'CATEGORY' and lower(trim(coalesce(pr.category, ''))) = lower(trim(coalesce(p.category, ''))))
              or (pr.scope = 'PRODUCTS' and coalesce(pr.product_ids, '') like '%"' || p.id || '"%'))
          order by case when pr.kind = 'PERCENT' then pr.percent_off else 100.0 * (pr.buy_qty - pr.pay_qty) / greatest(pr.buy_qty, 1) end desc
          limit 1
        ),
        'variants', coalesce((
          select jsonb_agg(jsonb_build_object(
            'id', v.id,
            'size', nullif(trim(v.attribute_value), ''), 'size_name', nullif(trim(coalesce(v.attribute_name, '')), ''), 'option_name', nullif(trim(coalesce(v.attribute2_name, '')), ''),
            'color', nullif(trim(coalesce(v.attribute2_value, '')), ''),
            'hex', v.color_hex, 'image', case when v.image_url like 'https://%' then v.image_url end,
            'extra', v.additional_price,
            'stock', case when v_store.show_stock then greatest(v.stock, 0) end,
            'sold_out', v.stock <= 0,
            'few', v.stock between 1 and 3
          ) order by v.created_at)
          from public.product_variants v
          where v.product_id = p.id
        ), '[]'::jsonb)
      ) order by lower(coalesce(p.category, '')), lower(p.name))
      from (
        select * from public.products pp
        where pp.business_id = v_store.business_id and pp.sale_price > 0
          and (pp.current_stock > 0 or (v_branches and exists (
            select 1 from public.branch_stock bs join public.branches b on b.id = bs.branch_id
             where bs.product_id = pp.id and bs.stock > 0 and b.status = 'ACTIVE' and public.branch_usable(b.id))))
        order by lower(coalesce(pp.category, '')), lower(pp.name)
        limit 500
      ) p
    ), '[]'::jsonb)
  );
end;
$$;
grant execute on function public.get_public_store(text) to anon, authenticated;
