-- Fase 1 · Etapa 2: funciones del servidor que reemplazan lecturas de tablas completas.
--
-- Hoy la app descarga todas las empresas para buscar un código de invitación y lee
-- public.users directamente. Con RLS (Etapa 3) esas lecturas quedarán bloqueadas,
-- así que estas operaciones pasan a funciones SECURITY DEFINER que solo devuelven
-- lo mínimo y solo a usuarios autenticados.

-- Busca un usuario registrado para vincularlo al invitarlo a un negocio.
create or replace function public.find_user_by_email(p_email text)
returns table (id text, name text)
language sql
stable
security definer
set search_path = ''
as $$
  select u.id, u.name
  from public.users u
  where auth.uid() is not null
    and lower(u.email) = lower(trim(p_email))
  limit 1;
$$;

revoke all on function public.find_user_by_email(text) from public, anon;
grant execute on function public.find_user_by_email(text) to authenticated;

-- Une a la cuenta en sesión a un negocio con su código de invitación (los primeros
-- 8+ caracteres hex del id, o el id completo). Entra como CASHIER; si ya estaba
-- invitada por correo, conserva su rol y solo se vincula su user_id.
create or replace function public.join_business_by_code(p_code text)
returns json
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_email text := lower(auth.email());
  v_code text := lower(regexp_replace(coalesce(p_code, ''), '[^0-9a-fA-F]', '', 'g'));
  v_matches int;
  v_biz public.businesses;
  v_user public.users;
  v_member public.business_members;
begin
  if auth.uid() is null or v_email is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if length(v_code) < 8 then
    raise exception 'invalid_code' using errcode = '22023';
  end if;

  select count(*) into v_matches
  from public.businesses b
  where b.is_deleted = 0 and replace(lower(b.id), '-', '') like v_code || '%';
  if v_matches <> 1 then
    raise exception 'code_not_found' using errcode = 'P0002';
  end if;

  select * into v_biz
  from public.businesses b
  where b.is_deleted = 0 and replace(lower(b.id), '-', '') like v_code || '%';

  select * into v_user from public.users u where lower(u.email) = v_email limit 1;

  select * into v_member
  from public.business_members m
  where m.business_id = v_biz.id and lower(m.user_email) = v_email
  limit 1;

  if found then
    update public.business_members
    set user_id = coalesce(v_user.id, user_id)
    where id = v_member.id
    returning * into v_member;
  else
    insert into public.business_members (id, business_id, user_id, user_email, user_name, role, created_at)
    values (
      gen_random_uuid()::text,
      v_biz.id,
      coalesce(v_user.id, auth.uid()::text),
      v_email,
      coalesce(nullif(trim(v_user.name), ''), split_part(v_email, '@', 1)),
      'CASHIER',
      now()
    )
    returning * into v_member;
  end if;

  return json_build_object(
    'business', json_build_object(
      'id', v_biz.id,
      'name', v_biz.name,
      'currency', v_biz.currency,
      'created_at', v_biz.created_at
    ),
    'owner_user_id', (
      select m.user_id from public.business_members m
      where m.business_id = v_biz.id and m.role = 'OWNER'
      order by m.created_at
      limit 1
    ),
    'member', json_build_object(
      'id', v_member.id,
      'user_id', v_member.user_id,
      'user_email', v_member.user_email,
      'user_name', v_member.user_name,
      'role', v_member.role,
      'created_at', v_member.created_at
    )
  );
end;
$$;

revoke all on function public.join_business_by_code(text) from public, anon;
grant execute on function public.join_business_by_code(text) to authenticated;
