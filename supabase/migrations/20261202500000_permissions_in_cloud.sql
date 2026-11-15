-- 0.15.0, punto 7 (docs/plan-permisos-nube.md, opción A, aprobada el 14 nov 2026):
-- los permisos y límites de cada rol se cumplen también en la nube, no solo en la app.
--
-- • has_permission / my_limit saben lo mismo que lib/core/permissions/permissions.dart:
--   el rol de la persona, su rol propio y los ajustes del Administrador y del Cajero.
--   La lista del Cajero de fábrica está aquí y en la app; test/core/permissions_cloud_parity_test.dart
--   comprueba que sean iguales.
-- • Lo que pasa el límite (o lo que el rol no permite pero alguien autorizó) tiene que llegar
--   con el número de una autorización ya usada por esa persona, en ese negocio y en las
--   últimas 24 horas. Cada autorización sirve para un solo cambio.
-- • Las funciones de stock y deuda pasan a correr en el servidor con su propia revisión,
--   así el cajero sigue bajando el stock al vender aunque no pueda editar productos.
-- • Las escrituras del servidor (sin usuario: funciones internas, webhooks) no se revisan.

alter table public.sales add column if not exists auth_request_id uuid;
alter table public.sales add column if not exists void_auth_request_id uuid;
alter table public.cash_movements add column if not exists auth_request_id uuid;

-- El rol de quien llama en un negocio: su rol, sus permisos (null = los de fábrica) y sus límites
create or replace function public._my_role_row(p_business_id text)
returns table (role text, perms jsonb, limits jsonb)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_role text;
  v_role_id text;
  v_perms jsonb;
  v_limits jsonb;
begin
  select m.role, m.role_id into v_role, v_role_id
  from public.business_members m
  where m.business_id = p_business_id and lower(m.user_email) = lower(auth.email())
  order by case m.role when 'OWNER' then 1 when 'ADMIN' then 2 else 3 end
  limit 1;
  if v_role is null then
    return;
  end if;
  if v_role <> 'OWNER' then
    if v_role_id is not null then
      select r.perms, r.limits into v_perms, v_limits
      from public.business_roles r
      where r.id = v_role_id and r.business_id = p_business_id and r.builtin is null;
    end if;
    if v_perms is null then
      select r.perms, r.limits into v_perms, v_limits
      from public.business_roles r
      where r.business_id = p_business_id and r.builtin = v_role;
    end if;
  end if;
  role := v_role;
  perms := v_perms;
  limits := coalesce(v_limits, '{}'::jsonb);
  return next;
end;
$$;

create or replace function public.has_permission(p_business_id text, p_perm text)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  r record;
begin
  select * into r from public._my_role_row(p_business_id);
  if r.role is null then
    return false;
  end if;
  if r.role = 'OWNER' then
    return true;
  end if;
  if r.perms is not null then
    return r.perms ? p_perm;
  end if;
  if r.role = 'ADMIN' then
    return p_perm <> 'team';
  end if;
  -- El Cajero de fábrica (igual que Permissions._cashierPerms en la app)
  return p_perm = any (array['sell', 'discount', 'credit', 'allSales', 'quotations', 'cashOwn', 'cashMoves', 'cashExpected', 'catalog', 'customersEdit', 'collectDebts', 'allDebts', 'servicesWork', 'servicesCharge', 'appointments', 'myCommissions']);
end;
$$;

-- El límite de quien llama; null = sin límite (el Dueño nunca tiene)
create or replace function public.my_limit(p_business_id text, p_key text)
returns numeric
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  r record;
begin
  select * into r from public._my_role_row(p_business_id);
  if r.role is null or r.role = 'OWNER' then
    return null;
  end if;
  if jsonb_typeof(r.limits -> p_key) = 'number' then
    return (r.limits ->> p_key)::numeric;
  end if;
  return null;
end;
$$;

-- ¿Esta autorización la usó quien llama, en este negocio y hace poco?
create or replace function public._auth_ok(p_id uuid, p_business_id text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.auth_requests a
    where a.id = p_id
      and a.business_id = p_business_id
      and a.requested_by = auth.uid()
      and a.status = 'USADA'
      and a.used_at > now() - interval '24 hours'
  );
$$;

revoke all on function public._my_role_row(text) from public, anon;
revoke all on function public.has_permission(text, text) from public, anon;
revoke all on function public.my_limit(text, text) from public, anon;
revoke all on function public._auth_ok(uuid, text) from public, anon;
grant execute on function public._my_role_row(text) to authenticated;
grant execute on function public.has_permission(text, text) to authenticated;
grant execute on function public.my_limit(text, text) to authenticated;
grant execute on function public._auth_ok(uuid, text) to authenticated;

