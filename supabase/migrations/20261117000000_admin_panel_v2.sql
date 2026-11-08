-- Panel de administrador v2 (versión 0.9.9)
--
--   • Roles del panel: OWNER (todo), SUPPORT (fichas, notas y contactos; no da Pro ni
--     cambia precios/ajustes), VIEWER (solo mirar). Los administradores actuales
--     quedan como OWNER.
--   • Registro de acciones del panel (quién dio Pro, cambió un precio, activó el
--     mantenimiento…). Se escribe en la misma transacción: si la acción falla, no queda.
--   • Notas internas por cuenta y estado "contactado".
--   • Búsqueda global, embudo de activación (solo conteos), uso de Stocky IA y
--     versiones de la app en uso (la app reporta su versión al abrir).
--   • Modo mantenimiento: aviso programado (1), nube en pausa (2) o cierre total (3),
--     por partes (tiendas, app, pagos), con hora de fin obligatoria.
-- Nada de esto expone productos, ventas, clientes ni ganancias de los negocios.

-- ---------------------------------------------------------------------------
-- Roles
-- ---------------------------------------------------------------------------
alter table public.app_admins add column if not exists role text not null default 'OWNER';
alter table public.app_admins add column if not exists added_at timestamptz not null default now();
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'app_admins_role_check') then
    alter table public.app_admins add constraint app_admins_role_check check (role in ('OWNER', 'SUPPORT', 'VIEWER'));
  end if;
end $$;

create or replace function public.admin_role()
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select a.role from public.app_admins a
   where lower(a.email) = lower(coalesce(auth.jwt() ->> 'email', ''))
   limit 1;
$$;

create table if not exists public.admin_actions (
  id bigint generated always as identity primary key,
  admin_email text not null,
  action text not null,
  detail jsonb,
  created_at timestamptz not null default now()
);
create index if not exists idx_admin_actions_time on public.admin_actions(created_at desc);
alter table public.admin_actions enable row level security;

