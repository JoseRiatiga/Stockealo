-- Stockealo Pro, fase A (versión 0.9.0): planes, códigos canjeables y suscripciones
--
-- Dos tipos de plan:
--   business  Pro Negocio: un negocio y todo su equipo
--   global    Pro Global: todos los negocios donde la cuenta es dueña (sigue al dueño)
-- Mientras no hay pasarela, Pro se activa con códigos: el usuario paga por Nequi, manda
-- el comprobante por WhatsApp y recibe un código. Los códigos se crean desde el SQL de
-- Supabase (o el panel de administración cuando exista).
--
-- Seguridad:
--   • pro_plans y pro_settings se leen desde la app; nadie los escribe desde la app
--   • pro_codes, code_redemptions y app_admins no tienen acceso directo: solo funciones
--   • subscriptions solo se leen (las crea redeem_pro_code o un administrador)
-- No modifica tablas existentes.

-- ---------------------------------------------------------------------------
-- Precios por moneda (se fijan a mano; sin precio para una moneda = Pro no disponible ahí)
-- ---------------------------------------------------------------------------
create table if not exists public.pro_plans (
  id text primary key,
  kind text not null check (kind in ('business', 'global')),
  period text not null check (period in ('week', 'month', 'lifetime')),
  currency text not null,
  price numeric not null check (price >= 0),
  -- Precio normal de un plan en oferta (Fundador); null si no hay oferta
  regular_price numeric check (regular_price is null or regular_price >= 0),
  label text,
  active boolean not null default true,
  sort integer not null default 0
);

alter table public.pro_plans enable row level security;
drop policy if exists pro_plans_select on public.pro_plans;
create policy pro_plans_select on public.pro_plans for select to authenticated using (active);
revoke all on public.pro_plans from anon;
grant select on public.pro_plans to authenticated;

insert into public.pro_plans (id, kind, period, currency, price, regular_price, label, sort) values
  ('business_week_cop',     'business', 'week',     'COP',   2000, null,   null,        1),
  ('business_month_cop',    'business', 'month',    'COP',   6900, null,   null,        2),
  ('business_lifetime_cop', 'business', 'lifetime', 'COP',  39900, 69900,  'Fundador',  3),
  ('global_week_cop',       'global',   'week',     'COP',   5000, null,   null,        4),
  ('global_month_cop',      'global',   'month',    'COP',  16900, null,   null,        5),
  ('global_lifetime_cop',   'global',   'lifetime', 'COP',  79900, 169900, 'Fundador',  6)
on conflict (id) do nothing;

-- ---------------------------------------------------------------------------
-- Ajustes públicos de Pro (Nequi, WhatsApp, cupos y aviso legal)
-- ---------------------------------------------------------------------------
create table if not exists public.pro_settings (
  key text primary key,
  value text
);

alter table public.pro_settings enable row level security;
drop policy if exists pro_settings_select on public.pro_settings;
create policy pro_settings_select on public.pro_settings for select to authenticated using (true);
revoke all on public.pro_settings from anon;
grant select on public.pro_settings to authenticated;

-- Los valores reales (número de Nequi y WhatsApp) los completa el dueño de Stockealo
insert into public.pro_settings (key, value) values
  ('nequi_number', null),
  ('nequi_name', null),
  ('whatsapp', null),
  ('founder_slots', '30'),
  ('founder_until', '2026-12-31'),
  ('legal_notice', 'Precios en pesos colombianos (COP), sujetos a cambios sin previo aviso. Los cambios no afectan los planes ya adquiridos. Oferta Fundador limitada a 30 cupos o hasta el 31/12.')
on conflict (key) do nothing;

-- ---------------------------------------------------------------------------
-- Administradores de Stockealo (para el panel; hoy solo se usa desde SQL)
-- ---------------------------------------------------------------------------
create table if not exists public.app_admins (
  email text primary key
);
alter table public.app_admins enable row level security;
revoke all on public.app_admins from anon, authenticated;

