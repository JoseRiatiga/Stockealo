-- 0.16.0, fase 6: verificación en dos pasos OBLIGATORIA en el panel de administración.
--
-- ⚠ Aplicar SOLO después de publicar la web nueva del panel (la que pide el código).
--   El panel viejo no sabe pedirlo y, con esto, dejaría de funcionar.
--
-- • is_app_admin_listed(): «está en la lista de administradores» (sin el código). Lo usa
--   el panel al entrar para saber si debe pedir o activar la verificación.
-- • is_app_admin() y admin_role(): ahora además exigen la sesión con el código
--   (aal2). Todas las funciones del panel pasan por ellas (admin_guard, admin_require,
--   admin_orphan_files…), así que sin el código ninguna responde, aunque alguien tenga
--   la contraseña. Las funciones de la nube del panel (storage-cleanup, daily-backup)
--   usan el token de quien llama: también lo exigen.

create or replace function public.is_app_admin_listed()
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
revoke all on function public.is_app_admin_listed() from public, anon;
grant execute on function public.is_app_admin_listed() to authenticated;

create or replace function public.is_app_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(auth.jwt() ->> 'aal', '') = 'aal2' and exists (
    select 1 from public.app_admins
    where lower(email) = lower(coalesce(auth.jwt() ->> 'email', ''))
  );
$$;

create or replace function public.admin_role()
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select a.role from public.app_admins a
   where lower(a.email) = lower(coalesce(auth.jwt() ->> 'email', ''))
     and coalesce(auth.jwt() ->> 'aal', '') = 'aal2'
   limit 1;
$$;
