-- 0.16.0, fase 2b: lotes con vencimiento y cambios con el proveedor.
--
-- • products.tracks_expiry: «Controla vencimiento por lote».
-- • product_lots: cuántas unidades quedan de cada lote y cuándo vence. Lo vencido sale del
--   stock vendible (la app baja current_stock con adjust_product_stock) y queda en el
--   lote con estado EXPIRED hasta el cambio (RETURNED) o la baja (WRITTEN_OFF).
-- • lot_exchanges: el lote vencido que se fue al proveedor para que lo cambie.
-- • Todo el equipo los lee y los mueve (al vender, la app descuenta del lote que vence
--   antes); solo el dueño los borra.

alter table public.products add column if not exists tracks_expiry boolean not null default false;

create table if not exists public.product_lots (
  id text primary key,
  business_id text not null references public.businesses(id) on delete cascade,
  product_id text not null,
  code text check (code is null or char_length(code) <= 40),
  expires_on date not null,
  quantity integer not null default 0 check (quantity >= 0),
  initial_quantity integer not null default 0 check (initial_quantity >= 0),
  cost numeric not null default 0 check (cost >= 0),
  source text not null default 'ENTRADA' check (source in ('ENTRADA', 'AJUSTE', 'CAMBIO', 'SIN_FECHA')),
  purchase_id text,
  status text not null default 'ACTIVE' check (status in ('ACTIVE', 'EXPIRED', 'RETURNED', 'WRITTEN_OFF', 'USED')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists product_lots_business_idx on public.product_lots (business_id);
create index if not exists product_lots_product_idx on public.product_lots (product_id);

create table if not exists public.lot_exchanges (
  id text primary key,
  business_id text not null references public.businesses(id) on delete cascade,
  product_id text not null,
  product_name text not null check (char_length(product_name) <= 200),
  lot_id text not null,
  supplier_id text,
  supplier_name text check (supplier_name is null or char_length(supplier_name) <= 120),
  quantity integer not null default 0 check (quantity >= 0),
  status text not null default 'PENDING' check (status in ('PENDING', 'RECEIVED', 'WRITTEN_OFF')),
  new_lot_id text,
  created_at timestamptz not null default now(),
  closed_at timestamptz
);

create index if not exists lot_exchanges_business_idx on public.lot_exchanges (business_id);

alter table public.product_lots enable row level security;
alter table public.lot_exchanges enable row level security;

do $$
declare t text;
begin
  foreach t in array array['product_lots', 'lot_exchanges'] loop
    execute format('drop policy if exists %1$s_select on public.%1$s', t);
    execute format('create policy %1$s_select on public.%1$s for select to authenticated using (public.my_business_role(business_id) is not null)', t);
    execute format('drop policy if exists %1$s_insert on public.%1$s', t);
    execute format('create policy %1$s_insert on public.%1$s for insert to authenticated with check (public.my_business_role(business_id) is not null)', t);
    execute format('drop policy if exists %1$s_update on public.%1$s', t);
    execute format('create policy %1$s_update on public.%1$s for update to authenticated using (public.my_business_role(business_id) is not null) with check (public.my_business_role(business_id) is not null)', t);
    execute format('drop policy if exists %1$s_delete on public.%1$s', t);
    execute format('create policy %1$s_delete on public.%1$s for delete to authenticated using (public.my_business_role(business_id) = ''OWNER'')', t);
  end loop;
end $$;
