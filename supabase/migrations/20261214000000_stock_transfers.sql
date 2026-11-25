-- 0.18.5 · Traslados entre sedes y encargado de turno (plan aprobado el 25 nov,
-- docs/plan-0.18.5-traslados.md)
--
-- Como el resto de sedes: branch_id vacío = la Principal (products.current_stock y
-- product_variants.stock); las sedes extra guardan su stock en branch_stock.
--
-- El stock se mueve SOLO en la nube, con estas funciones, de una vez:
--   send_transfer    → sale del origen y queda «En camino» (IN_TRANSIT)
--   receive_transfer → entra al destino; lo que no llegó queda como faltante (pérdida)
--                      Un cajero sin encargado recibe «por verificar» (RECEIVED_UNVERIFIED)
--   verify_transfer  → el administrador o el encargado confirma lo recibido por verificar
--   cancel_transfer  → mientras esté en camino, vuelve al origen
-- Los lotes con vencimiento salen del origen por el que vence primero y llegan con su
-- fecha y su código.
--
-- Encargado de turno: business_members.lead_until. Mientras esté vigente, en su sede,
-- recibe traslados de forma definitiva, verifica los provisionales y cierra la caja de
-- otros (cashOthers). La hora la revisa la nube.

-- ---------------------------------------------------------------------------
-- Encargado de turno
alter table public.business_members add column if not exists lead_until timestamptz;

-- ¿Quien llama es encargado vigente de esa sede? (p_branch null = la Principal)
create or replace function public._i_am_lead(p_business_id text, p_branch_id text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.business_members m
     where m.business_id = p_business_id
       and lower(m.user_email) = lower(coalesce(auth.email(), ''))
       and m.lead_until > now()
       and m.branch_id is not distinct from p_branch_id
  );
$$;
revoke all on function public._i_am_lead(text, text) from public, anon;
grant execute on function public._i_am_lead(text, text) to authenticated;

-- Nombrar o quitar el encargado (dueño o administrador). Uno por sede: nombrar a uno
-- quita al anterior de esa misma sede. p_until null = quitarlo.
create or replace function public.set_shift_lead(p_member_id text, p_until timestamptz)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_member public.business_members;
begin
  select * into v_member from public.business_members where id = p_member_id;
  if not found then
    raise exception 'member_not_found';
  end if;
  if coalesce(public.my_business_role(v_member.business_id), '') not in ('OWNER', 'ADMIN') then
    raise exception 'perm_denied:team';
  end if;
  if v_member.role in ('OWNER', 'ADMIN') then
    raise exception 'lead_not_needed';
  end if;
  if p_until is not null and p_until <= now() then
    raise exception 'lead_past';
  end if;
  if p_until is not null then
    update public.business_members set lead_until = null
     where business_id = v_member.business_id and id <> v_member.id
       and branch_id is not distinct from v_member.branch_id and lead_until is not null;
  end if;
  update public.business_members set lead_until = p_until where id = v_member.id;
end;
$$;
revoke all on function public.set_shift_lead(text, timestamptz) from public, anon;
grant execute on function public.set_shift_lead(text, timestamptz) to authenticated;

-- Si la persona cambia de sede (la trasladan o se cierra la suya), deja de ser
-- encargado: el turno era de la otra sede (Codex, 25 nov)
create or replace function public._lead_follows_branch()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.branch_id is distinct from old.branch_id then
    new.lead_until := null;
  end if;
  return new;
end;
$$;
drop trigger if exists business_members_lead_branch on public.business_members;
create trigger business_members_lead_branch
  before update of branch_id on public.business_members
  for each row execute function public._lead_follows_branch();

-- El encargado vigente puede cerrar la caja de otros. Igual que antes en todo lo demás.
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
  -- Encargado de turno (0.18.5): solo en su sede, porque escribir en otra sede ya lo
  -- impide _check_branch_write
  if p_perm = 'cashOthers' and exists (
    select 1 from public.business_members m
     where m.business_id = p_business_id and lower(m.user_email) = lower(auth.email())
       and m.lead_until > now()) then
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

-- ---------------------------------------------------------------------------
-- Lotes que llegan por traslado
alter table public.product_lots drop constraint if exists product_lots_source_check;
alter table public.product_lots add constraint product_lots_source_check
  check (source in ('ENTRADA', 'AJUSTE', 'CAMBIO', 'SIN_FECHA', 'TRASLADO'));