-- ---------------------------------------------------------------------------
-- Ventas: vender, descuento (y su límite), pérdida, fiado y anular (y su límite)
-- ---------------------------------------------------------------------------
create or replace function public._check_sale()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_gross numeric;
  v_disc numeric;
  v_limit numeric;
  v_needs boolean := false;
begin
  if auth.uid() is null then
    return new;
  end if;

  if tg_op = 'INSERT' then
    -- Un reintento de una venta que ya está: lo revisa la parte de cambios
    if exists (select 1 from public.sales s where s.id = new.id) then
      return new;
    end if;
    if new.service_id is null then
      if not public.has_permission(new.business_id, 'sell') then
        raise exception 'perm_denied:sell';
      end if;
    elsif not public.has_permission(new.business_id, 'servicesCharge') then
      raise exception 'perm_denied:servicesCharge';
    end if;
    -- Descuento: precio por cantidad menos promociones, frente a lo cobrado
    v_gross := coalesce(new.unit_price, 0) * coalesce(new.quantity, 0) - coalesce(new.promotion_discount, 0);
    v_disc := v_gross - coalesce(new.total_amount, 0);
    if new.service_id is null and v_disc > 0.5 then
      if not public.has_permission(new.business_id, 'discount') then
        v_needs := true;
      else
        v_limit := public.my_limit(new.business_id, 'discountPct');
        if v_limit is not null and v_gross > 0 and v_disc * 100 / v_gross > v_limit + 0.01 then
          v_needs := true;
        end if;
      end if;
    end if;
    if new.service_id is null
       and coalesce(new.unit_cost, 0) * coalesce(new.quantity, 0) - coalesce(new.total_amount, 0) > 0.5
       and not public.has_permission(new.business_id, 'sellBelowCost') then
      v_needs := true;
    end if;
    if upper(coalesce(new.payment_method, '')) = 'FIADO' and not public.has_permission(new.business_id, 'credit') then
      v_needs := true;
    end if;
    if v_needs and (
      new.auth_request_id is null
      or not public._auth_ok(new.auth_request_id, new.business_id)
      -- La misma autorización sirve para las líneas de una sola venta, no para otra
      or exists (
        select 1 from public.sales s
        where s.auth_request_id = new.auth_request_id and s.id <> new.id and s.sale_date <> new.sale_date
      )
    ) then
      raise exception 'needs_authorization';
    end if;
    return new;
  end if;

  -- UPDATE: anular necesita «Anular venta»; una venta vieja, además, su autorización
  if old.voided_at is null and new.voided_at is not null then
    if not public.has_permission(new.business_id, 'voidSale') then
      raise exception 'perm_denied:voidSale';
    end if;
    v_limit := public.my_limit(new.business_id, 'voidHours');
    if v_limit is not null and old.sale_date < now() - make_interval(secs => (v_limit * 3600)::double precision) and (
      new.void_auth_request_id is null
      or not public._auth_ok(new.void_auth_request_id, new.business_id)
      or exists (
        select 1 from public.sales s
        where s.void_auth_request_id = new.void_auth_request_id and s.id <> new.id and s.sale_date <> new.sale_date
      )
    ) then
      raise exception 'needs_authorization';
    end if;
  end if;
  -- Lo cobrado no se cambia después (solo se anula)
  if (new.total_amount, new.unit_price, new.quantity, new.payment_method)
       is distinct from (old.total_amount, old.unit_price, old.quantity, old.payment_method)
     and not public.has_permission(new.business_id, 'voidSale') then
    raise exception 'perm_denied:sale_locked';
  end if;
  return new;
end;
$$;

drop trigger if exists sales_check_permissions on public.sales;
create trigger sales_check_permissions
  before insert or update on public.sales
  for each row execute function public._check_sale();

-- ---------------------------------------------------------------------------
-- Caja: entradas y salidas (y la salida máxima)
-- ---------------------------------------------------------------------------
create or replace function public._check_cash_movement()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_needs boolean := false;
  v_limit numeric;
begin
  if auth.uid() is null then
    return new;
  end if;
  if exists (select 1 from public.cash_movements m where m.id = new.id) then
    return new;
  end if;
  if not public.has_permission(new.business_id, 'cashMoves') then
    v_needs := true;
  end if;
  if new.kind = 'SALIDA' then
    v_limit := public.my_limit(new.business_id, 'cashOutMax');
    if v_limit is not null and coalesce(new.amount, 0) > v_limit + 0.5 then
      v_needs := true;
    end if;
  end if;
  if v_needs and (
    new.auth_request_id is null
    or not public._auth_ok(new.auth_request_id, new.business_id)
    or exists (select 1 from public.cash_movements m where m.auth_request_id = new.auth_request_id and m.id <> new.id)
  ) then
    raise exception 'needs_authorization';
  end if;
  return new;
end;
$$;

