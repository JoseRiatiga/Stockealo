-- 0.18.4 · Registro sin código (plan aprobado el 24 nov, docs/plan-0.18.4.md)
--
-- Las cuentas nuevas pueden crearse sin probar el correo (función register-account).
-- Regla: una cuenta que no ha probado su correo nunca puede tener un correo al que le
-- corresponda algo. Aquí quedan las piezas de la nube:
--   * unverified_accounts: solo las cuentas creadas sin código.
--   * Reglas en business_members y app_admins: no se invita ni se da acceso a un correo
--     sin verificar (sí se puede crear el negocio propio).
--   * _register_check: register-account solo crea sin código si el correo no tiene nada.
--   * _session_methods: con qué entró la sesión (otp, oauth, password…), para verify-email.
--   * my_email_verified: lo que la app pregunta para mostrar el aviso.

-- ---------------------------------------------------------------------------
-- Cuentas sin verificar
-- ---------------------------------------------------------------------------
create table if not exists public.unverified_accounts (
  user_id uuid primary key references auth.users(id) on delete cascade,
  email text not null,
  created_at timestamptz not null default now()
);
alter table public.unverified_accounts enable row level security;
drop policy if exists "unverified_accounts: la propia" on public.unverified_accounts;
create policy "unverified_accounts: la propia" on public.unverified_accounts
  for select to authenticated using (user_id = auth.uid());
revoke all on public.unverified_accounts from anon;
revoke insert, update, delete on public.unverified_accounts from authenticated;

-- Mary (24 nov) se confirmó a mano sin probar el correo: queda sin verificar
insert into public.unverified_accounts (user_id, email)
select id, lower(email) from auth.users where id = 'c867b6a4-473b-453d-8bfe-5a3f9765c802'
on conflict (user_id) do nothing;

-- Intentos de registro sin código, para el límite por conexión
create table if not exists public.register_attempts (
  id bigint generated always as identity primary key,
  ip_hash text not null,
  at timestamptz not null default now()
);
create index if not exists register_attempts_ip_at on public.register_attempts (ip_hash, at);
alter table public.register_attempts enable row level security;
revoke all on public.register_attempts from anon, authenticated;

-- ¿Este correo pertenece a una cuenta sin verificar? (por el correo actual de la cuenta)
create or replace function public._email_unverified(p_email text)
returns boolean
language sql
stable
security definer
set search_path = public, auth
as $$
  select exists (
    select 1 from public.unverified_accounts u
      join auth.users a on a.id = u.user_id
     where lower(a.email) = lower(trim(p_email))
  );
$$;
revoke all on function public._email_unverified(text) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Reglas: nada se le da por correo a una cuenta sin verificar
-- ---------------------------------------------------------------------------
create or replace function public._block_unverified_member()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  if new.user_email is null or trim(new.user_email) = '' then return new; end if;
  if tg_op = 'UPDATE' and lower(coalesce(old.user_email, '')) = lower(new.user_email) then return new; end if;
  -- Su propio negocio sí: la fila de dueño con su propio correo
  if new.role = 'OWNER' and lower(new.user_email) = lower(coalesce(auth.email(), '')) then return new; end if;
  -- Misma llave que _register_mark: una invitación y un registro sin código del mismo
  -- correo no se cruzan (Codex, 24 nov)
  perform pg_advisory_xact_lock(hashtext('stockealo-register:' || lower(trim(new.user_email))));
  if public._email_unverified(new.user_email) then
    raise exception 'email_unverified' using hint = 'Esa persona debe verificar su correo en Stockealo antes de entrar al negocio.';
  end if;
  return new;
end;
$$;
revoke all on function public._block_unverified_member() from public, anon, authenticated;

drop trigger if exists business_members_block_unverified on public.business_members;
create trigger business_members_block_unverified
  before insert or update of user_email on public.business_members
  for each row execute function public._block_unverified_member();

create or replace function public._block_unverified_admin()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  if public._email_unverified(new.email) then
    raise exception 'email_unverified';
  end if;
  return new;
end;
$$;
revoke all on function public._block_unverified_admin() from public, anon, authenticated;

drop trigger if exists app_admins_block_unverified on public.app_admins;
create trigger app_admins_block_unverified
  before insert or update of email on public.app_admins
  for each row execute function public._block_unverified_admin();

