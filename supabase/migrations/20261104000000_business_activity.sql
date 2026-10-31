-- Registro de actividad del equipo (versión 0.9.0)
--
-- Cada acción importante (venta, cambio de precio, ajuste de stock, abono, caja, equipo)
-- queda anotada con quién la hizo. Sirve de control para el dueño, así que:
--   • solo los miembros del negocio anotan, y solo a su propio nombre (el correo se
--     compara con el de la sesión)
--   • solo el dueño y los administradores la leen
--   • nadie la edita ni la borra; desaparece solo si se borra el negocio
-- No modifica tablas existentes.

create table if not exists public.business_activity (
  id text primary key,
  business_id text not null references public.businesses (id) on delete cascade,
  actor_email text not null default auth.email(),
  actor_name text,
  action text not null check (action ~ '^[a-z_]{2,40}$'),
  summary text not null check (char_length(summary) <= 300),
  data jsonb,
  created_at timestamptz not null default now()
);

create index if not exists business_activity_business_created_idx
  on public.business_activity (business_id, created_at desc);

alter table public.business_activity enable row level security;

drop policy if exists activity_select on public.business_activity;
create policy activity_select on public.business_activity for select to authenticated
  using (public.my_business_role(business_id) in ('OWNER', 'ADMIN'));

drop policy if exists activity_insert on public.business_activity;
create policy activity_insert on public.business_activity for insert to authenticated
  with check (
    public.my_business_role(business_id) is not null
    and lower(actor_email) = lower(auth.email())
  );

-- Sin políticas de update ni delete: el registro no se puede alterar

revoke all on public.business_activity from anon;
grant select, insert on public.business_activity to authenticated;
