-- 0.18.0: sedes (docs/plan-sedes.md, Etapa 1 parte 1)
--
-- Diseño «la Principal se queda donde está»: las columnas de hoy (products.current_stock,
-- product_variants.stock, ventas, cajas, entradas, lotes) siguen siendo de la sede
-- Principal. branch_id vacío = Principal. branch_stock guarda solo las sedes extra.
-- Un negocio con una sola sede no cambia en nada.
--
-- La app vieja (0.17.1 o antes) no sabe de sedes: lo que tiene branch_id solo lo ve una
-- app que manda la cabecera «x-stockealo-branches: 1» (0.18.0 en adelante). Así una app
-- vieja nunca mezcla ventas ni cierra la caja de otra sede.

-- ---------------------------------------------------------------------------
-- La app sabe de sedes (cabecera de la 0.18.0)
create or replace function public.client_knows_branches()
returns boolean
language sql
stable
set search_path = ''
as $$
  select coalesce((nullif(current_setting('request.headers', true), '')::json ->> 'x-stockealo-branches'), '') = '1';
$$;

-- ---------------------------------------------------------------------------
-- Sedes extra. La Principal no es una fila: su nombre va en businesses.main_branch_name
alter table public.businesses add column if not exists main_branch_name text;

create table if not exists public.branches (
  id text primary key default gen_random_uuid()::text,
  business_id text not null references public.businesses(id) on delete cascade,
  name text not null check (length(trim(name)) between 1 and 60),
  address text,
  phone text,
  schedule jsonb,
  status text not null default 'ACTIVE' check (status in ('ACTIVE', 'CLOSED')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  closed_at timestamptz
);
create index if not exists branches_business_idx on public.branches(business_id);

-- Stock de las sedes extra, por producto y talla/color ('' = sin variante)
create table if not exists public.branch_stock (
  branch_id text not null references public.branches(id) on delete cascade,
  business_id text not null references public.businesses(id) on delete cascade,
  product_id text not null references public.products(id) on delete cascade,
  variant_key text not null default '',
  stock integer not null default 0,
  min_stock integer,
  updated_at timestamptz not null default now(),
  primary key (branch_id, product_id, variant_key)
);
create index if not exists branch_stock_business_idx on public.branch_stock(business_id);

-- Cupos de sedes extra que da el dueño de Stockealo (panel) o se compran (0.18.1)
create table if not exists public.branch_slots (
  id uuid primary key default gen_random_uuid(),
  business_id text not null references public.businesses(id) on delete cascade,
  slots integer not null check (slots between 1 and 50),
  starts_at timestamptz not null default now(),
  ends_at timestamptz not null,
  source text not null default 'manual',
  created_at timestamptz not null default now()
);
create index if not exists branch_slots_business_idx on public.branch_slots(business_id);

-- ---------------------------------------------------------------------------
-- Sede en lo que pasa en una sede (null = Principal)
alter table public.sales add column if not exists branch_id text references public.branches(id);
alter table public.cash_sessions add column if not exists branch_id text references public.branches(id);
alter table public.cash_movements add column if not exists branch_id text references public.branches(id);
alter table public.purchases add column if not exists branch_id text references public.branches(id);
alter table public.product_lots add column if not exists branch_id text references public.branches(id);
-- La sede donde trabaja la persona (null = Principal; dueño y administradores ven todas)
alter table public.business_members add column if not exists branch_id text references public.branches(id) on delete set null;

-- ---------------------------------------------------------------------------
-- Cuántas sedes extra puede tener abiertas el negocio: Pro Servicios trae 2; más los
-- cupos vigentes. Sin Pro activo, ninguna.
create or replace function public.branch_allowance(p_business_id text)
returns integer
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_pro jsonb := public.business_pro_until(p_business_id);
  v_included integer := 0;
  v_slots integer;
begin
  if not coalesce((v_pro ->> 'active')::boolean, false) then
    return 0;
  end if;
  if v_pro ->> 'kind' = 'services' then
    v_included := 2;
  end if;
  select coalesce(sum(s.slots), 0) into v_slots from public.branch_slots s
   where s.business_id = p_business_id and s.starts_at <= now() and s.ends_at > now();
  return v_included + v_slots;
end;
$$;

-- Una sede extra se puede usar si está abierta y entra en el límite. Si el plan baja,
-- siguen usables las más antiguas; las demás quedan inactivas (se ven y se descargan).
create or replace function public.branch_usable(p_branch_id text)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_branch public.branches;
  v_rank integer;
begin
  if p_branch_id is null then
    return true;
  end if;
  select * into v_branch from public.branches where id = p_branch_id;
  if not found or v_branch.status <> 'ACTIVE' then
    return false;
  end if;
  select count(*) into v_rank from public.branches b
   where b.business_id = v_branch.business_id and b.status = 'ACTIVE'
     and (b.created_at, b.id) <= (v_branch.created_at, v_branch.id);
  return v_rank <= public.branch_allowance(v_branch.business_id);
end;
$$;

-- Lo que ve la app: sedes, cuáles se pueden usar y cuántos cupos quedan
create or replace function public.my_branches(p_business_id text)
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
  return jsonb_build_object(
    'allowance', public.branch_allowance(p_business_id),
    'main_name', (select main_branch_name from public.businesses where id = p_business_id),
    'branches', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', b.id, 'name', b.name, 'address', b.address, 'phone', b.phone, 'schedule', b.schedule,
        'status', b.status, 'usable', public.branch_usable(b.id), 'created_at', b.created_at, 'closed_at', b.closed_at
      ) order by b.created_at)
      from public.branches b where b.business_id = p_business_id), '[]'::jsonb)
  );
