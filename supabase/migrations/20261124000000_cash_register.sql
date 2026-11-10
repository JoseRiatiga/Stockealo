-- Stockealo 0.12.0: arqueo de caja en la nube
--
--   • cash_sessions: turnos de caja (base, apertura, cierre, efectivo esperado y
--     contado, nota y resumen del cierre por forma de pago). Hasta la 0.11.0 solo
--     existían en el celular.
--   • cash_movements: entradas y salidas de efectivo a mano (gasto, retiro, pago a
--     proveedor, propina entregada…).
--   • Acceso: los miembros del negocio abren, cierran y registran movimientos (el
--     cajero lleva la caja); borrar, solo el dueño o un administrador.
-- No borra ni cambia datos existentes.

create table if not exists public.cash_sessions (
  id text primary key,
  business_id text not null references public.businesses (id) on delete cascade,
  opened_by text not null,
  opened_at timestamptz not null,
  opening_amount numeric not null default 0 check (opening_amount >= 0),
  closed_at timestamptz,
  closed_by text,
  expected_amount numeric,
  counted_amount numeric check (counted_amount is null or counted_amount >= 0),
  notes text,
  summary jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);
create index if not exists idx_cash_sessions_business on public.cash_sessions (business_id, opened_at desc);

create table if not exists public.cash_movements (
  id text primary key,
  business_id text not null references public.businesses (id) on delete cascade,
  session_id text not null references public.cash_sessions (id) on delete cascade,
  kind text not null check (kind in ('ENTRADA', 'SALIDA')),
  reason text not null,
  amount numeric not null check (amount > 0),
  note text,
  created_by text,
  date timestamptz not null
);
create index if not exists idx_cash_movements_session on public.cash_movements (session_id);

alter table public.cash_sessions enable row level security;
alter table public.cash_movements enable row level security;

drop policy if exists cash_sessions_select on public.cash_sessions;
create policy cash_sessions_select on public.cash_sessions for select to authenticated
  using (public.my_business_role(business_id) is not null);
drop policy if exists cash_sessions_insert on public.cash_sessions;
create policy cash_sessions_insert on public.cash_sessions for insert to authenticated
  with check (public.my_business_role(business_id) is not null);
drop policy if exists cash_sessions_update on public.cash_sessions;
create policy cash_sessions_update on public.cash_sessions for update to authenticated
  using (public.my_business_role(business_id) is not null)
  with check (public.my_business_role(business_id) is not null);
drop policy if exists cash_sessions_delete on public.cash_sessions;
create policy cash_sessions_delete on public.cash_sessions for delete to authenticated
  using (public.my_business_role(business_id) = any (array['OWNER', 'ADMIN']));

drop policy if exists cash_movements_select on public.cash_movements;
create policy cash_movements_select on public.cash_movements for select to authenticated
  using (public.my_business_role(business_id) is not null);
drop policy if exists cash_movements_insert on public.cash_movements;
create policy cash_movements_insert on public.cash_movements for insert to authenticated
  with check (public.my_business_role(business_id) is not null);
drop policy if exists cash_movements_update on public.cash_movements;
create policy cash_movements_update on public.cash_movements for update to authenticated
  using (public.my_business_role(business_id) = any (array['OWNER', 'ADMIN']))
  with check (public.my_business_role(business_id) = any (array['OWNER', 'ADMIN']));
drop policy if exists cash_movements_delete on public.cash_movements;
create policy cash_movements_delete on public.cash_movements for delete to authenticated
  using (public.my_business_role(business_id) = any (array['OWNER', 'ADMIN']));

revoke all on public.cash_sessions from anon;
revoke all on public.cash_movements from anon;
grant select, insert, update, delete on public.cash_sessions to authenticated;
grant select, insert, update, delete on public.cash_movements to authenticated;
