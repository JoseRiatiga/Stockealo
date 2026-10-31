-- Uso de la IA de Stocky (versión 0.9.0)
--
-- ai_usage         preguntas a la IA por cuenta y día (zona horaria de Bogotá)
-- ai_usage_global  total de la app por día, para no pasar el cupo gratis de los proveedores
-- ai_cache         respuestas recientes: la misma pregunta con los mismos números no
--                  vuelve a llamar a la IA ni gasta del límite
--
-- Solo la Edge Function stocky-chat (con la llave de servicio) lee y escribe estas
-- tablas: tienen RLS activo y ninguna política, así que la app no puede tocarlas.
-- No modifica tablas existentes.

create table if not exists public.ai_usage (
  user_id uuid not null references auth.users (id) on delete cascade,
  day date not null,
  count integer not null default 0 check (count >= 0),
  primary key (user_id, day)
);

create table if not exists public.ai_usage_global (
  day date primary key,
  count integer not null default 0 check (count >= 0)
);

create table if not exists public.ai_cache (
  key text primary key,
  answer text not null,
  provider text not null,
  created_at timestamptz not null default now()
);

create index if not exists ai_cache_created_at_idx on public.ai_cache (created_at);

alter table public.ai_usage enable row level security;
alter table public.ai_usage_global enable row level security;
alter table public.ai_cache enable row level security;

revoke all on public.ai_usage, public.ai_usage_global, public.ai_cache from anon, authenticated;

-- Reserva una pregunta de forma atómica. Devuelve cuántas le quedan hoy a la cuenta,
-- o -1 si llegó a su límite, o -2 si la app llegó al tope global del día.
create or replace function public.ai_consume(p_user uuid, p_day date, p_user_limit integer, p_global_limit integer)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user integer;
  v_global integer;
begin
  insert into public.ai_usage_global as g (day, count) values (p_day, 0)
    on conflict (day) do nothing;
  insert into public.ai_usage as u (user_id, day, count) values (p_user, p_day, 0)
    on conflict (user_id, day) do nothing;

  select count into v_global from public.ai_usage_global where day = p_day for update;
  if v_global >= p_global_limit then
    return -2;
  end if;

  select count into v_user from public.ai_usage where user_id = p_user and day = p_day for update;
  if v_user >= p_user_limit then
    return -1;
  end if;

  update public.ai_usage set count = count + 1 where user_id = p_user and day = p_day;
  update public.ai_usage_global set count = count + 1 where day = p_day;
  return p_user_limit - v_user - 1;
end;
$$;

-- Devuelve la pregunta si ningún proveedor respondió (no se cobra un fallo)
create or replace function public.ai_refund(p_user uuid, p_day date)
returns void
language sql
security definer
set search_path = ''
as $$
  update public.ai_usage set count = greatest(count - 1, 0) where user_id = p_user and day = p_day;
  update public.ai_usage_global set count = greatest(count - 1, 0) where day = p_day;
$$;

revoke all on function public.ai_consume(uuid, date, integer, integer) from public, anon, authenticated;
revoke all on function public.ai_refund(uuid, date) from public, anon, authenticated;
grant execute on function public.ai_consume(uuid, date, integer, integer) to service_role;
grant execute on function public.ai_refund(uuid, date) to service_role;
