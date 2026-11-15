-- 0.15.0: la limpieza de archivos sin uso respeta también la portada propia de la
-- tienda (online_stores.hero_image_url, 0.15.0) y las fotos de recepción de Servicios
-- (work_orders.extra -> photos, 0.14.0). Antes las veía como huérfanas y el botón de
-- limpieza del panel admin las habría borrado aunque se estuvieran usando.
-- Encontrado en la revisión de la 0.15.0.

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
