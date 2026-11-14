-- 0.13.4: el negocio elige si la portada de la tienda muestra fotos de sus productos
-- (pedido del dueño, 14 nov 2026). Encendido por defecto, como hasta ahora.

alter table public.online_stores add column if not exists hero_photos boolean not null default true;

create or replace function public.get_my_store(p_business_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_store public.online_stores;
begin
  if public.my_business_role(p_business_id) is null then
    raise exception 'not_member';
  end if;
  select * into v_store from public.online_stores where business_id = p_business_id;
  if not found then
    return null;
  end if;
  return jsonb_build_object(
    'slug', v_store.slug,
    'enabled', v_store.enabled,
    'whatsapp', v_store.whatsapp,
    'welcome', v_store.welcome,
    'show_stock', v_store.show_stock,
    'template', v_store.template,
    'hero_title', v_store.hero_title,
    'hero_photos', v_store.hero_photos
  );
end;
$$;

-- Guardar con la opción de fotos (las versiones de 6 y 8 datos siguen para la app anterior)
create or replace function public.save_my_store(
  p_business_id text, p_slug text, p_enabled boolean, p_whatsapp text, p_welcome text, p_show_stock boolean,
  p_template text, p_hero_title text, p_hero_photos boolean
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform public.save_my_store(p_business_id, p_slug, p_enabled, p_whatsapp, p_welcome, p_show_stock, p_template, p_hero_title);
  update public.online_stores set hero_photos = coalesce(p_hero_photos, true), updated_at = now()
  where business_id = p_business_id;
  return public.get_my_store(p_business_id);
end;
$$;

revoke all on function public.save_my_store(text, text, boolean, text, text, boolean, text, text, boolean) from public, anon;
grant execute on function public.save_my_store(text, text, boolean, text, text, boolean, text, text, boolean) to authenticated;

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
    'hero_photos', v_store.hero_photos,
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