-- Exige un rol mínimo y, si se indica, deja la acción en el registro
create or replace function public.admin_require(p_min text, p_action text default null, p_detail jsonb default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_role text := public.admin_role();
  v_rank int;
  v_need int;
begin
  if v_role is null then
    raise exception 'admin_only';
  end if;
  v_rank := case v_role when 'OWNER' then 3 when 'SUPPORT' then 2 else 1 end;
  v_need := case p_min when 'OWNER' then 3 when 'SUPPORT' then 2 else 1 end;
  if v_rank < v_need then
    raise exception 'admin_role_forbidden';
  end if;
  if p_action is not null then
    insert into public.admin_actions (admin_email, action, detail)
    values (lower(auth.jwt() ->> 'email'), p_action, p_detail);
  end if;
end;
$$;
revoke all on function public.admin_require(text, text, jsonb) from public, anon;
grant execute on function public.admin_require(text, text, jsonb) to authenticated;

create or replace function public.admin_me()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform public.admin_guard();
  return jsonb_build_object('email', lower(auth.jwt() ->> 'email'), 'role', public.admin_role());
end;
$$;
revoke all on function public.admin_me() from public, anon;
grant execute on function public.admin_me() to authenticated;

create or replace function public.admin_list_admins()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform public.admin_guard();
  return coalesce((
    select jsonb_agg(jsonb_build_object('email', a.email, 'role', a.role, 'added_at', a.added_at) order by a.added_at)
    from public.app_admins a
  ), '[]'::jsonb);
end;
$$;
revoke all on function public.admin_list_admins() from public, anon;
grant execute on function public.admin_list_admins() to authenticated;

-- Agregar, cambiar o quitar (p_role null) un administrador. Solo OWNER. Nunca se
-- puede dejar el panel sin dueño ni quitarse a uno mismo el rol de dueño.
create or replace function public.admin_set_admin(p_email text, p_role text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_email text := lower(trim(coalesce(p_email, '')));
  v_me text := lower(auth.jwt() ->> 'email');
begin
  perform public.admin_require('OWNER', 'set_admin', jsonb_build_object('email', v_email, 'role', p_role));
  if v_email = '' or position('@' in v_email) = 0 then
    raise exception 'invalid_email';
  end if;
  if p_role is not null and p_role not in ('OWNER', 'SUPPORT', 'VIEWER') then
    raise exception 'invalid_role';
  end if;
  if v_email = v_me and coalesce(p_role, '') <> 'OWNER' then
    raise exception 'cannot_demote_self';
  end if;
  if p_role is null then
    delete from public.app_admins where lower(email) = v_email;
  else
    insert into public.app_admins (email, role) values (v_email, p_role)
    on conflict (email) do update set role = excluded.role;
  end if;
  if not exists (select 1 from public.app_admins where role = 'OWNER') then
    raise exception 'last_owner';
  end if;
end;
$$;
revoke all on function public.admin_set_admin(text, text) from public, anon;
grant execute on function public.admin_set_admin(text, text) to authenticated;

create or replace function public.admin_list_actions(p_limit integer default 100)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform public.admin_guard();
  return coalesce((
    select jsonb_agg(x)
    from (
      select jsonb_build_object('admin_email', a.admin_email, 'action', a.action, 'detail', a.detail, 'created_at', a.created_at) x
      from public.admin_actions a
      order by a.created_at desc
      limit least(greatest(coalesce(p_limit, 100), 1), 500)
    ) t
  ), '[]'::jsonb);
end;
$$;
revoke all on function public.admin_list_actions(integer) from public, anon;
grant execute on function public.admin_list_actions(integer) to authenticated;

-- ---------------------------------------------------------------------------
-- Las acciones que cambian algo pasan a exigir OWNER y quedan registradas
-- (mismo cuerpo que antes; solo cambia la primera línea)
-- ---------------------------------------------------------------------------
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
  perform public.admin_require('OWNER', 'grant_pro', jsonb_build_object('business_id', p_business_id, 'days', p_days));
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

create or replace function public.admin_end_subscription(p_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform public.admin_require('OWNER', 'end_subscription', jsonb_build_object('id', p_id));
  update public.subscriptions set ends_at = now()
   where id = p_id and (ends_at is null or ends_at > now());
end;
$$;

create or replace function public.admin_create_pro_codes(p_kind text, p_days integer, p_count integer default 1,
    p_note text default null, p_max_uses integer default 1, p_valid_days integer default null)
returns setof text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_code text;
begin
  perform public.admin_require('OWNER', 'create_codes',
    jsonb_build_object('kind', p_kind, 'days', p_days, 'count', p_count, 'max_uses', p_max_uses, 'note', p_note));
  if p_kind not in ('business', 'global') then raise exception 'invalid_kind'; end if;
  if p_count is null or p_count < 1 or p_count > 50 then raise exception 'invalid_count'; end if;
  if p_days is not null and (p_days < 1 or p_days > 3650) then raise exception 'invalid_days'; end if;
  if p_max_uses is null or p_max_uses < 1 or p_max_uses > 1000 then raise exception 'invalid_max_uses'; end if;
  if p_valid_days is not null and (p_valid_days < 1 or p_valid_days > 3650) then raise exception 'invalid_valid_days'; end if;
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

create or replace function public.admin_disable_code(p_code text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform public.admin_require('OWNER', 'disable_code', jsonb_build_object('code', upper(trim(p_code))));
  update public.pro_codes set expires_at = now()
   where code = upper(trim(p_code)) and (expires_at is null or expires_at > now());
end;
$$;

create or replace function public.admin_set_plan(p_id text, p_price numeric, p_regular_price numeric, p_label text, p_active boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform public.admin_require('OWNER', 'set_plan',
    jsonb_build_object('id', p_id, 'price', p_price, 'regular_price', p_regular_price, 'active', p_active));
  if p_price is null or p_price < 0 or (p_regular_price is not null and p_regular_price < 0) then
    raise exception 'invalid_price';
  end if;
  update public.pro_plans
     set price = p_price, regular_price = p_regular_price,
         label = nullif(trim(coalesce(p_label, '')), ''), active = coalesce(p_active, true)
   where id = p_id;
  if not found then
    raise exception 'plan_not_found';
  end if;
end;
$$;

create or replace function public.admin_set_setting(p_key text, p_value text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- No se registra el valor: puede ser una llave
  perform public.admin_require('OWNER', 'set_setting', jsonb_build_object('key', p_key));
  if p_key not in ('nequi_number', 'nequi_name', 'whatsapp', 'founder_slots', 'founder_until', 'legal_notice',
                   'wompi_public_key') then
    raise exception 'invalid_setting';
  end if;
  insert into public.pro_settings (key, value) values (p_key, nullif(trim(coalesce(p_value, '')), ''))
  on conflict (key) do update set value = excluded.value;
end;
$$;

-- ---------------------------------------------------------------------------
-- Notas internas y estado "contactado"
-- ---------------------------------------------------------------------------
create table if not exists public.admin_notes (
  id bigint generated always as identity primary key,
  user_email text not null,
  note text not null check (char_length(note) between 1 and 2000),
  author_email text not null,
  created_at timestamptz not null default now()
);
create index if not exists idx_admin_notes_user on public.admin_notes(lower(user_email), created_at desc);
alter table public.admin_notes enable row level security;

create table if not exists public.admin_contacts (
  user_email text primary key,
  contacted_at timestamptz not null default now(),
  contacted_by text not null
);
alter table public.admin_contacts enable row level security;

create or replace function public.admin_list_notes(p_email text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform public.admin_guard();
  return jsonb_build_object(
    'notes', coalesce((
      select jsonb_agg(jsonb_build_object('id', n.id, 'note', n.note, 'author_email', n.author_email, 'created_at', n.created_at)
             order by n.created_at desc)
      from public.admin_notes n where lower(n.user_email) = lower(trim(p_email))
    ), '[]'::jsonb),
    'contacted', (
      select jsonb_build_object('at', c.contacted_at, 'by', c.contacted_by)
      from public.admin_contacts c where c.user_email = lower(trim(p_email))
    )
  );
end;
$$;
revoke all on function public.admin_list_notes(text) from public, anon;
grant execute on function public.admin_list_notes(text) to authenticated;

create or replace function public.admin_add_note(p_email text, p_note text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform public.admin_require('SUPPORT', 'add_note', jsonb_build_object('email', lower(trim(p_email))));
  if nullif(trim(coalesce(p_note, '')), '') is null then
    raise exception 'empty_note';
  end if;
  insert into public.admin_notes (user_email, note, author_email)
  values (lower(trim(p_email)), trim(p_note), lower(auth.jwt() ->> 'email'));
end;
$$;
revoke all on function public.admin_add_note(text, text) from public, anon;
grant execute on function public.admin_add_note(text, text) to authenticated;

-- Borrar una nota: el dueño del panel o quien la escribió
create or replace function public.admin_delete_note(p_id bigint)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_author text;
begin
  perform public.admin_require('SUPPORT');
  select author_email into v_author from public.admin_notes where id = p_id;
  if v_author is null then return; end if;
  if v_author <> lower(auth.jwt() ->> 'email') and public.admin_role() <> 'OWNER' then
    raise exception 'admin_role_forbidden';
  end if;
  perform public.admin_require('SUPPORT', 'delete_note', jsonb_build_object('id', p_id));
  delete from public.admin_notes where id = p_id;
end;
$$;
revoke all on function public.admin_delete_note(bigint) from public, anon;
grant execute on function public.admin_delete_note(bigint) to authenticated;

create or replace function public.admin_set_contacted(p_email text, p_contacted boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_email text := lower(trim(coalesce(p_email, '')));
begin
  perform public.admin_require('SUPPORT', 'set_contacted', jsonb_build_object('email', v_email, 'contacted', p_contacted));
  if coalesce(p_contacted, false) then
    insert into public.admin_contacts (user_email, contacted_at, contacted_by)
    values (v_email, now(), lower(auth.jwt() ->> 'email'))
    on conflict (user_email) do update set contacted_at = now(), contacted_by = excluded.contacted_by;
  else
    delete from public.admin_contacts where user_email = v_email;
  end if;
end;
$$;
revoke all on function public.admin_set_contacted(text, boolean) from public, anon;
grant execute on function public.admin_set_contacted(text, boolean) to authenticated;

create or replace function public.admin_list_contacts()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform public.admin_guard();
  return coalesce((
    select jsonb_object_agg(c.user_email, jsonb_build_object('at', c.contacted_at, 'by', c.contacted_by))
    from public.admin_contacts c
  ), '{}'::jsonb);
end;
$$;
revoke all on function public.admin_list_contacts() from public, anon;
grant execute on function public.admin_list_contacts() to authenticated;

-- ---------------------------------------------------------------------------
-- Búsqueda global
-- ---------------------------------------------------------------------------
create or replace function public.admin_search(p_query text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_q text := lower(trim(coalesce(p_query, '')));
  v_like text;
begin
  perform public.admin_guard();
  if char_length(v_q) < 2 then
    return jsonb_build_object('users', '[]'::jsonb, 'businesses', '[]'::jsonb, 'codes', '[]'::jsonb, 'payments', '[]'::jsonb);
  end if;
  v_like := '%' || replace(replace(replace(v_q, '\', '\\'), '%', '\%'), '_', '\_') || '%';
  return jsonb_build_object(
    'users', coalesce((
      select jsonb_agg(x) from (
        select jsonb_build_object('email', u.email, 'name', p.name) x
        from auth.users u
        left join public.users p on lower(p.email) = lower(u.email)
        where lower(u.email) like v_like or lower(coalesce(p.name, '')) like v_like
           or regexp_replace(coalesce(p.phone, ''), '\D', '', 'g') like '%' || regexp_replace(v_q, '\D', '', 'g') || '%'
              and char_length(regexp_replace(v_q, '\D', '', 'g')) >= 4
        limit 8
      ) t
    ), '[]'::jsonb),
    'businesses', coalesce((
      select jsonb_agg(x) from (
        select jsonb_build_object(
          'id', b.id, 'name', b.name,
          'owner_email', (select m.user_email from public.business_members m where m.business_id = b.id and m.role = 'OWNER' limit 1)
        ) x
        from public.businesses b
        where coalesce(b.is_deleted, 0) = 0 and lower(b.name) like v_like
        limit 8
      ) t
    ), '[]'::jsonb),
    'codes', coalesce((
      select jsonb_agg(x) from (
        select jsonb_build_object('code', c.code, 'kind', c.kind, 'days', c.days, 'uses', c.uses, 'max_uses', c.max_uses,
                                  'expires_at', c.expires_at, 'note', c.note) x
        from public.pro_codes c
        where lower(c.code) like v_like or lower(coalesce(c.note, '')) like v_like
        limit 8
      ) t
    ), '[]'::jsonb),
    'payments', coalesce((
      select jsonb_agg(x) from (
        select jsonb_build_object('reference', pp.reference, 'user_email', pp.user_email, 'status', pp.status,
                                  'amount_in_cents', pp.amount_in_cents, 'created_at', pp.created_at) x
        from public.pro_payments pp
        where lower(pp.reference) like v_like or lower(coalesce(pp.wompi_transaction_id, '')) like v_like
        order by pp.created_at desc
        limit 8
      ) t
    ), '[]'::jsonb)
  );
end;
$$;
revoke all on function public.admin_search(text) from public, anon;
grant execute on function public.admin_search(text) to authenticated;

-- ---------------------------------------------------------------------------
-- Embudo de activación: solo conteos, nunca el contenido de nadie
-- ---------------------------------------------------------------------------
create or replace function public.admin_funnel()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform public.admin_guard();
  return jsonb_build_object(
    'accounts', (select count(*) from auth.users),
    'with_business', (
      select count(distinct lower(m.user_email)) from public.business_members m
       join public.businesses b on b.id = m.business_id and coalesce(b.is_deleted, 0) = 0
       where m.role = 'OWNER'
    ),
    'businesses', (select count(*) from public.businesses b where coalesce(b.is_deleted, 0) = 0),
    'with_products', (
      select count(*) from public.businesses b
       where coalesce(b.is_deleted, 0) = 0 and exists (select 1 from public.products p where p.business_id = b.id)
    ),
    'with_sales', (
      select count(*) from public.businesses b
       where coalesce(b.is_deleted, 0) = 0 and exists (select 1 from public.sales s where s.business_id = b.id)
    ),
    'with_pro', (
      select count(distinct s.business_id) from public.subscriptions s where s.business_id is not null
    )
  );
end;
$$;
revoke all on function public.admin_funnel() from public, anon;
grant execute on function public.admin_funnel() to authenticated;

-- ---------------------------------------------------------------------------
-- Uso de Stocky con IA
-- ---------------------------------------------------------------------------
create or replace function public.admin_ai_usage()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform public.admin_guard();
  return jsonb_build_object(
    'days', coalesce((
      select jsonb_agg(jsonb_build_object('day', g.day, 'count', g.count) order by g.day)
      from public.ai_usage_global g where g.day > current_date - 14
    ), '[]'::jsonb),
    'users_today', (select count(*) from public.ai_usage u where u.day = current_date),
    -- 10 preguntas al día es el límite gratis (Pro tiene 50)
    'at_free_limit_today', (select count(*) from public.ai_usage u where u.day = current_date and u.count >= 10),
    'at_pro_limit_today', (select count(*) from public.ai_usage u where u.day = current_date and u.count >= 50),
    'providers_7d', coalesce((
      select jsonb_object_agg(provider, n) from (
        select coalesce(c.provider, 'otro') provider, count(*) n
        from public.ai_cache c where c.created_at > now() - interval '7 days'
        group by 1
      ) t
    ), '{}'::jsonb)
  );
end;
$$;
revoke all on function public.admin_ai_usage() from public, anon;
grant execute on function public.admin_ai_usage() to authenticated;

-- ---------------------------------------------------------------------------
-- Versiones de la app en uso
-- ---------------------------------------------------------------------------
create table if not exists public.app_clients (
  user_id uuid not null,
  platform text not null check (platform in ('android', 'ios', 'web', 'windows', 'macos', 'linux')),
  version text not null check (char_length(version) <= 32),
  last_seen timestamptz not null default now(),
  primary key (user_id, platform)
);
alter table public.app_clients enable row level security;

-- La app la llama al abrir con sesión: guarda solo plataforma y versión
create or replace function public.report_app_version(p_platform text, p_version text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then return; end if;
  if p_platform not in ('android', 'ios', 'web', 'windows', 'macos', 'linux') then return; end if;
  if p_version is null or char_length(p_version) > 32 or p_version !~ '^[0-9]+(\.[0-9]+){1,3}(\+[0-9]+)?$' then return; end if;
  insert into public.app_clients (user_id, platform, version, last_seen)
  values (auth.uid(), p_platform, p_version, now())
  on conflict (user_id, platform) do update set version = excluded.version, last_seen = now();
end;
$$;
revoke all on function public.report_app_version(text, text) from public, anon;
grant execute on function public.report_app_version(text, text) to authenticated;

create or replace function public.admin_app_versions()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform public.admin_guard();
  return coalesce((
    select jsonb_agg(jsonb_build_object('version', v.version, 'platform', v.platform, 'count', v.n, 'last_seen', v.last_seen)
           order by v.last_seen desc)
    from (
      select split_part(c.version, '+', 1) version, c.platform, count(*) n, max(c.last_seen) last_seen
      from public.app_clients c
      where c.last_seen > now() - interval '60 days'
      group by 1, 2
    ) v
  ), '[]'::jsonb);
end;
$$;
revoke all on function public.admin_app_versions() from public, anon;
grant execute on function public.admin_app_versions() to authenticated;

-- ---------------------------------------------------------------------------
-- Modo mantenimiento
-- ---------------------------------------------------------------------------
create table if not exists public.maintenance_window (
  id int primary key default 1 check (id = 1),
  level int not null default 0 check (level between 0 and 3),
  scopes text[] not null default '{}',
  message text,
  starts_at timestamptz,
  ends_at timestamptz,
  notice_hours int not null default 2 check (notice_hours between 0 and 72),
  updated_by text,
  updated_at timestamptz not null default now()
);
insert into public.maintenance_window (id) values (1) on conflict (id) do nothing;
alter table public.maintenance_window enable row level security;

-- Estado público (también sin sesión: lo leen las tiendas). Se calcula con la hora
-- del servidor; al pasar ends_at deja de estar activo solo.
create or replace function public.get_maintenance()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when w.level = 0 or w.starts_at is null or w.ends_at is null or w.ends_at <= now() then
      jsonb_build_object('state', 'none')
    when now() >= w.starts_at then
      jsonb_build_object('state', 'active', 'level', w.level, 'scopes', to_jsonb(w.scopes), 'message', w.message,
                         'starts_at', w.starts_at, 'ends_at', w.ends_at)
    when now() >= w.starts_at - make_interval(hours => w.notice_hours) then
      jsonb_build_object('state', 'notice', 'level', w.level, 'scopes', to_jsonb(w.scopes), 'message', w.message,
                         'starts_at', w.starts_at, 'ends_at', w.ends_at)
    else jsonb_build_object('state', 'none')
  end
  from public.maintenance_window w where w.id = 1;
$$;
revoke all on function public.get_maintenance() from public;
grant execute on function public.get_maintenance() to anon, authenticated;

create or replace function public.admin_get_maintenance()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform public.admin_guard();
  return (
    select jsonb_build_object('level', w.level, 'scopes', to_jsonb(w.scopes), 'message', w.message,
                              'starts_at', w.starts_at, 'ends_at', w.ends_at, 'notice_hours', w.notice_hours,
                              'updated_by', w.updated_by, 'updated_at', w.updated_at, 'public', public.get_maintenance())
    from public.maintenance_window w where w.id = 1
  );
end;
$$;
revoke all on function public.admin_get_maintenance() from public, anon;
grant execute on function public.admin_get_maintenance() to authenticated;

-- Programar o activar. Hora de fin obligatoria (máximo 48 h de ventana); el cierre
-- total exige escribir MANTENIMIENTO.
create or replace function public.admin_set_maintenance(
  p_level integer, p_scopes text[], p_message text, p_starts_at timestamptz, p_ends_at timestamptz,
  p_notice_hours integer default 2, p_confirm text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_starts timestamptz := coalesce(p_starts_at, now());
begin
  perform public.admin_require('OWNER', 'set_maintenance',
    jsonb_build_object('level', p_level, 'scopes', p_scopes, 'starts_at', v_starts, 'ends_at', p_ends_at));
  if p_level is null or p_level not between 1 and 3 then raise exception 'invalid_level'; end if;
  if p_scopes is null or cardinality(p_scopes) = 0
     or exists (select 1 from unnest(p_scopes) s where s not in ('stores', 'app', 'payments')) then
    raise exception 'invalid_scopes';
  end if;
  if p_ends_at is null or p_ends_at <= v_starts or p_ends_at <= now() then raise exception 'invalid_end'; end if;
  if p_ends_at - v_starts > interval '48 hours' then raise exception 'too_long'; end if;
  if p_level = 3 and upper(trim(coalesce(p_confirm, ''))) <> 'MANTENIMIENTO' then raise exception 'confirm_required'; end if;
  update public.maintenance_window
     set level = p_level, scopes = p_scopes, message = nullif(trim(coalesce(p_message, '')), ''),
         starts_at = v_starts, ends_at = p_ends_at,
         notice_hours = least(greatest(coalesce(p_notice_hours, 2), 0), 72),
         updated_by = lower(auth.jwt() ->> 'email'), updated_at = now()
   where id = 1;
  return public.get_maintenance();
end;
$$;
revoke all on function public.admin_set_maintenance(integer, text[], text, timestamptz, timestamptz, integer, text) from public, anon;
grant execute on function public.admin_set_maintenance(integer, text[], text, timestamptz, timestamptz, integer, text) to authenticated;

create or replace function public.admin_end_maintenance()
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform public.admin_require('OWNER', 'end_maintenance', null);
  update public.maintenance_window
     set level = 0, updated_by = lower(auth.jwt() ->> 'email'), updated_at = now()
   where id = 1;
end;
$$;
revoke all on function public.admin_end_maintenance() from public, anon;
grant execute on function public.admin_end_maintenance() to authenticated;
