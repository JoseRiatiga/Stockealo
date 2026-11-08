-- Variantes de producto en la nube (versión 0.9.3)
--
-- Hasta ahora las variantes (tallas, colores…) vivían solo en el dispositivo:
-- no existía tabla en Supabase y `products` no guardaba `has_variants` ni la
-- descripción. Al descargar de la nube, el producto se reescribía sin esos datos
-- y las variantes desaparecían de la app.
--
--   • products: has_variants y description
--   • product_variants: hasta DOS datos por variante (ej. Talla M + Color Rojo),
--     con muestra de color (1 o 2 tonos, o multicolor), existencias propias,
--     código y precio adicional
--   • Mismas reglas de acceso que products: ven los miembros del negocio; crean y
--     borran el dueño o un administrador; actualizan los miembros (las ventas de un
--     cajero descuentan existencias de la variante)
--   • adjust_variant_stock: descuenta o suma por diferencia, como adjust_product_stock,
--     para que dos ventas al mismo tiempo no se pisen
-- No borra ni cambia datos existentes.

alter table public.products add column if not exists has_variants boolean not null default false;
alter table public.products add column if not exists description text;

create table if not exists public.product_variants (
  id text primary key,
  business_id text not null,
  product_id text not null references public.products(id) on delete cascade,
  attribute_name text not null default 'Talla',
  attribute_value text not null default '',
  attribute2_name text,
  attribute2_value text,
  -- Muestra del color (#RRGGBB); la segunda, para prendas de dos tonos.
  -- 'multi' en color_hex = estampado o multicolor.
  color_hex text check (color_hex is null or color_hex ~ '^(#[0-9A-Fa-f]{6}|multi)$'),
  color_hex2 text check (color_hex2 is null or color_hex2 ~ '^#[0-9A-Fa-f]{6}$'),
  sku_or_barcode text,
  stock integer not null default 0,
  additional_price numeric not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_product_variants_product on public.product_variants(product_id);
create index if not exists idx_product_variants_business on public.product_variants(business_id);

alter table public.product_variants enable row level security;

drop policy if exists product_variants_select on public.product_variants;
create policy product_variants_select on public.product_variants
  for select to authenticated
  using (public.my_business_role(business_id) is not null);

drop policy if exists product_variants_insert on public.product_variants;
create policy product_variants_insert on public.product_variants
  for insert to authenticated
  with check (public.my_business_role(business_id) = any (array['OWNER', 'ADMIN']));

drop policy if exists product_variants_update on public.product_variants;
create policy product_variants_update on public.product_variants
  for update to authenticated
  using (public.my_business_role(business_id) is not null)
  with check (public.my_business_role(business_id) is not null);

drop policy if exists product_variants_delete on public.product_variants;
create policy product_variants_delete on public.product_variants
  for delete to authenticated
  using (public.my_business_role(business_id) = any (array['OWNER', 'ADMIN']));

-- Ajuste por diferencia (venta, anulación). Nunca deja existencias negativas.
-- Como adjust_product_stock: corre con los permisos de quien llama (RLS aplica).
create or replace function public.adjust_variant_stock(p_variant_id text, p_delta integer)
returns void
language sql
security invoker
set search_path = ''
as $$
  update public.product_variants
     set stock = greatest(0, stock + p_delta), updated_at = now()
   where id = p_variant_id;
$$;

revoke all on function public.adjust_variant_stock(text, integer) from public, anon;
grant execute on function public.adjust_variant_stock(text, integer) to authenticated;
