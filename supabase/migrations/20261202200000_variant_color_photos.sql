-- 0.15.0: una foto por color (pedido del dueño, 14 nov 2026). Cada variante guarda la
-- foto de su color (todas las tallas de ese color tienen la misma). null = se usa la
-- foto principal del producto.

alter table public.product_variants add column if not exists image_url text;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'product_variants_image_url_https') then
    alter table public.product_variants
      add constraint product_variants_image_url_https check (image_url is null or image_url like 'https://%');
  end if;
end;
$$;

-- La tienda pública devuelve la foto de cada variante. Se suma 'image' junto a 'hex'
-- sin reescribir el resto (la versión vigente de get_public_store es la de
-- 20261130300000_promotions.sql, con la portada de 20261202000000_store_cover.sql).
do $$
declare
  v_def text;
begin
  v_def := pg_get_functiondef('public.get_public_store(text)'::regprocedure);
  if position('v.image_url' in v_def) = 0 then
    if position('''hex'', v.color_hex,' in v_def) = 0 then
      raise exception 'No se encontró hex en get_public_store';
    end if;
    v_def := replace(
      v_def,
      '''hex'', v.color_hex,',
      '''hex'', v.color_hex, ''image'', case when v.image_url like ''https://%'' then v.image_url end,'
    );
    execute v_def;
  end if;
end;
$$;

-- La limpieza de archivos sin uso respeta también las fotos de los colores
create or replace function public.admin_orphan_files()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_result jsonb;
begin
  if not public.is_app_admin() then
    raise exception 'not_admin';
  end if;

  with orphans as (
    select o.bucket_id, o.name, coalesce((o.metadata ->> 'size')::bigint, 0) as size
    from storage.objects o
    where o.created_at < now() - interval '1 day'
      and (
        (o.bucket_id = 'product-images'
          and not exists (select 1 from public.products p where p.image_url like '%/product-images/' || o.name || '%')
          and not exists (select 1 from public.product_variants pv where pv.image_url like '%/product-images/' || o.name || '%')
          and not exists (select 1 from public.businesses b where b.logo_url like '%/product-images/' || o.name || '%')
          and not exists (select 1 from public.online_stores s where s.hero_image_url like '%/product-images/' || o.name || '%')
          and not exists (select 1 from public.work_orders w where w.extra::text like '%/product-images/' || o.name || '%'))
        or
        (o.bucket_id = 'purchase-invoices'
          and not exists (select 1 from public.purchases pu where pu.photo_path = o.name))
      )
  )
  select jsonb_build_object(
    'count', count(*),
    'bytes', coalesce(sum(size), 0),
    'files', coalesce(jsonb_agg(jsonb_build_object('bucket', bucket_id, 'name', name)), '[]'::jsonb)
  ) into v_result
  from orphans;

  return v_result;
end;
$$;

revoke all on function public.admin_orphan_files() from public, anon;
grant execute on function public.admin_orphan_files() to authenticated;