drop trigger if exists cash_movements_check_permissions on public.cash_movements;
create trigger cash_movements_check_permissions
  before insert on public.cash_movements
  for each row execute function public._check_cash_movement();

-- ---------------------------------------------------------------------------
-- Stock y deuda: en el servidor, con su propia revisión
-- ---------------------------------------------------------------------------
create or replace function public.adjust_product_stock(p_product_id text, p_delta integer)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.products p
  set current_stock = p.current_stock + p_delta
  where p.id = p_product_id and public.my_business_role(p.business_id) is not null;
end;
$$;

create or replace function public.adjust_variant_stock(p_variant_id text, p_delta integer)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.product_variants v
  set stock = greatest(0, v.stock + p_delta), updated_at = now()
  where v.id = p_variant_id and public.my_business_role(v.business_id) is not null;
end;
$$;

-- Fiar sube la deuda (necesita «Fiar» y respeta el fiado máximo); abonar o anular la baja
drop function if exists public.adjust_customer_debt(text, numeric);
create or replace function public.adjust_customer_debt(p_customer_id text, p_delta numeric, p_auth_request_id uuid default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_business text;
  v_balance numeric;
  v_limit numeric;
  v_authorized boolean;
begin
  select c.business_id, c.debt_balance into v_business, v_balance from public.customers c where c.id = p_customer_id;
  if v_business is null then
    return;
  end if;
  if public.my_business_role(v_business) is null then
    raise exception 'not_member';
  end if;
  if auth.uid() is not null then
    v_authorized := p_auth_request_id is not null and public._auth_ok(p_auth_request_id, v_business);
    if p_delta > 0 then
      if not public.has_permission(v_business, 'credit') and not v_authorized then
        raise exception 'needs_authorization';
      end if;
      v_limit := public.my_limit(v_business, 'creditMax');
      if v_limit is not null and coalesce(v_balance, 0) + p_delta > v_limit + 0.5 and not v_authorized then
        raise exception 'needs_authorization';
      end if;
    elsif p_delta < 0 then
      if not (public.has_permission(v_business, 'collectDebts') or public.has_permission(v_business, 'voidSale')) then
        raise exception 'perm_denied:collectDebts';
      end if;
    end if;
  end if;
  update public.customers set debt_balance = greatest(0, debt_balance + p_delta) where id = p_customer_id;
end;
$$;

revoke all on function public.adjust_product_stock(text, integer) from public, anon;
revoke all on function public.adjust_variant_stock(text, integer) from public, anon;
revoke all on function public.adjust_customer_debt(text, numeric, uuid) from public, anon;
grant execute on function public.adjust_product_stock(text, integer) to authenticated;
grant execute on function public.adjust_variant_stock(text, integer) to authenticated;
grant execute on function public.adjust_customer_debt(text, numeric, uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Reglas por tabla
-- ---------------------------------------------------------------------------
drop policy if exists cash_sessions_insert on public.cash_sessions;
create policy cash_sessions_insert on public.cash_sessions
  for insert to authenticated with check (public.has_permission(business_id, 'cashOwn'));

-- Cerrar: la propia o la de otros (la nube no sabe quién abrió cada turno, así que basta con uno)
drop policy if exists cash_sessions_update on public.cash_sessions;
create policy cash_sessions_update on public.cash_sessions
  for update to authenticated
  using (public.has_permission(business_id, 'cashOwn') or public.has_permission(business_id, 'cashOthers'))
  with check (public.has_permission(business_id, 'cashOwn') or public.has_permission(business_id, 'cashOthers'));

drop policy if exists customers_insert on public.customers;
create policy customers_insert on public.customers
  for insert to authenticated
  with check (public.has_permission(business_id, 'customersEdit') or public.has_permission(business_id, 'credit'));

drop policy if exists customers_update on public.customers;
create policy customers_update on public.customers
  for update to authenticated
  using (public.has_permission(business_id, 'customersEdit') or public.has_permission(business_id, 'credit')
         or public.has_permission(business_id, 'collectDebts'))
  with check (public.has_permission(business_id, 'customersEdit') or public.has_permission(business_id, 'credit')
              or public.has_permission(business_id, 'collectDebts'));

drop policy if exists products_update on public.products;
create policy products_update on public.products
  for update to authenticated
  using (public.has_permission(business_id, 'productsEdit') or public.has_permission(business_id, 'stockAdjust'))
  with check (public.has_permission(business_id, 'productsEdit') or public.has_permission(business_id, 'stockAdjust'));

drop policy if exists product_variants_update on public.product_variants;
create policy product_variants_update on public.product_variants
  for update to authenticated
  using (public.has_permission(business_id, 'productsEdit') or public.has_permission(business_id, 'stockAdjust'))
  with check (public.has_permission(business_id, 'productsEdit') or public.has_permission(business_id, 'stockAdjust'));
