-- Fotos de productos desde un enlace (versión 0.9.3)
--
-- La función product-image trae la imagen de una página (Shein, Temu, Mercado
-- Libre…) y la copia a Storage. Esta tabla solo cuenta cuántas importaciones hizo
-- cada cuenta, para limitarlas por día. Sin políticas: solo la lee y escribe la
-- función con la llave de servicio; las cuentas no la ven.
-- No modifica tablas existentes.

create table if not exists public.image_imports (
  id bigint generated always as identity primary key,
  user_id uuid not null,
  created_at timestamptz not null default now()
);

create index if not exists idx_image_imports_user_time on public.image_imports(user_id, created_at desc);

alter table public.image_imports enable row level security;