-- ---------------------------------------------------------------------------
-- Traslados
create table if not exists public.stock_transfers (
  id text primary key,
  business_id text not null references public.businesses(id) on delete cascade,
  from_branch_id text references public.branches(id),
  to_branch_id text references public.branches(id),
  status text not null default 'IN_TRANSIT'
    check (status in ('IN_TRANSIT', 'RECEIVED', 'RECEIVED_UNVERIFIED', 'CANCELLED')),
  note text check (note is null or char_length(note) <= 500),
  receive_note text check (receive_note is null or char_length(receive_note) <= 500),
  sent_by_email text not null,
  sent_by_name text,
  sent_at timestamptz not null default now(),
  received_by_email text,
  received_by_name text,
  received_as_lead boolean not null default false,
  received_at timestamptz,
  verified_by_email text,
  verified_by_name text,
  verified_at timestamptz,
  cancelled_by_email text,
  cancelled_at timestamptz,
  updated_at timestamptz not null default now(),
  check (from_branch_id is distinct from to_branch_id)
);
create index if not exists stock_transfers_business_idx on public.stock_transfers (business_id, status);

create table if not exists public.stock_transfer_lines (
  id text primary key default gen_random_uuid()::text,
  transfer_id text not null references public.stock_transfers(id) on delete cascade,
  business_id text not null references public.businesses(id) on delete cascade,
  product_id text not null references public.products(id) on delete cascade,
  variant_key text not null default '',
  product_name text not null check (char_length(product_name) <= 200),
  variant_label text check (variant_label is null or char_length(variant_label) <= 120),
  sent integer not null check (sent > 0),
  received integer check (received is null or (received >= 0 and received <= sent)),
  -- Lotes que salieron del origen: [{lot_id, code, expires_on, qty}] (el costo se lee del lote al recibir)
  lots jsonb not null default '[]'::jsonb
);
create index if not exists stock_transfer_lines_transfer_idx on public.stock_transfer_lines (transfer_id);
create index if not exists stock_transfer_lines_business_idx on public.stock_transfer_lines (business_id);

-- Leen: el dueño y los administradores todos; los demás, los de su sede (origen o destino).
-- Nadie escribe directo: solo las funciones de abajo.
alter table public.stock_transfers enable row level security;
alter table public.stock_transfer_lines enable row level security;