end;
$$;

-- Solo el dueño crea, cierra y reabre sedes; abrir una necesita un cupo libre
create or replace function public._check_branch()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_open integer;
begin
  if auth.uid() is not null and public.my_business_role(new.business_id) is distinct from 'OWNER' then
    raise exception 'owner_only';
  end if;
  new.updated_at := now();
  if new.status = 'CLOSED' and (tg_op = 'INSERT' or old.status <> 'CLOSED') then
    new.closed_at := now();
  end if;
  if new.status = 'ACTIVE' and (tg_op = 'INSERT' or old.status <> 'ACTIVE') then
    new.closed_at := null;
    perform pg_advisory_xact_lock(hashtext('branches:' || new.business_id));
    select count(*) into v_open from public.branches
     where business_id = new.business_id and status = 'ACTIVE' and id <> new.id;
    if v_open >= public.branch_allowance(new.business_id) then
      raise exception 'branch_limit';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists branches_check on public.branches;
create trigger branches_check before insert or update on public.branches
  for each row execute function public._check_branch();

-- ---------------------------------------------------------------------------
-- Ventas y cajas: la sede tiene que existir, estar en uso y ser la de la persona
create or replace function public._check_branch_write(p_business_id text, p_branch_id text)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_role text;
  v_mine text;
begin
  if auth.uid() is null then
    return;
  end if;
  if p_branch_id is not null then
    if not exists (select 1 from public.branches where id = p_branch_id and business_id = p_business_id) then
      raise exception 'branch_not_found';
    end if;
    if not public.branch_usable(p_branch_id) then
      raise exception 'branch_inactive';
    end if;
  end if;
  v_role := public.my_business_role(p_business_id);
  if v_role in ('OWNER', 'ADMIN') then
    return;
  end if;
  select m.branch_id into v_mine from public.business_members m
   where m.business_id = p_business_id and lower(m.user_email) = lower(auth.email()) limit 1;
  if v_mine is distinct from p_branch_id then
    raise exception 'wrong_branch';
  end if;
end;
$$;

create or replace function public._check_branch_row()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' or new.branch_id is distinct from old.branch_id then
    perform public._check_branch_write(new.business_id, new.branch_id);
  end if;
  return new;
end;
$$;


