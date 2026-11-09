-- Servicios, empleados y tablero de órdenes (versión 0.11.0: lavaderos y negocios de servicios)
--
--   • businesses.services_enabled / service_type: el negocio ofrece servicios
--     (LAVADERO_MOTOS, BARBERIA, TALLER u OTRO)
--   • services: catálogo de servicios con precio, duración y % de comisión
--   • staff: empleados (personas, no necesitan cuenta) con su % de comisión
--   • work_orders: tablero de órdenes (placa, cliente, servicios con sus empleados,
--     estado con la hora de cada cambio, total, propina y ventas que generó)
--   • sales: service_id, work_order_id y staff_ids para las líneas de servicio
--     (product_id queda vacío, como ya permite la tabla)
--   • Acceso: ven los miembros del negocio. Servicios y empleados los cambian el
--     dueño o un administrador; las órdenes las crea y mueve cualquier miembro
--     (el cajero lleva el tablero) y solo el dueño o un administrador las borra.
-- No borra ni cambia datos existentes.

alter table public.businesses add column if not exists services_enabled boolean not null default false;
alter table public.businesses add column if not exists service_type text;

alter table public.sales add column if not exists service_id text;
alter table public.sales add column if not exists work_order_id text;
alter table public.sales add column if not exists staff_ids text;

create table if not exists public.services (
  id text primary key,
  business_id text not null references public.businesses (id) on delete cascade,
  name text not null,
  price numeric not null default 0,
  duration_min integer,
  commission_pct numeric not null default 0 check (commission_pct >= 0 and commission_pct <= 100),
  is_active boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists idx_services_business on public.services (business_id);

create table if not exists public.staff (
  id text primary key,
  business_id text not null references public.businesses (id) on delete cascade,
  name text not null,
  phone text,
  document text,
  commission_pct numeric check (commission_pct is null or (commission_pct >= 0 and commission_pct <= 100)),
  is_active boolean not null default true,
  member_email text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists idx_staff_business on public.staff (business_id);

create table if not exists public.work_orders (
  id text primary key,
  business_id text not null references public.businesses (id) on delete cascade,
  number text not null,
  plate text,
  vehicle text,
  customer_name text,
  customer_phone text,
  status text not null default 'ESPERA'
    check (status in ('ESPERA', 'PROCESO', 'LISTA', 'ENTREGADA', 'CANCELADA')),
  lines jsonb not null default '[]'::jsonb,
  notes text,
  status_times jsonb not null default '{}'::jsonb,
  total numeric not null default 0,
  discount numeric not null default 0,
  tip numeric not null default 0,
  payment_method text,
  sale_ids jsonb not null default '[]'::jsonb,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists idx_work_orders_business on public.work_orders (business_id, created_at desc);
create index if not exists idx_work_orders_plate on public.work_orders (business_id, plate);

alter table public.services enable row level security;
alter table public.staff enable row level security;
alter table public.work_orders enable row level security;

-- Servicios y empleados: ven todos los miembros; cambian dueño o administrador
drop policy if exists services_select on public.services;
create policy services_select on public.services for select to authenticated
  using (public.my_business_role(business_id) is not null);
drop policy if exists services_write on public.services;
create policy services_write on public.services for all to authenticated
  using (public.my_business_role(business_id) = any (array['OWNER', 'ADMIN']))
  with check (public.my_business_role(business_id) = any (array['OWNER', 'ADMIN']));

drop policy if exists staff_select on public.staff;
create policy staff_select on public.staff for select to authenticated
  using (public.my_business_role(business_id) is not null);
drop policy if exists staff_write on public.staff;
create policy staff_write on public.staff for all to authenticated
  using (public.my_business_role(business_id) = any (array['OWNER', 'ADMIN']))
  with check (public.my_business_role(business_id) = any (array['OWNER', 'ADMIN']));

-- Órdenes: cualquier miembro las crea y las mueve; borrar, solo dueño o administrador
drop policy if exists work_orders_select on public.work_orders;
create policy work_orders_select on public.work_orders for select to authenticated
  using (public.my_business_role(business_id) is not null);
drop policy if exists work_orders_insert on public.work_orders;
create policy work_orders_insert on public.work_orders for insert to authenticated
  with check (public.my_business_role(business_id) is not null);
drop policy if exists work_orders_update on public.work_orders;
create policy work_orders_update on public.work_orders for update to authenticated
  using (public.my_business_role(business_id) is not null)
  with check (public.my_business_role(business_id) is not null);
drop policy if exists work_orders_delete on public.work_orders;
create policy work_orders_delete on public.work_orders for delete to authenticated
  using (public.my_business_role(business_id) = any (array['OWNER', 'ADMIN']));