-- ---------------------------------------------------------------------------
-- Códigos canjeables
-- ---------------------------------------------------------------------------
create table if not exists public.pro_codes (
  code text primary key check (code ~ '^[A-Z0-9-]{6,32}$'),
  kind text not null check (kind in ('business', 'global')),
  -- Días de Pro que da; null = permanente
  days integer check (days is null or days > 0),
  max_uses integer not null default 1 check (max_uses > 0),
  uses integer not null default 0,
  expires_at timestamptz,
  note text,
  created_at timestamptz not null default now()
);
alter table public.pro_codes enable row level security;
revoke all on public.pro_codes from anon, authenticated;

create table if not exists public.code_redemptions (
  id uuid primary key default gen_random_uuid(),
  code text not null references public.pro_codes (code),
  user_email text not null,
  business_id text,
  redeemed_at timestamptz not null default now(),
  unique (code, user_email)
);
alter table public.code_redemptions enable row level security;
revoke all on public.code_redemptions from anon, authenticated;

-- ---------------------------------------------------------------------------
-- Suscripciones
-- ---------------------------------------------------------------------------
create table if not exists public.subscriptions (
  id uuid primary key default gen_random_uuid(),
  kind text not null check (kind in ('business', 'global')),
  -- Pro Negocio: el negocio. Pro Global: null (aplica a los negocios del dueño)
  business_id text references public.businesses (id) on delete cascade,
  owner_email text not null,
  source text not null default 'code' check (source in ('code', 'manual', 'gateway')),
  starts_at timestamptz not null default now(),
  -- null = permanente
  ends_at timestamptz,
  created_at timestamptz not null default now(),
  check ((kind = 'business') = (business_id is not null))
);

create index if not exists subscriptions_business_idx on public.subscriptions (business_id);
create index if not exists subscriptions_owner_idx on public.subscriptions (lower(owner_email));

alter table public.subscriptions enable row level security;
drop policy if exists subscriptions_select on public.subscriptions;
create policy subscriptions_select on public.subscriptions for select to authenticated
  using (
    lower(owner_email) = lower(auth.email())
    or (business_id is not null and public.my_business_role(business_id) is not null)
  );
revoke all on public.subscriptions from anon;
grant select on public.subscriptions to authenticated;

-- ---------------------------------------------------------------------------
-- ¿El negocio tiene Pro? (Pro Negocio vigente, o Pro Global de alguno de sus dueños)
-- Uso interno: la llaman pro_status y la función de IA con la llave de servicio.
-- ---------------------------------------------------------------------------
create or replace function public.business_pro_until(p_business_id text)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  with active as (
    select s.kind, s.ends_at
    from public.subscriptions s
    where (s.ends_at is null or s.ends_at > now())
      and s.starts_at <= now()
      and (
        s.business_id = p_business_id
        or (
          s.kind = 'global'
          and exists (
            select 1 from public.business_members m
            where m.business_id = p_business_id
              and m.role = 'OWNER'
              and lower(m.user_email) = lower(s.owner_email)
          )
        )
      )
  )
  select case
    when not exists (select 1 from active) then jsonb_build_object('active', false)
    else jsonb_build_object(
      'active', true,
      -- Si hay alguna permanente, no vence; si no, la que vence más tarde
      'ends_at', (select case when bool_or(ends_at is null) then null else max(ends_at) end from active),
      'kind', (select case when bool_or(kind = 'global') then 'global' else 'business' end from active)
    )
  end;
$$;

revoke all on function public.business_pro_until(text) from public, anon, authenticated;
grant execute on function public.business_pro_until(text) to service_role;

