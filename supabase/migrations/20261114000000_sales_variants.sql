-- Ventas de una talla o color en la nube (versión 0.9.5)
--
-- La venta ya guardaba el producto, pero no la variante: en otro equipo no se veía
-- "Blusa · M · Rojo" y al anularla la unidad no volvía a esa talla.
-- Solo agrega dos columnas opcionales; no cambia datos existentes.

alter table public.sales add column if not exists variant_id text;
alter table public.sales add column if not exists variant_name text;
