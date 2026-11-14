-- 0.13.3: existencias en la tienda como Nike (decisión del dueño, 14 nov 2026)
--   • Las tallas y colores agotados también se mandan, con 'sold_out': la tienda los
--     muestra tachados y no se pueden elegir.
--   • 'few' (3 o menos) se manda siempre: la tienda dice «Quedan pocas, pide pronto»
--     sin decir el número. El número solo va si el negocio activó «Mostrar existencias».
--   • Los productos sin existencias siguen sin mostrarse.

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
begin
  select * into v_store from public.online_stores where slug = lower(trim(coalesce(p_slug, '')));
  if not found or not v_store.enabled then
    return null;
  end if;
  select * into v_business from public.businesses where id = v_store.business_id;
  if not found or coalesce(v_business.is_deleted, 0) = 1 then
    return null;
  end if;
  -- Sin Pro activo la tienda se apaga sola
  if not coalesce((public.business_pro_until(v_store.business_id) ->> 'active')::boolean, false) then
    return null;
  end if;

  return jsonb_build_object(
    'slug', v_store.slug,
    'whatsapp', v_store.whatsapp,
    'welcome', v_store.welcome,
    'template', v_store.template,
    'hero_title', v_store.hero_title,
    'business', jsonb_build_object(
      'name', v_business.name,
      'logo_url', v_business.logo_url,
      'color', v_business.color,
      'currency', v_business.currency,
      'country', v_business.country
    ),
    'products', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', p.id,
        'name', p.name,
        'category', p.category,
        'price', p.sale_price,
        'old_price', case when p.compare_price > p.sale_price then p.compare_price end,
        'image_url', case when p.image_url like 'https://%' then p.image_url end,
        'stock', case when v_store.show_stock then p.current_stock end,
        'few', p.current_stock <= 3,
        'variants', coalesce((
          select jsonb_agg(jsonb_build_object(
            'id', v.id,
            'size', nullif(trim(v.attribute_value), ''),
            'color', nullif(trim(coalesce(v.attribute2_value, '')), ''),
            'hex', v.color_hex,
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
        select * from public.products
        where business_id = v_store.business_id and current_stock > 0 and sale_price > 0
        order by lower(coalesce(category, '')), lower(name)
        limit 500
      ) p
    ), '[]'::jsonb)
  );
end;
$$;

revoke all on function public.get_public_store(text) from public;
grant execute on function public.get_public_store(text) to anon, authenticated;
