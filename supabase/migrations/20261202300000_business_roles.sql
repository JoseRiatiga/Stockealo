-- 0.15.0, etapa 2 de roles (docs/plan-roles.md): roles propios del negocio.
--
-- • business_roles guarda:
--   - los ajustes de los roles por defecto (builtin = 'ADMIN' o 'CASHIER'), por ejemplo
--     un Cajero que también ve costos;
--   - los roles propios (builtin = null), por ejemplo «Vendedor».
-- • perms: lista de claves de permisos (lib/core/permissions/permissions.dart).
-- • base_role: el rol que usa la nube para dejarlo trabajar ('ADMIN' o 'CASHIER').
--   Que la nube cumpla cada permiso por separado es el punto 7 de la 0.15.0.
-- • business_members.role_id: el rol propio de la persona; null = su rol por defecto.
--   La columna role sigue igual, así las versiones viejas de la app siguen funcionando.
-- Solo el dueño crea, cambia o borra roles; todo el equipo los puede leer.

create table if not exists public.business_roles (
  id text primary key,
  business_id text not null references public.businesses(id) on delete cascade,
  name text not null check (length(trim(name)) between 1 and 40),
  base_role text not null default 'CASHIER' check (base_role in ('ADMIN', 'CASHIER')),
  builtin text check (builtin in ('ADMIN', 'CASHIER')),
  perms jsonb not null default '[]'::jsonb check (jsonb_typeof(perms) = 'array'),
  template_id text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists business_roles_business_idx on public.business_roles (business_id);
create unique index if not exists business_roles_builtin_uq on public.business_roles (business_id, builtin)
  where builtin is not null;

alter table public.business_roles enable row level security;

drop policy if exists business_roles_select on public.business_roles;
create policy business_roles_select on public.business_roles
  for select to authenticated using (public.my_business_role(business_id) is not null);

drop policy if exists business_roles_insert on public.business_roles;
create policy business_roles_insert on public.business_roles
  for insert to authenticated with check (public.my_business_role(business_id) = 'OWNER');

drop policy if exists business_roles_update on public.business_roles;
create policy business_roles_update on public.business_roles
  for update to authenticated
  using (public.my_business_role(business_id) = 'OWNER')
  with check (public.my_business_role(business_id) = 'OWNER');

drop policy if exists business_roles_delete on public.business_roles;
create policy business_roles_delete on public.business_roles
  for delete to authenticated using (public.my_business_role(business_id) = 'OWNER');

alter table public.business_members
  add column if not exists role_id text references public.business_roles (id) on delete set null;
