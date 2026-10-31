-- Stockealo Pro: administración desde la app (versión 0.9.1)
--
-- Permite a las cuentas de app_admins crear y ver códigos Pro desde Ajustes ›
-- Administrador, sin abrir el SQL de Supabase. Todo pasa por funciones que
-- comprueban en el servidor que quien llama es administrador; las tablas siguen
-- sin acceso directo.
-- No modifica tablas existentes.

-- ---------------------------------------------------------------------------
-- ¿La cuenta que llama es administradora?
-- ---------------------------------------------------------------------------
create or replace function public.is_app_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.app_admins
    where lower(email) = lower(coalesce(auth.jwt() ->> 'email', ''))
  );
$$;

revoke all on function public.is_app_admin() from public, anon;
grant execute on function public.is_app_admin() to authenticated;

-- ---------------------------------------------------------------------------
-- Crear códigos (máximo 50 por vez)
-- ---------------------------------------------------------------------------
create or replace function public.admin_create_pro_codes(
  p_kind text,
  p_days integer,
  p_count integer default 1,
  p_note text default null,
  p_max_uses integer default 1
)
returns setof text
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.is_app_admin() then
    raise exception 'admin_only';
  end if;
  if p_kind not in ('business', 'global') then
    raise exception 'invalid_kind';
  end if;
  if p_count is null or p_count < 1 or p_count > 50 then
    raise exception 'invalid_count';
  end if;
  if p_days is not null and (p_days < 1 or p_days > 3650) then
    raise exception 'invalid_days';
  end if;
  if p_max_uses is null or p_max_uses < 1 or p_max_uses > 1000 then
    raise exception 'invalid_max_uses';
  end if;
  return query
    select public.create_pro_codes(p_kind, p_days, p_count, nullif(trim(p_note), ''), p_max_uses);
end;
$$;

revoke all on function public.admin_create_pro_codes(text, integer, integer, text, integer) from public, anon;
grant execute on function public.admin_create_pro_codes(text, integer, integer, text, integer) to authenticated;

-- ---------------------------------------------------------------------------
-- Últimos códigos creados, con cuántas veces se usaron y quién los canjeó
-- ---------------------------------------------------------------------------
create or replace function public.admin_list_pro_codes(p_limit integer default 50)
returns table (
  code text,
  kind text,
  days integer,
  max_uses integer,
  uses integer,
  note text,
  created_at timestamptz,
  redeemed_by text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not public.is_app_admin() then
    raise exception 'admin_only';
  end if;
  return query
    select c.code, c.kind, c.days, c.max_uses, c.uses, c.note, c.created_at,
           (select string_agg(r.user_email, ', ' order by r.redeemed_at)
              from public.code_redemptions r where r.code = c.code)
      from public.pro_codes c
     order by c.created_at desc
     limit least(greatest(coalesce(p_limit, 50), 1), 200);
end;
$$;

revoke all on function public.admin_list_pro_codes(integer) from public, anon;
grant execute on function public.admin_list_pro_codes(integer) to authenticated;

-- ---------------------------------------------------------------------------
-- Primer administrador
-- ---------------------------------------------------------------------------
insert into public.app_admins (email) values ('byjosealbert@gmail.com')
on conflict (email) do nothing;
