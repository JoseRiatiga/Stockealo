-- 0.15.0, etapa 3 de roles (docs/plan-roles.md):
-- • límites con números por rol (business_roles.limits);
-- • autorización de un solo uso, solo con internet (decisión del dueño, 14 nov 2026):
--   el cajero pide, el administrador o el dueño aprueba en su celular y la aprobación
--   sirve una sola vez durante 5 minutos.
-- Todo pasa por funciones del servidor: nadie se aprueba a sí mismo y solo el dueño o
-- un administrador deciden.

alter table public.business_roles add column if not exists limits jsonb not null default '{}'::jsonb;

create table if not exists public.auth_requests (
  id uuid primary key default gen_random_uuid(),
  business_id text not null references public.businesses(id) on delete cascade,
  number int not null,
  action text not null,
  detail text,
  amount numeric,
  requested_by uuid not null,
  requested_name text,
  status text not null default 'PENDIENTE' check (status in ('PENDIENTE', 'APROBADA', 'RECHAZADA', 'USADA')),
  decided_by uuid,
  decided_name text,
  decided_role text,
  created_at timestamptz not null default now(),
  decided_at timestamptz,
  expires_at timestamptz not null,
  used_at timestamptz
);

create index if not exists auth_requests_business_idx on public.auth_requests (business_id, created_at desc);

alter table public.auth_requests enable row level security;

drop policy if exists auth_requests_select on public.auth_requests;
create policy auth_requests_select on public.auth_requests
  for select to authenticated using (public.my_business_role(business_id) is not null);

-- Pedir: cualquiera del equipo; la solicitud vence en 10 minutos si nadie la decide
create or replace function public.create_auth_request(
  p_business_id text, p_action text, p_detail text, p_amount numeric, p_name text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row public.auth_requests;
begin
  if auth.uid() is null or public.my_business_role(p_business_id) is null then
    raise exception 'not_member';
  end if;
  insert into public.auth_requests (business_id, number, action, detail, amount, requested_by, requested_name, expires_at)
  values (
    p_business_id,
    1000 + floor(random() * 9000)::int,
    left(coalesce(p_action, ''), 120),
    left(p_detail, 400),
    p_amount,
    auth.uid(),
    left(p_name, 80),
    now() + interval '10 minutes'
  )
  returning * into v_row;
  return to_jsonb(v_row);
end;
$$;

-- Decidir: el dueño o un administrador, nunca quien pidió; la aprobación vale 5 minutos
create or replace function public.decide_auth_request(p_id uuid, p_approve boolean, p_name text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row public.auth_requests;
  v_role text;
begin
  select * into v_row from public.auth_requests where id = p_id for update;
  if not found then
    raise exception 'not_found';
  end if;
  v_role := public.my_business_role(v_row.business_id);
  if v_role is null or v_role not in ('OWNER', 'ADMIN') then
    raise exception 'not_allowed';
  end if;
  if v_row.requested_by = auth.uid() then
    raise exception 'own_request';
  end if;
  if v_row.status <> 'PENDIENTE' or v_row.expires_at < now() then
    raise exception 'not_pending';
  end if;
  update public.auth_requests
  set status = case when p_approve then 'APROBADA' else 'RECHAZADA' end,
      decided_by = auth.uid(),
      decided_name = left(p_name, 80),
      decided_role = v_role,
      decided_at = now(),
      expires_at = case when p_approve then now() + interval '5 minutes' else expires_at end
  where id = p_id
  returning * into v_row;
  return to_jsonb(v_row);
end;
$$;

-- Usar: solo quien pidió, una sola vez y antes de que venza
create or replace function public.use_auth_request(p_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count int;
begin
  update public.auth_requests
  set status = 'USADA', used_at = now()
  where id = p_id and requested_by = auth.uid() and status = 'APROBADA' and expires_at > now();
  get diagnostics v_count = row_count;
  return v_count = 1;
end;
$$;

revoke all on function public.create_auth_request(text, text, text, numeric, text) from public, anon;
revoke all on function public.decide_auth_request(uuid, boolean, text) from public, anon;
revoke all on function public.use_auth_request(uuid) from public, anon;
grant execute on function public.create_auth_request(text, text, text, numeric, text) to authenticated;
grant execute on function public.decide_auth_request(uuid, boolean, text) to authenticated;
grant execute on function public.use_auth_request(uuid) to authenticated;

-- Aviso al instante al que aprueba (y al que espera)
do $$
begin
  if not exists (
    select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'auth_requests'
  ) then
    alter publication supabase_realtime add table public.auth_requests;
  end if;
end;
$$;
