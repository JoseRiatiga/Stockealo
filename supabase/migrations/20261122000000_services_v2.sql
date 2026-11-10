-- Stockealo 0.12.0: módulo Servicios v2
--
--   • services.prices: precio por tipo de vehículo (lavadero: MOTO, CARRO, CAMIONETA).
--     Vacío = un solo precio (services.price). Un tipo que no aparece no se ofrece.
--   • services.staff_ids: empleados que pueden hacer cada servicio.
--   • work_orders.vehicle_kind: tipo de vehículo de cada trabajo.
--   • work_orders.lines ya es JSON: cada línea guarda ahora su estado
--     (PENDIENTE, PROCESO, TERMINADO) y sus horas; no cambia la columna.
--   • staff_attendance: asistencia del día (llegó o no vino, salida y pausas).
--     La marcan los miembros del negocio (el cajero lleva el tablero); borrar,
--     solo el dueño o un administrador.
-- No borra ni cambia datos existentes.

alter table public.services add column if not exists prices jsonb not null default '{}'::jsonb;
alter table public.services add column if not exists staff_ids jsonb not null default '[]'::jsonb;
alter table public.work_orders add column if not exists vehicle_kind text;

create table if not exists public.staff_attendance (
  id text primary key,
  business_id text not null references public.businesses (id) on delete cascade,
  staff_id text not null references public.staff (id) on delete cascade,
  day date not null,
  status text not null default 'LLEGO' check (status in ('LLEGO', 'NO_VINO')),
  arrived_at timestamptz,
  left_at timestamptz,
  pauses jsonb not null default '[]'::jsonb,
  updated_at timestamptz not null default now(),
  unique (business_id, staff_id, day)
);
create index if not exists idx_staff_attendance_business_day on public.staff_attendance (business_id, day desc);

alter table public.staff_attendance enable row level security;

drop policy if exists staff_attendance_select on public.staff_attendance;
create policy staff_attendance_select on public.staff_attendance for select to authenticated
  using (public.my_business_role(business_id) is not null);
drop policy if exists staff_attendance_insert on public.staff_attendance;
create policy staff_attendance_insert on public.staff_attendance for insert to authenticated
  with check (public.my_business_role(business_id) is not null);
drop policy if exists staff_attendance_update on public.staff_attendance;
create policy staff_attendance_update on public.staff_attendance for update to authenticated
  using (public.my_business_role(business_id) is not null)
  with check (public.my_business_role(business_id) is not null);
drop policy if exists staff_attendance_delete on public.staff_attendance;
create policy staff_attendance_delete on public.staff_attendance for delete to authenticated
  using (public.my_business_role(business_id) = any (array['OWNER', 'ADMIN']));

revoke all on public.staff_attendance from anon;
grant select, insert, update, delete on public.staff_attendance to authenticated;