create or replace function public._can_see_transfer(p_business_id text, p_from text, p_to text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when public.my_business_role(p_business_id) in ('OWNER', 'ADMIN') then true
    when public.my_business_role(p_business_id) is null then false
    else exists (
      select 1 from public.business_members m
       where m.business_id = p_business_id and lower(m.user_email) = lower(auth.email())
         and (m.branch_id is not distinct from p_from or m.branch_id is not distinct from p_to))
  end;
$$;
revoke all on function public._can_see_transfer(text, text, text) from public, anon;
grant execute on function public._can_see_transfer(text, text, text) to authenticated;

drop policy if exists "stock_transfers: leer" on public.stock_transfers;
create policy "stock_transfers: leer" on public.stock_transfers for select to authenticated
  using (public._can_see_transfer(business_id, from_branch_id, to_branch_id));

drop policy if exists "stock_transfer_lines: leer" on public.stock_transfer_lines;
create policy "stock_transfer_lines: leer" on public.stock_transfer_lines for select to authenticated
  using (exists (select 1 from public.stock_transfers t where t.id = transfer_id
                  and public._can_see_transfer(t.business_id, t.from_branch_id, t.to_branch_id)));

revoke insert, update, delete on public.stock_transfers from anon, authenticated;
revoke insert, update, delete on public.stock_transfer_lines from anon, authenticated;
revoke all on public.stock_transfers from anon;
revoke all on public.stock_transfer_lines from anon;

-- ---------------------------------------------------------------------------
-- Piezas internas

-- Nombre de quien llama en el equipo
create or replace function public._my_member_name(p_business_id text)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select m.user_name from public.business_members m
   where m.business_id = p_business_id and lower(m.user_email) = lower(coalesce(auth.email(), ''))
   order by case m.role when 'OWNER' then 1 when 'ADMIN' then 2 else 3 end limit 1;
$$;
revoke all on function public._my_member_name(text) from public, anon, authenticated;

-- Suma (o resta) unidades en una sede. Restar exige que alcancen.
create or replace function public._transfer_move(p_business_id text, p_branch_id text, p_product_id text, p_variant_key text, p_delta integer)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_have integer;
begin
  -- Producto, talla/color y sede tienen que ser de este negocio (Codex, 25 nov)
  if not exists (select 1 from public.products where id = p_product_id and business_id = p_business_id) then
    raise exception 'product_not_found';
  end if;
  if p_variant_key <> '' and not exists (
    select 1 from public.product_variants where id = p_variant_key and product_id = p_product_id) then
    raise exception 'product_not_found';
  end if;
  if p_branch_id is not null and not exists (
    select 1 from public.branches where id = p_branch_id and business_id = p_business_id) then
    raise exception 'branch_not_found';
  end if;
  if p_branch_id is null then
    if p_variant_key <> '' then
      select stock into v_have from public.product_variants
       where id = p_variant_key and product_id = p_product_id for update;
      if not found then raise exception 'product_not_found'; end if;
      if p_delta < 0 and v_have < -p_delta then raise exception 'not_enough_stock'; end if;
      update public.product_variants set stock = stock + p_delta, updated_at = now() where id = p_variant_key;
      update public.products set current_stock = current_stock + p_delta, updated_at = now() where id = p_product_id;
    else
      select current_stock into v_have from public.products
       where id = p_product_id and business_id = p_business_id for update;
      if not found then raise exception 'product_not_found'; end if;
      if p_delta < 0 and v_have < -p_delta then raise exception 'not_enough_stock'; end if;
      update public.products set current_stock = current_stock + p_delta, updated_at = now() where id = p_product_id;
    end if;
    return;
  end if;
  if p_delta < 0 then
    select stock into v_have from public.branch_stock
     where branch_id = p_branch_id and product_id = p_product_id and variant_key = p_variant_key for update;
    if coalesce(v_have, 0) < -p_delta then raise exception 'not_enough_stock'; end if;
  end if;
  insert into public.branch_stock (branch_id, business_id, product_id, variant_key, stock)
  values (p_branch_id, p_business_id, p_product_id, p_variant_key, p_delta)
  on conflict (branch_id, product_id, variant_key)
  do update set stock = public.branch_stock.stock + excluded.stock, updated_at = now();
end;
$$;
revoke all on function public._transfer_move(text, text, text, text, integer) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Enviar. p_lines: [{product_id, variant_key, quantity, product_name, variant_label}].
-- p_id lo pone la app: si se reintenta, no se envía dos veces.
create or replace function public.send_transfer(
  p_id text, p_business_id text, p_from text, p_to text, p_lines jsonb, p_note text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_role text := public.my_business_role(p_business_id);
  v_line jsonb;
  v_qty integer;
  v_left integer;
  v_take integer;
  v_lots jsonb;
  v_lot record;
  v_product public.products;
  v_variant text;
  v_count integer := 0;
begin
  if v_role is null then
    raise exception 'not_member';
  end if;
  if exists (select 1 from public.stock_transfers where id = p_id) then
    if exists (select 1 from public.stock_transfers where id = p_id and business_id = p_business_id) then
      return jsonb_build_object('id', p_id, 'repeated', true);
    end if;
    raise exception 'transfer_exists';
  end if;
  if p_from is not distinct from p_to then
    raise exception 'same_branch';
  end if;
  -- Quién envía: dueño y administradores desde cualquier sede; con «Ajustar stock»,
  -- solo desde la suya (_check_branch_write revisa que sea la suya)
  if v_role not in ('OWNER', 'ADMIN') and not public.has_permission(p_business_id, 'stockAdjust') then
    raise exception 'perm_denied:stockAdjust';
  end if;
  perform public._check_branch_write(p_business_id, p_from);
  if p_to is not null and not public.branch_usable(p_to) then
    raise exception 'branch_inactive';
  end if;
  if p_to is not null and not exists (select 1 from public.branches where id = p_to and business_id = p_business_id) then
    raise exception 'branch_not_found';
  end if;
  if jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) = 0 or jsonb_array_length(p_lines) > 200 then
    raise exception 'invalid_lines';
  end if;

  insert into public.stock_transfers (id, business_id, from_branch_id, to_branch_id, note, sent_by_email, sent_by_name)
  values (p_id, p_business_id, p_from, p_to, nullif(trim(coalesce(p_note, '')), ''), lower(auth.email()),
          public._my_member_name(p_business_id));

  for v_line in select * from jsonb_array_elements(p_lines) loop
    v_qty := (v_line ->> 'quantity')::integer;
    v_variant := coalesce(v_line ->> 'variant_key', '');
    if v_qty is null or v_qty <= 0 then
      raise exception 'invalid_lines';
    end if;
    select * into v_product from public.products
     where id = v_line ->> 'product_id' and business_id = p_business_id;
    if not found then
      raise exception 'product_not_found';
    end if;
    perform public._transfer_move(p_business_id, p_from, v_product.id, v_variant, -v_qty);

    -- Lotes: primero los que vencen antes
    v_lots := '[]'::jsonb;
    if v_product.tracks_expiry then
      v_left := v_qty;
      for v_lot in
        select * from public.product_lots
         where business_id = p_business_id and product_id = v_product.id
           and branch_id is not distinct from p_from and status = 'ACTIVE' and quantity > 0
         order by expires_on, created_at
         for update
      loop
        exit when v_left <= 0;
        v_take := least(v_left, v_lot.quantity);
        update public.product_lots
           set quantity = quantity - v_take,
               status = case when quantity - v_take = 0 then 'USED' else status end,
               updated_at = now()
         where id = v_lot.id;
        -- Sin el costo: el cajero puede leer las líneas y no ve costos (Codex, 25 nov)
        v_lots := v_lots || jsonb_build_array(jsonb_build_object(
          'lot_id', v_lot.id, 'code', v_lot.code, 'expires_on', v_lot.expires_on, 'qty', v_take));
        v_left := v_left - v_take;
      end loop;
    end if;

    insert into public.stock_transfer_lines (transfer_id, business_id, product_id, variant_key, product_name, variant_label, sent, lots)
    values (p_id, p_business_id, v_product.id, v_variant,
            left(coalesce(nullif(v_line ->> 'product_name', ''), v_product.name), 200),
            left(nullif(v_line ->> 'variant_label', ''), 120), v_qty, v_lots);
    v_count := v_count + 1;
  end loop;

  return jsonb_build_object('id', p_id, 'lines', v_count);
end;
$$;
revoke all on function public.send_transfer(text, text, text, text, jsonb, text) from public, anon;
grant execute on function public.send_transfer(text, text, text, text, jsonb, text) to authenticated;

-- ---------------------------------------------------------------------------
-- Recibir. p_received: {line_id: unidades que llegaron}; la que falte = todo lo enviado.
create or replace function public.receive_transfer(p_id text, p_received jsonb default '{}'::jsonb, p_note text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_t public.stock_transfers;
  v_role text;
  v_lead boolean;
  v_final boolean;
  v_line public.stock_transfer_lines;
  v_got integer;
  v_left integer;
  v_take integer;
  v_lot jsonb;
  v_missing integer := 0;
begin
  select * into v_t from public.stock_transfers where id = p_id for update;
  if not found then
    raise exception 'transfer_not_found';
  end if;
  v_role := public.my_business_role(v_t.business_id);
  if v_role is null then
    raise exception 'not_member';
  end if;
  if v_t.status <> 'IN_TRANSIT' then
    raise exception 'transfer_not_in_transit';
  end if;
  -- La sede de destino tiene que estar en uso y, si no es dueño ni administrador, ser la suya
  perform public._check_branch_write(v_t.business_id, v_t.to_branch_id);
  v_lead := v_role not in ('OWNER', 'ADMIN') and public._i_am_lead(v_t.business_id, v_t.to_branch_id);
  v_final := v_role in ('OWNER', 'ADMIN') or v_lead;

  for v_line in select * from public.stock_transfer_lines where transfer_id = p_id order by id loop
    v_got := coalesce((p_received ->> v_line.id)::integer, v_line.sent);
    if v_got < 0 or v_got > v_line.sent then
      raise exception 'invalid_received';
    end if;
    update public.stock_transfer_lines set received = v_got where id = v_line.id;
    v_missing := v_missing + (v_line.sent - v_got);
    if v_got > 0 then
      perform public._transfer_move(v_t.business_id, v_t.to_branch_id, v_line.product_id, v_line.variant_key, v_got);
      -- Lotes: llegan con su fecha, en el orden en que salieron; lo que faltó sale de los últimos
      v_left := v_got;
      for v_lot in select * from jsonb_array_elements(v_line.lots) loop
        exit when v_left <= 0;
        v_take := least(v_left, (v_lot ->> 'qty')::integer);
        insert into public.product_lots (id, business_id, product_id, code, expires_on, quantity, initial_quantity, cost, source, branch_id)
        values (gen_random_uuid()::text, v_t.business_id, v_line.product_id, v_lot ->> 'code', (v_lot ->> 'expires_on')::date,
                v_take, v_take,
                coalesce((select l.cost from public.product_lots l where l.id = v_lot ->> 'lot_id'), 0),
                'TRASLADO', v_t.to_branch_id);
        v_left := v_left - v_take;
      end loop;
    end if;
  end loop;

  update public.stock_transfers
     set status = case when v_final then 'RECEIVED' else 'RECEIVED_UNVERIFIED' end,
         received_by_email = lower(auth.email()),
         received_by_name = public._my_member_name(v_t.business_id),
         received_as_lead = v_lead,
         received_at = now(),
         receive_note = nullif(trim(coalesce(p_note, '')), ''),
         updated_at = now()
   where id = p_id;
  return jsonb_build_object('id', p_id, 'final', v_final, 'missing', v_missing, 'as_lead', v_lead);
end;
$$;
revoke all on function public.receive_transfer(text, jsonb, text) from public, anon;
grant execute on function public.receive_transfer(text, jsonb, text) to authenticated;

-- ---------------------------------------------------------------------------
-- Verificar lo recibido por un cajero sin encargado
create or replace function public.verify_transfer(p_id text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_t public.stock_transfers;
begin
  select * into v_t from public.stock_transfers where id = p_id for update;
  if not found then
    raise exception 'transfer_not_found';
  end if;
  if v_t.status <> 'RECEIVED_UNVERIFIED' then
    raise exception 'transfer_not_unverified';
  end if;
  if coalesce(public.my_business_role(v_t.business_id), '') not in ('OWNER', 'ADMIN')
     and not public._i_am_lead(v_t.business_id, v_t.to_branch_id) then
    raise exception 'perm_denied:verify';
  end if;
  update public.stock_transfers
     set status = 'RECEIVED', verified_by_email = lower(auth.email()),
         verified_by_name = public._my_member_name(v_t.business_id), verified_at = now(), updated_at = now()
   where id = p_id;
end;
$$;
revoke all on function public.verify_transfer(text) from public, anon;
grant execute on function public.verify_transfer(text) to authenticated;

-- ---------------------------------------------------------------------------
-- Cancelar: mientras esté en camino. Lo cancela quien lo envió, el dueño o un
-- administrador. Las unidades (y los lotes) vuelven al origen; si el origen se cerró,
-- a la Principal.
create or replace function public.cancel_transfer(p_id text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_t public.stock_transfers;
  v_back text;
  v_line public.stock_transfer_lines;
  v_lot jsonb;
begin
  select * into v_t from public.stock_transfers where id = p_id for update;
  if not found then
    raise exception 'transfer_not_found';
  end if;
  if v_t.status <> 'IN_TRANSIT' then
    raise exception 'transfer_not_in_transit';
  end if;
  -- coalesce: sin rol (no es del negocio) la comparación daría null y dejaría pasar
  if public.my_business_role(v_t.business_id) is null then
    raise exception 'not_member';
  end if;
  if coalesce(public.my_business_role(v_t.business_id), '') not in ('OWNER', 'ADMIN')
     and lower(v_t.sent_by_email) <> lower(coalesce(auth.email(), '')) then
    raise exception 'perm_denied:cancel';
  end if;
  v_back := v_t.from_branch_id;
  if v_back is not null and not exists (select 1 from public.branches where id = v_back and status = 'ACTIVE') then
    v_back := null;
  end if;
  for v_line in select * from public.stock_transfer_lines where transfer_id = p_id loop
    perform public._transfer_move(v_t.business_id, v_back, v_line.product_id, v_line.variant_key, v_line.sent);
    for v_lot in select * from jsonb_array_elements(v_line.lots) loop
      update public.product_lots
         set quantity = quantity + (v_lot ->> 'qty')::integer, status = 'ACTIVE', branch_id = v_back, updated_at = now()
       where id = v_lot ->> 'lot_id';
    end loop;
  end loop;
  update public.stock_transfers
     set status = 'CANCELLED', cancelled_by_email = lower(auth.email()), cancelled_at = now(), updated_at = now()
   where id = p_id;
end;
$$;
revoke all on function public.cancel_transfer(text) from public, anon;
grant execute on function public.cancel_transfer(text) to authenticated;
