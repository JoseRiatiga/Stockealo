-- 0.18.7: orden de las tallas (docs/plan-0.18.7.md, A1).
-- El dueño ordena las tallas arrastrando al crear o editar un producto; ese orden se
-- guarda en sort_order y se respeta en todos lados. Las variantes que ya existen
-- quedan en null y siguen saliendo por created_at, como hasta hoy: nada cambia de
-- lugar hasta que alguien mueva una talla. Las apps viejas no mandan la columna
-- (el upsert no la toca), y lo que crean sale al final.

alter table public.product_variants add column if not exists sort_order integer;

comment on column public.product_variants.sort_order is
  'Posición de la variante en su producto (0.18.7). null = orden por created_at.';

-- La tienda en línea: mismo orden que en la app. Se cambia solo la línea del orden
-- de las variantes dentro de get_public_store (la función es larga y ya cambió en
-- varias migraciones; así no se copia entera y no se pisa nada más).
do $$
declare
  v_def text := pg_get_functiondef('public.get_public_store'::regproc);
  v_old text := ') order by v.created_at)';
  v_new text := ') order by v.sort_order nulls last, v.created_at)';
begin
  if position(v_new in v_def) > 0 then
    return; -- ya aplicada
  end if;
  if (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old) <> 1 then
    raise exception 'get_public_store: no se encontró una sola vez el orden de las variantes';
  end if;
  execute replace(v_def, v_old, v_new);
end
$$;
