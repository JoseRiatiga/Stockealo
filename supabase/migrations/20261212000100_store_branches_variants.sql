-- 0.18.3 · Tienda por sede, corrección (24 nov) de 20261212000000_store_branches:
-- • Con tallas o colores, el total de una sede es la suma de sus variantes (igual que
--   la app); antes se sumaba también la fila general y podía contar doble.
-- • Cada talla o color trae su stock por sede ('branch_stock'), para que en una sede se
--   vea agotada o disponible según esa sede y no según la Principal.
-- • Con el stock oculto se manda un nivel y no el número: 0 = agotado, 1 = quedan pocas
--   (1 a 3), 4 = hay. Antes 1 = hay y la tienda decía «quedan pocas» en todo.

-- El número que ve la tienda: exacto si muestra el stock; si no, el nivel
create or replace function public._store_level(n integer, p_show boolean)
returns integer
language sql
immutable
set search_path = ''
as $$
  select case when p_show then greatest(n, 0) when n <= 0 then 0 when n <= 3 then 1 else 4 end;
$$;

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
        -- la tienda muestra el stock; si no, el nivel de _store_level.
        'branch_stock', case when v_branches then (
          select jsonb_object_agg(k, public._store_level(n, v_store.show_stock))
            from (
              select '' as k, greatest(p.current_stock, 0)::int as n
              union all
              select bs.branch_id, greatest(case when bool_or(bs.variant_key <> '')
                                                 then sum(bs.stock) filter (where bs.variant_key <> '')
                                                 else sum(bs.stock) end, 0)::int
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
            'few', v.stock between 1 and 3,
            'branch_stock', case when v_branches then (
              select jsonb_object_agg(k, public._store_level(n, v_store.show_stock))
                from (
                  select '' as k, greatest(v.stock, 0)::int as n
                  union all
                  select bs.branch_id, greatest(bs.stock, 0)::int
                    from public.branch_stock bs
                    join public.branches b on b.id = bs.branch_id
                   where bs.product_id = p.id and bs.variant_key = v.id
                     and b.status = 'ACTIVE' and public.branch_usable(b.id)
                ) s
            ) end
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
