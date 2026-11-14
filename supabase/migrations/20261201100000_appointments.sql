-- 0.14.0: agenda de citas (barberías, peluquerías, spa y cualquier negocio de servicios).
-- Cualquier miembro del negocio agenda y atiende citas; las reservas en línea llegan
-- con estado PENDIENTE (función aparte).
create table if not exists public.appointments (
  id text primary key,
  business_id text not null references public.businesses (id) on delete cascade,
  customer_name text not null check (char_length(customer_name) between 1 and 80),
  customer_phone text,
  service_ids text,
  service_names text,
  staff_id text,
  starts_at timestamptz not null,
  duration_min integer not null default 30 check (duration_min between 5 and 600),
  status text not null default 'CONFIRMADA' check (status in ('PENDIENTE', 'CONFIRMADA', 'LLEGO', 'NO_VINO', 'CANCELADA')),
  source text not null default 'LOCAL' check (source in ('LOCAL', 'TIENDA')),
  notes text,
  work_order_id text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists idx_appointments_day on public.appointments (business_id, starts_at);

alter table public.appointments enable row level security;
drop policy if exists appointments_select on public.appointments;
create policy appointments_select on public.appointments for select to authenticated
  using (public.my_business_role(business_id) is not null);
drop policy if exists appointments_write on public.appointments;
create policy appointments_write on public.appointments for all to authenticated
  using (public.my_business_role(business_id) is not null)
  with check (public.my_business_role(business_id) is not null);

-- Las reservas en línea avisan al instante en la app
alter publication supabase_realtime add table public.appointments;
