-- 0.13.4: limpieza única de archivos que ya no usa nadie (pedido del dueño, 14 nov 2026).
-- Solo para el administrador de la app. Esta función solo CUENTA y LISTA; el borrado lo
-- hace la función storage-cleanup con permisos completos, después de confirmar.
--
-- Un archivo es huérfano si tiene más de un día (para no tocar una foto recién subida
-- cuyo producto todavía no llega a la nube) y además:
--   • product-images: ningún producto lo usa como foto y ningún negocio como logo.
--     Los negocios en la papelera siguen existiendo, así que sus archivos se respetan.
--   • purchase-invoices: ninguna compra lo tiene como foto de factura.

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
          and not exists (select 1 from public.businesses b where b.logo_url like '%/product-images/' || o.name || '%'))
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
