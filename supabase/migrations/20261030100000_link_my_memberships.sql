-- Fase 1 · Etapa 3 (parte previa): se aplica antes de publicar la versión de la
-- app que la usa, igual que las funciones de la Etapa 2. No activa RLS.
--
-- Vincula las membresías de la cuenta en sesión con su id de la app y, si se
-- indica, actualiza su nombre. Reemplaza los UPDATE directos de la app, que con
-- RLS permitirían cambiarse el propio rol.
create or replace function public.link_my_memberships(p_name text default null)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_email text := lower(auth.email());
  v_user_id text;
begin
  if auth.uid() is null or v_email is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  select u.id into v_user_id from public.users u where lower(u.email) = v_email limit 1;

  update public.business_members m
  set user_id = coalesce(v_user_id, m.user_id),
      user_name = coalesce(nullif(trim(p_name), ''), m.user_name)
  where lower(m.user_email) = v_email;
end;
$$;

revoke all on function public.link_my_memberships(text) from public, anon;
grant execute on function public.link_my_memberships(text) to authenticated;
