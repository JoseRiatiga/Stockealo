-- Panel de administrador (versión 0.9.2): resumen, usuarios, tiendas,
-- suscripciones, códigos y configuración de Pro.
--
-- Todo pasa por funciones que comprueban is_app_admin() en el servidor. El panel
-- solo ve datos de cuenta, planes, códigos y tiendas: nunca inventario, ventas ni
-- clientes de los negocios.
-- No modifica tablas existentes (solo reemplaza dos funciones de admin).

-- Error estándar para quien no es administrador
create or replace function public.admin_guard()
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not public.is_app_admin() then
    raise exception 'admin_only';
  end if;
end;
$$;
revoke all on function public.admin_guard() from public, anon, authenticated;

-- ¿El negocio tiene Pro ahora?
create or replace function public.admin_business_pro(p_business_id text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((public.business_pro_until(p_business_id) ->> 'active')::boolean, false);
$$;
revoke all on function public.admin_business_pro(text) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Resumen
-- ---------------------------------------------------------------------------
create or replace function public.admin_summary()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform public.admin_guard();
  return jsonb_build_object(
    'users_total', (select count(*) from auth.users),
    'users_7d', (select count(*) from auth.users where created_at > now() - interval '7 days'),
    'users_30d', (select count(*) from auth.users where created_at > now() - interval '30 days'),
    'businesses_total', (select count(*) from public.businesses where coalesce(is_deleted, 0) = 0),
    'businesses_pro', (select count(*) from public.businesses b
                         where coalesce(b.is_deleted, 0) = 0 and public.admin_business_pro(b.id)),
    'subscriptions_active', (select count(*) from public.subscriptions
                               where starts_at <= now() and (ends_at is null or ends_at > now())),
    'subscriptions_ending_7d', (select count(*) from public.subscriptions
                                  where ends_at > now() and ends_at < now() + interval '7 days'),
    'redemptions_30d', (select count(*) from public.code_redemptions where redeemed_at > now() - interval '30 days'),
    'codes_unused', (select count(*) from public.pro_codes
                       where uses < max_uses and (expires_at is null or expires_at > now())),
    'stores_total', (select count(*) from public.online_stores),
    'stores_live', (select count(*) from public.online_stores s
                      where s.enabled and public.admin_business_pro(s.business_id))
  );
end;
$$;
revoke all on function public.admin_summary() from public, anon;
grant execute on function public.admin_summary() to authenticated;

-- ---------------------------------------------------------------------------
-- Usuarios (cuentas)
-- ---------------------------------------------------------------------------
create or replace function public.admin_list_users(p_search text default null, p_limit integer default 100)
returns table (
  email text,
  name text,
  phone text,
  created_at timestamptz,
  last_sign_in_at timestamptz,
  businesses integer,
  pro boolean
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_q text := lower(trim(coalesce(p_search, '')));
begin
  perform public.admin_guard();
  return query
    select u.email::text,
           p.name,
           p.phone,
           u.created_at,
           u.last_sign_in_at,
           (select count(distinct m.business_id)::integer from public.business_members m
              join public.businesses b on b.id = m.business_id and coalesce(b.is_deleted, 0) = 0
             where lower(m.user_email) = lower(u.email)),
           exists (select 1 from public.business_members m
                    where lower(m.user_email) = lower(u.email) and public.admin_business_pro(m.business_id))
      from auth.users u
      left join public.users p on lower(p.email) = lower(u.email)
     where v_q = ''
        or lower(u.email) like '%' || v_q || '%'
        or lower(coalesce(p.name, '')) like '%' || v_q || '%'
        or coalesce(p.phone, '') like '%' || v_q || '%'
     order by u.created_at desc
     limit least(greatest(coalesce(p_limit, 100), 1), 500);
end;
$$;
revoke all on function public.admin_list_users(text, integer) from public, anon;
grant execute on function public.admin_list_users(text, integer) to authenticated;

-- ---------------------------------------------------------------------------
-- Negocios (para buscar a quién darle Pro)
-- ---------------------------------------------------------------------------
create or replace function public.admin_find_businesses(p_search text default null)
returns table (id text, name text, owner_email text, country text, pro boolean)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_q text := lower(trim(coalesce(p_search, '')));
begin
  perform public.admin_guard();
  return query
    select b.id, b.name,
           (select m.user_email from public.business_members m
             where m.business_id = b.id and m.role = 'OWNER' limit 1),
           b.country,
           public.admin_business_pro(b.id)
      from public.businesses b
     where coalesce(b.is_deleted, 0) = 0
       and (v_q = ''
            or lower(b.name) like '%' || v_q || '%'
            or exists (select 1 from public.business_members m
                        where m.business_id = b.id and lower(m.user_email) like '%' || v_q || '%'))
     order by b.created_at desc
     limit 50;
end;
$$;
revoke all on function public.admin_find_businesses(text) from public, anon;
grant execute on function public.admin_find_businesses(text) to authenticated;

-- ---------------------------------------------------------------------------
-- Tiendas en línea
-- ---------------------------------------------------------------------------
create or replace function public.admin_list_stores()
returns table (
  business_id text,
  business_name text,
  owner_email text,
  slug text,
  enabled boolean,
  pro boolean,
  products integer,
  updated_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform public.admin_guard();
  return query
    select s.business_id, b.name,
           (select m.user_email from public.business_members m
             where m.business_id = s.business_id and m.role = 'OWNER' limit 1),
           s.slug, s.enabled,
           public.admin_business_pro(s.business_id),
           (select count(*)::integer from public.products p
             where p.business_id = s.business_id and p.current_stock > 0 and p.sale_price > 0),
           s.updated_at
      from public.online_stores s
      join public.businesses b on b.id = s.business_id
     order by s.updated_at desc;
end;
$$;
revoke all on function public.admin_list_stores() from public, anon;
grant execute on function public.admin_list_stores() to authenticated;

-- ---------------------------------------------------------------------------
-- Suscripciones
-- ---------------------------------------------------------------------------
create or replace function public.admin_list_subscriptions(p_only_active boolean default true)
returns table (
  id uuid,
  kind text,
  business_id text,
  business_name text,
  owner_email text,
  source text,
  starts_at timestamptz,
  ends_at timestamptz,
  active boolean
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform public.admin_guard();
  return query
    select s.id, s.kind, s.business_id, b.name, s.owner_email, s.source, s.starts_at, s.ends_at,
           (s.starts_at <= now() and (s.ends_at is null or s.ends_at > now()))
      from public.subscriptions s
      left join public.businesses b on b.id = s.business_id
     where not coalesce(p_only_active, true)
        or (s.starts_at <= now() and (s.ends_at is null or s.ends_at > now()))
     order by (s.ends_at is null), s.ends_at, s.created_at desc
     limit 500;
end;
$$;
revoke all on function public.admin_list_subscriptions(boolean) from public, anon;
grant execute on function public.admin_list_subscriptions(boolean) to authenticated;

-- Dar Pro Negocio a mano (cortesía o compensación). p_days null = permanente.
-- Los días se suman desde que vence el Pro que ya tenga el negocio.
create or replace function public.admin_grant_pro(p_business_id text, p_days integer)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_owner text;
  v_from timestamptz;
  v_current jsonb;
begin
  perform public.admin_guard();
  if p_days is not null and (p_days < 1 or p_days > 3650) then
    raise exception 'invalid_days';
  end if;
  if not exists (select 1 from public.businesses where id = p_business_id and coalesce(is_deleted, 0) = 0) then
    raise exception 'business_not_found';
  end if;
  select m.user_email into v_owner from public.business_members m
   where m.business_id = p_business_id and m.role = 'OWNER' limit 1;
  v_current := public.business_pro_until(p_business_id);
  v_from := greatest(now(), coalesce((v_current ->> 'ends_at')::timestamptz, now()));

  insert into public.subscriptions (kind, business_id, owner_email, source, starts_at, ends_at)
  values ('business', p_business_id, coalesce(v_owner, auth.email()), 'manual', now(),
          case when p_days is null then null else v_from + make_interval(days => p_days) end);

  return public.business_pro_until(p_business_id);
end;
$$;
revoke all on function public.admin_grant_pro(text, integer) from public, anon;
grant execute on function public.admin_grant_pro(text, integer) to authenticated;

-- Terminar una suscripción ya (pago que no llegó, error)
create or replace function public.admin_end_subscription(p_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform public.admin_guard();
  update public.subscriptions set ends_at = now()
   where id = p_id and (ends_at is null or ends_at > now());
end;
$$;
revoke all on function public.admin_end_subscription(uuid) from public, anon;
grant execute on function public.admin_end_subscription(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Códigos: crear con vencimiento, buscar y desactivar
-- ---------------------------------------------------------------------------
drop function if exists public.admin_create_pro_codes(text, integer, integer, text, integer);
create or replace function public.admin_create_pro_codes(
  p_kind text,
  p_days integer,
  p_count integer default 1,
  p_note text default null,
  p_max_uses integer default 1,
  -- Días que tiene el cliente para canjearlo; null = sin vencimiento
  p_valid_days integer default null
)
returns setof text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_code text;
begin
  perform public.admin_guard();
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
  if p_valid_days is not null and (p_valid_days < 1 or p_valid_days > 3650) then
    raise exception 'invalid_valid_days';
  end if;
  for v_code in
    select public.create_pro_codes(p_kind, p_days, p_count, nullif(trim(p_note), ''), p_max_uses)
  loop
    if p_valid_days is not null then
      update public.pro_codes set expires_at = now() + make_interval(days => p_valid_days) where code = v_code;
    end if;
    return next v_code;
  end loop;
end;
$$;
revoke all on function public.admin_create_pro_codes(text, integer, integer, text, integer, integer) from public, anon;
grant execute on function public.admin_create_pro_codes(text, integer, integer, text, integer, integer) to authenticated;

drop function if exists public.admin_list_pro_codes(integer);
create or replace function public.admin_list_pro_codes(p_limit integer default 50, p_search text default null)
returns table (
  code text,
  kind text,
  days integer,
  max_uses integer,
  uses integer,
  note text,
  created_at timestamptz,
  expires_at timestamptz,
  redeemed_by text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_q text := lower(trim(coalesce(p_search, '')));
begin
  perform public.admin_guard();
  return query
    select c.code, c.kind, c.days, c.max_uses, c.uses, c.note, c.created_at, c.expires_at,
           (select string_agg(r.user_email, ', ' order by r.redeemed_at)
              from public.code_redemptions r where r.code = c.code)
      from public.pro_codes c
     where v_q = ''
        or lower(c.code) like '%' || v_q || '%'
        or lower(coalesce(c.note, '')) like '%' || v_q || '%'
        or exists (select 1 from public.code_redemptions r
                    where r.code = c.code and lower(r.user_email) like '%' || v_q || '%')
     order by c.created_at desc
     limit least(greatest(coalesce(p_limit, 50), 1), 200);
end;
$$;
revoke all on function public.admin_list_pro_codes(integer, text) from public, anon;
grant execute on function public.admin_list_pro_codes(integer, text) to authenticated;

create or replace function public.admin_disable_code(p_code text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform public.admin_guard();
  update public.pro_codes set expires_at = now()
   where code = upper(trim(p_code)) and (expires_at is null or expires_at > now());
end;
$$;
revoke all on function public.admin_disable_code(text) from public, anon;
grant execute on function public.admin_disable_code(text) to authenticated;

-- ---------------------------------------------------------------------------
-- Configuración de Pro: datos de pago y precios
-- ---------------------------------------------------------------------------
create or replace function public.admin_get_config()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform public.admin_guard();
  return jsonb_build_object(
    'settings', coalesce((select jsonb_object_agg(key, value) from public.pro_settings), '{}'::jsonb),
    'plans', coalesce((select jsonb_agg(jsonb_build_object(
        'id', id, 'kind', kind, 'period', period, 'currency', currency, 'price', price,
        'regular_price', regular_price, 'label', label, 'active', active) order by currency, sort)
      from public.pro_plans), '[]'::jsonb)
  );
end;
$$;
revoke all on function public.admin_get_config() from public, anon;
grant execute on function public.admin_get_config() to authenticated;

create or replace function public.admin_set_setting(p_key text, p_value text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform public.admin_guard();
  if p_key not in ('nequi_number', 'nequi_name', 'whatsapp', 'founder_slots', 'founder_until', 'legal_notice') then
    raise exception 'invalid_setting';
  end if;
  insert into public.pro_settings (key, value) values (p_key, nullif(trim(coalesce(p_value, '')), ''))
  on conflict (key) do update set value = excluded.value;
end;
$$;
revoke all on function public.admin_set_setting(text, text) from public, anon;
grant execute on function public.admin_set_setting(text, text) to authenticated;

create or replace function public.admin_set_plan(p_id text, p_price numeric, p_regular_price numeric, p_label text, p_active boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform public.admin_guard();
  if p_price is null or p_price < 0 or (p_regular_price is not null and p_regular_price < 0) then
    raise exception 'invalid_price';
  end if;
  update public.pro_plans
     set price = p_price,
         regular_price = p_regular_price,
         label = nullif(trim(coalesce(p_label, '')), ''),
         active = coalesce(p_active, true)
   where id = p_id;
  if not found then
    raise exception 'plan_not_found';
  end if;
end;
$$;
revoke all on function public.admin_set_plan(text, numeric, numeric, text, boolean) from public, anon;
grant execute on function public.admin_set_plan(text, numeric, numeric, text, boolean) to authenticated;