-- Mover stock de una sede extra (ventas, anulaciones, entradas): por diferencia
create or replace function public.adjust_branch_stock(p_branch_id text, p_product_id text, p_variant_key text, p_delta integer)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_business text;
begin
  select business_id into v_business from public.branches where id = p_branch_id;
  if v_business is null or public.my_business_role(v_business) is null then
    raise exception 'not_member';
  end if;
  -- La sede tiene que estar en uso y ser la de la persona (hallazgo de la revisión)
  perform public._check_branch_write(v_business, p_branch_id);
  insert into public.branch_stock (branch_id, business_id, product_id, variant_key, stock)
  values (p_branch_id, v_business, p_product_id, coalesce(p_variant_key, ''), p_delta)
  on conflict (branch_id, product_id, variant_key)
  do update set stock = public.branch_stock.stock + excluded.stock, updated_at = now();
end;
$$;

-- Fijar el stock de una sede extra (ajuste, conteo, importar): necesita permiso de stock
create or replace function public.set_branch_stock(p_branch_id text, p_product_id text, p_variant_key text, p_stock integer, p_min_stock integer default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_business text;
begin
  select business_id into v_business from public.branches where id = p_branch_id;
  if v_business is null then
    raise exception 'not_member';
  end if;
  if not (public.has_permission(v_business, 'stockAdjust') or public.has_permission(v_business, 'productsEdit')) then
    raise exception 'perm_denied:stockAdjust';
  end if;
  perform public._check_branch_write(v_business, p_branch_id);
  insert into public.branch_stock (branch_id, business_id, product_id, variant_key, stock, min_stock)
  values (p_branch_id, v_business, p_product_id, coalesce(p_variant_key, ''), greatest(p_stock, 0), p_min_stock)
  on conflict (branch_id, product_id, variant_key)
  do update set stock = excluded.stock, min_stock = coalesce(excluded.min_stock, public.branch_stock.min_stock), updated_at = now();
end;
$$;

-- ---------------------------------------------------------------------------
-- Reglas de acceso
alter table public.branches enable row level security;
alter table public.branch_stock enable row level security;
alter table public.branch_slots enable row level security;

drop policy if exists branches_select on public.branches;
create policy branches_select on public.branches for select using (public.my_business_role(business_id) is not null);
drop policy if exists branches_insert on public.branches;
create policy branches_insert on public.branches for insert with check (public.my_business_role(business_id) = 'OWNER');
drop policy if exists branches_update on public.branches;
create policy branches_update on public.branches for update using (public.my_business_role(business_id) = 'OWNER');

drop policy if exists branch_stock_select on public.branch_stock;
create policy branch_stock_select on public.branch_stock for select using (public.my_business_role(business_id) is not null);

drop policy if exists branch_slots_select on public.branch_slots;
create policy branch_slots_select on public.branch_slots for select using (public.my_business_role(business_id) is not null);

-- La app vieja no ve ni toca lo de otras sedes (restrictiva: se suma a las de hoy)
do $$
declare t text;
begin
  foreach t in array array['sales', 'cash_sessions', 'cash_movements', 'purchases', 'product_lots'] loop
    execute format('drop policy if exists %I on public.%I', t || '_branch_visible', t);
    execute format(
      'create policy %I on public.%I as restrictive for all using (branch_id is null or public.client_knows_branches()) with check (branch_id is null or public.client_knows_branches())',
      t || '_branch_visible', t);
  end loop;
end $$;

create or replace function public._check_cash_movement_branch()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_session_branch text;
begin
  if tg_op = 'INSERT' or new.branch_id is distinct from old.branch_id or new.session_id is distinct from old.session_id then
    perform public._check_branch_write(new.business_id, new.branch_id);
    if new.session_id is not null then
      select branch_id into v_session_branch from public.cash_sessions where id = new.session_id;
      if found and v_session_branch is distinct from new.branch_id then
        raise exception 'wrong_branch';
      end if;
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists cash_movements_branch_check on public.cash_movements;
create trigger cash_movements_branch_check before insert or update on public.cash_movements
  for each row execute function public._check_cash_movement_branch();

do $$
declare t text;
begin
  foreach t in array array['sales', 'cash_sessions', 'purchases'] loop
    execute format('drop trigger if exists %I on public.%I', t || '_branch_check', t);
    execute format('create trigger %I before insert or update on public.%I for each row execute function public._check_branch_row()',
      t || '_branch_check', t);
  end loop;
end $$;

-- ---------------------------------------------------------------------------
-- Panel: dar cupos de sedes extra (hasta 1 año, como Pro)
create or replace function public.admin_grant_branch_slots(p_business_id text, p_slots integer, p_days integer)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform public.admin_require('OWNER', 'grant_branch_slots',
    jsonb_build_object('business_id', p_business_id, 'slots', p_slots, 'days', p_days));
  if p_slots is null or p_slots < 1 or p_slots > 50 then
    raise exception 'invalid_slots';
  end if;
  if p_days is null or p_days < 1 or p_days > 366 then
    raise exception 'invalid_days';
  end if;
  insert into public.branch_slots (business_id, slots, ends_at, source)
  values (p_business_id, p_slots, now() + make_interval(days => p_days), 'manual');
  return public.branch_allowance(p_business_id);
end;
$$;

revoke all on function public.admin_grant_branch_slots(text, integer, integer) from public, anon;
grant execute on function public.admin_grant_branch_slots(text, integer, integer) to authenticated;
revoke all on function public.adjust_branch_stock(text, text, text, integer) from public, anon;
grant execute on function public.adjust_branch_stock(text, text, text, integer) to authenticated;
revoke all on function public.set_branch_stock(text, text, text, integer, integer) from public, anon;
grant execute on function public.set_branch_stock(text, text, text, integer, integer) to authenticated;
revoke all on function public.my_branches(text) from public, anon;
grant execute on function public.my_branches(text) to authenticated;

-- ---------------------------------------------------------------------------
-- Cerrar una sede (solo el dueño), en un solo paso: su mercancía, sus lotes y sus
-- personas pasan a la sede que elija el dueño (null = Principal) y la sede queda
-- cerrada. Nada se borra: sus ventas, cajas y fiados siguen ahí para verlos y bajarlos.
create or replace function public.close_branch(p_branch_id text, p_target_branch_id text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_branch public.branches;
  v_row record;
  v_moved integer := 0;
begin
  select * into v_branch from public.branches where id = p_branch_id for update;
  if not found then
    raise exception 'branch_not_found';
  end if;
  if public.my_business_role(v_branch.business_id) is distinct from 'OWNER' then
    raise exception 'owner_only';
  end if;
  if v_branch.status <> 'ACTIVE' then
    raise exception 'branch_closed';
  end if;
  if p_target_branch_id = p_branch_id then
    raise exception 'same_branch';
  end if;
  if p_target_branch_id is not null and not exists (
    select 1 from public.branches where id = p_target_branch_id and business_id = v_branch.business_id and status = 'ACTIVE') then
    raise exception 'branch_not_found';
  end if;
  if exists (select 1 from public.cash_sessions where branch_id = p_branch_id and closed_at is null) then
    raise exception 'cash_open';
  end if;

  for v_row in select * from public.branch_stock where branch_id = p_branch_id and stock <> 0 loop
    if p_target_branch_id is null then
      update public.products set current_stock = current_stock + v_row.stock, updated_at = now() where id = v_row.product_id;
      if v_row.variant_key <> '' then
        update public.product_variants set stock = stock + v_row.stock, updated_at = now() where id = v_row.variant_key;
      end if;
    else
      insert into public.branch_stock (branch_id, business_id, product_id, variant_key, stock)
      values (p_target_branch_id, v_row.business_id, v_row.product_id, v_row.variant_key, v_row.stock)
      on conflict (branch_id, product_id, variant_key)
      do update set stock = public.branch_stock.stock + excluded.stock, updated_at = now();
    end if;
    v_moved := v_moved + v_row.stock;
  end loop;
  -- Con tallas o colores, la fila del producto (variant_key '') no se suma dos veces:
  -- la app solo guarda filas por variante en productos con variantes
  update public.branch_stock set stock = 0, updated_at = now() where branch_id = p_branch_id;
  update public.product_lots set branch_id = p_target_branch_id, updated_at = now()
   where branch_id = p_branch_id and status = 'ACTIVE';
  update public.business_members set branch_id = p_target_branch_id where branch_id = p_branch_id;
  update public.branches set status = 'CLOSED' where id = p_branch_id;
  return jsonb_build_object('moved', v_moved);
end;
$$;

revoke all on function public.close_branch(text, text) from public, anon;
grant execute on function public.close_branch(text, text) to authenticated;
