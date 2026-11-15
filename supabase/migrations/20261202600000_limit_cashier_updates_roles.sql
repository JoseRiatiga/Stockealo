-- 0.15.0, punto 7: la revisión vieja limit_cashier_updates (de antes de los roles propios)
-- deshacía en silencio cualquier cambio del Cajero en ventas, incluso anular, y en
-- productos solo dejaba el stock. Con los roles propios eso tiene que decidirlo el
-- permiso, no el rol de la nube. Encontrado al probar 20261202500000_permissions_in_cloud.
--
-- • Ventas: ya las revisa _check_sale (anular necesita «Anular venta» y lo cobrado no se
--   cambia), así que aquí se dejan pasar.
-- • Productos: con «Crear y editar productos», cualquier cambio; solo con «Ajustar stock»,
--   únicamente el stock (como antes).

create or replace function public.limit_cashier_updates()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_stock integer;
begin
  if auth.uid() is null or tg_table_name <> 'products' then
    return new;
  end if;
  if public.has_permission(old.business_id, 'productsEdit') then
    return new;
  end if;
  v_stock := new.current_stock;
  new := old;
  new.current_stock := v_stock;
  return new;
end;
$$;