-- Estado Pro para la app: solo miembros del negocio pueden consultarlo
create or replace function public.pro_status(p_business_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if public.my_business_role(p_business_id) is null then
    raise exception 'not_member';
  end if;
  return public.business_pro_until(p_business_id);
end;
$$;

revoke all on function public.pro_status(text) from public, anon;
grant execute on function public.pro_status(text) to authenticated;

-- ---------------------------------------------------------------------------
-- Canjear un código. Pro Negocio se aplica al negocio indicado (solo su dueño);
-- Pro Global, a la cuenta. Si ya tenía Pro, los días se suman al final.
-- ---------------------------------------------------------------------------
create or replace function public.redeem_pro_code(p_code text, p_business_id text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_email text := lower(auth.email());
  v_code public.pro_codes%rowtype;
  v_from timestamptz;
  v_end timestamptz;
  v_clean text := upper(regexp_replace(coalesce(p_code, ''), '\s', '', 'g'));
begin
  if v_email is null then
    raise exception 'not_authenticated';
  end if;

  select * into v_code from public.pro_codes where code = v_clean for update;
  if not found then
    raise exception 'code_not_found';
  end if;
  if v_code.expires_at is not null and v_code.expires_at < now() then
    raise exception 'code_expired';
  end if;
  if v_code.uses >= v_code.max_uses then
    raise exception 'code_used';
  end if;
  if exists (select 1 from public.code_redemptions where code = v_clean and user_email = v_email) then
    raise exception 'code_already_redeemed';
  end if;

  if v_code.kind = 'business' then
    if p_business_id is null or public.my_business_role(p_business_id) is distinct from 'OWNER' then
      raise exception 'owner_only';
    end if;
    select max(ends_at) into v_from from public.subscriptions
      where business_id = p_business_id and ends_at > now();
  else
    select max(ends_at) into v_from from public.subscriptions
      where kind = 'global' and lower(owner_email) = v_email and ends_at > now();
  end if;

  v_end := case when v_code.days is null then null
                else greatest(coalesce(v_from, now()), now()) + make_interval(days => v_code.days) end;

  insert into public.subscriptions (kind, business_id, owner_email, source, ends_at)
  values (
    v_code.kind,
    case when v_code.kind = 'business' then p_business_id else null end,
    v_email,
    'code',
    v_end
  );

  update public.pro_codes set uses = uses + 1 where code = v_clean;
  insert into public.code_redemptions (code, user_email, business_id) values (v_clean, v_email, p_business_id);

  return jsonb_build_object('kind', v_code.kind, 'ends_at', v_end, 'days', v_code.days);
end;
$$;

revoke all on function public.redeem_pro_code(text, text) from public, anon;
grant execute on function public.redeem_pro_code(text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- Crear códigos desde el SQL de Supabase (como administrador del proyecto):
--   select public.create_pro_codes('business', 30, 1, 'Pago Nequi de Ana');
-- Devuelve los códigos nuevos. Solo la llave de servicio puede llamarla.
-- ---------------------------------------------------------------------------
create or replace function public.create_pro_codes(
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
declare
  v_code text;
  i integer;
begin
  for i in 1..greatest(p_count, 1) loop
    loop
      -- STK-XXXX-XXXX sin letras que se confunden (0/O, 1/I)
      v_code := 'STK-' ||
        array_to_string(array(select substr('ABCDEFGHJKLMNPQRSTUVWXYZ23456789', 1 + floor(random() * 32)::int, 1) from generate_series(1, 4)), '') || '-' ||
        array_to_string(array(select substr('ABCDEFGHJKLMNPQRSTUVWXYZ23456789', 1 + floor(random() * 32)::int, 1) from generate_series(1, 4)), '');
      exit when not exists (select 1 from public.pro_codes where code = v_code);
    end loop;
    insert into public.pro_codes (code, kind, days, max_uses, note) values (v_code, p_kind, p_days, p_max_uses, p_note);
    return next v_code;
  end loop;
end;
$$;

revoke all on function public.create_pro_codes(text, integer, integer, text, integer) from public, anon, authenticated;
grant execute on function public.create_pro_codes(text, integer, integer, text, integer) to service_role;