-- ---------------------------------------------------------------------------
-- register-account: ¿se puede crear sin código?
--   'new'          → correo libre: crear la cuenta
--   'reuse:<id>'   → cuenta sin confirmar que nunca entró (la dejan las apps viejas al
--                    pedir el código): ponerle la contraseña
--   'code'         → ya tiene cuenta o algo le corresponde: registro con código
-- ---------------------------------------------------------------------------
create or replace function public._register_check(p_email text)
returns text
language plpgsql
stable
security definer
set search_path = public, auth
as $$
declare
  v_email text := lower(trim(p_email));
  v_user auth.users%rowtype;
begin
  if v_email is null or position('@' in v_email) = 0 then return 'code'; end if;

  -- Algo le corresponde a este correo: invitación, perfil, plan, pago, cupón, administrador
  if exists (select 1 from public.users where lower(email) = v_email)
     or exists (select 1 from public.business_members where lower(user_email) = v_email)
     or exists (select 1 from public.app_admins where lower(email) = v_email)
     or exists (select 1 from public.subscriptions where lower(owner_email) = v_email)
     or exists (select 1 from public.pro_payments where lower(user_email) = v_email)
     or exists (select 1 from public.code_redemptions where lower(user_email) = v_email)
     or exists (select 1 from public.staff where lower(member_email) = v_email) then
    return 'code';
  end if;

  select * into v_user from auth.users where lower(email) = v_email limit 1;
  if not found then return 'new'; end if;
  if v_user.email_confirmed_at is null and v_user.last_sign_in_at is null then
    return 'reuse:' || v_user.id::text;
  end if;
  return 'code';
end;
$$;
revoke all on function public._register_check(text) from public, anon, authenticated;
grant execute on function public._register_check(text) to service_role;

-- register-account: marca la cuenta como sin verificar, con la llave del correo tomada y
-- revisando otra vez que nada le corresponda (pudo llegar una invitación entre la primera
-- revisión y ahora). false = ya no se puede sin código.
create or replace function public._register_mark(p_user uuid, p_email text)
returns boolean
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_email text := lower(trim(p_email));
begin
  perform pg_advisory_xact_lock(hashtext('stockealo-register:' || v_email));
  if exists (select 1 from public.users where lower(email) = v_email)
     or exists (select 1 from public.business_members where lower(user_email) = v_email)
     or exists (select 1 from public.app_admins where lower(email) = v_email)
     or exists (select 1 from public.subscriptions where lower(owner_email) = v_email)
     or exists (select 1 from public.pro_payments where lower(user_email) = v_email)
     or exists (select 1 from public.code_redemptions where lower(user_email) = v_email)
     or exists (select 1 from public.staff where lower(member_email) = v_email) then
    return false;
  end if;
  insert into public.unverified_accounts (user_id, email) values (p_user, v_email)
  on conflict (user_id) do update set email = excluded.email;
  return true;
end;
$$;
revoke all on function public._register_mark(uuid, text) from public, anon, authenticated;
grant execute on function public._register_mark(uuid, text) to service_role;

-- Con qué entró esta sesión (lo guarda Supabase al iniciarla y no cambia al renovarla)
create or replace function public._session_methods(p_user uuid, p_session uuid)
returns text[]
language sql
stable
security definer
set search_path = auth
as $$
  select coalesce(array_agg(c.authentication_method::text), '{}')
    from auth.mfa_amr_claims c
    join auth.sessions s on s.id = c.session_id
   where c.session_id = p_session and s.user_id = p_user;
$$;
revoke all on function public._session_methods(uuid, uuid) from public, anon, authenticated;
grant execute on function public._session_methods(uuid, uuid) to service_role;

-- Para el aviso de la app
create or replace function public.my_email_verified()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select auth.uid() is not null
     and not exists (select 1 from public.unverified_accounts where user_id = auth.uid());
$$;
revoke all on function public.my_email_verified() from public, anon;
grant execute on function public.my_email_verified() to authenticated;

-- Antes de invitar: la app avisa al dueño si esa persona aún no verificó su correo.
-- Solo quien es dueño o administrador de algún negocio puede preguntar.
create or replace function public.member_email_unverified(p_email text)
returns boolean
language sql
stable
security definer
set search_path = public, auth
as $$
  select case
    when exists (
      select 1 from public.business_members m
       where lower(m.user_email) = lower(coalesce(auth.email(), ''))
         and m.role in ('OWNER', 'ADMIN')
    ) then public._email_unverified(p_email)
    else false
  end;
$$;
revoke all on function public.member_email_unverified(text) from public, anon;
grant execute on function public.member_email_unverified(text) to authenticated;
