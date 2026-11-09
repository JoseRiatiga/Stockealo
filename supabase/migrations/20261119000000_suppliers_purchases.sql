-- Proveedores y entradas de mercancía (versión 0.10.1)
--
--   • suppliers: ficha del proveedor (nombre, contacto, WhatsApp, NIT, día de
--     visita, días de entrega, pedido mínimo, contado o crédito a N días, notas)
--   • products.supplier_id: proveedor principal del producto (opcional)
--   • purchases: entradas de mercancía con sus renglones en `items` (producto,
--     talla y color, cantidad y costo), factura, contado o crédito con vencimiento
--   • purchases.payments: abonos a una entrada a crédito ({amount, date, note});
--     is_paid queda en true cuando los abonos cubren el total
--   • purchases.photo_path: foto de la factura en el depósito PRIVADO
--     purchase-invoices (carpeta = id del negocio; solo la ve el equipo del negocio)
--   • supplier_orders: pedidos enviados al proveedor (renglones en `items` con lo
--     pedido y lo que ya llegó) para ver faltantes; purchases.order_id los une
--   • Mismas reglas que product_variants: ven los miembros del negocio; crean,
--     cambian y borran el dueño o un administrador
-- No borra ni cambia datos existentes.

create table if not exists public.suppliers (
  id text primary key,
  business_id text not null references public.businesses (id) on delete cascade,
  name text not null,
  contact_name text,
  phone text,
  email text,
  tax_id text,
  visit_day text,
  delivery_days integer,
  min_order numeric,
  payment_terms text not null default 'CONTADO' check (payment_terms in ('CONTADO', 'CREDITO')),
  credit_days integer,
  notes text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_suppliers_business on public.suppliers (business_id);

alter table public.products add column if not exists supplier_id text;

create table if not exists public.purchases (
  id text primary key,
  business_id text not null references public.businesses (id) on delete cascade,
  supplier_id text,
  supplier_name text,
  invoice_number text,
  purchase_date timestamptz not null default now(),
  items jsonb not null default '[]'::jsonb,
  total numeric not null default 0,
  payment_terms text not null default 'CONTADO' check (payment_terms in ('CONTADO', 'CREDITO')),
  due_date timestamptz,
  is_paid boolean not null default true,
  payments jsonb not null default '[]'::jsonb,
  photo_path text,
  order_id text,
  notes text,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_purchases_business on public.purchases (business_id, purchase_date desc);

create table if not exists public.supplier_orders (
  id text primary key,
  business_id text not null references public.businesses (id) on delete cascade,
  supplier_id text,
  supplier_name text,
  items jsonb not null default '[]'::jsonb,
  status text not null default 'ENVIADO' check (status in ('ENVIADO', 'PARCIAL', 'RECIBIDO', 'CERRADO')),
  created_by text,
  created_at timestamptz not null default now(),
  received_at timestamptz,
  updated_at timestamptz not null default now()
);

create index if not exists idx_supplier_orders_business on public.supplier_orders (business_id, created_at desc);

alter table public.supplier_orders enable row level security;

drop policy if exists supplier_orders_select on public.supplier_orders;
create policy supplier_orders_select on public.supplier_orders
  for select to authenticated
  using (public.my_business_role(business_id) is not null);

drop policy if exists supplier_orders_insert on public.supplier_orders;
create policy supplier_orders_insert on public.supplier_orders
  for insert to authenticated
  with check (public.my_business_role(business_id) = any (array['OWNER', 'ADMIN']));

drop policy if exists supplier_orders_update on public.supplier_orders;
create policy supplier_orders_update on public.supplier_orders
  for update to authenticated
  using (public.my_business_role(business_id) = any (array['OWNER', 'ADMIN']))
  with check (public.my_business_role(business_id) = any (array['OWNER', 'ADMIN']));

drop policy if exists supplier_orders_delete on public.supplier_orders;
create policy supplier_orders_delete on public.supplier_orders
  for delete to authenticated
  using (public.my_business_role(business_id) = any (array['OWNER', 'ADMIN']));

alter table public.suppliers enable row level security;
alter table public.purchases enable row level security;

drop policy if exists suppliers_select on public.suppliers;
create policy suppliers_select on public.suppliers
  for select to authenticated
  using (public.my_business_role(business_id) is not null);

drop policy if exists suppliers_insert on public.suppliers;
create policy suppliers_insert on public.suppliers
  for insert to authenticated
  with check (public.my_business_role(business_id) = any (array['OWNER', 'ADMIN']));

drop policy if exists suppliers_update on public.suppliers;
create policy suppliers_update on public.suppliers
  for update to authenticated
  using (public.my_business_role(business_id) = any (array['OWNER', 'ADMIN']))
  with check (public.my_business_role(business_id) = any (array['OWNER', 'ADMIN']));

drop policy if exists suppliers_delete on public.suppliers;
create policy suppliers_delete on public.suppliers
  for delete to authenticated
  using (public.my_business_role(business_id) = any (array['OWNER', 'ADMIN']));

drop policy if exists purchases_select on public.purchases;
create policy purchases_select on public.purchases
  for select to authenticated
  using (public.my_business_role(business_id) is not null);

drop policy if exists purchases_insert on public.purchases;
create policy purchases_insert on public.purchases
  for insert to authenticated
  with check (public.my_business_role(business_id) = any (array['OWNER', 'ADMIN']));

drop policy if exists purchases_update on public.purchases;
create policy purchases_update on public.purchases
  for update to authenticated
  using (public.my_business_role(business_id) = any (array['OWNER', 'ADMIN']))
  with check (public.my_business_role(business_id) = any (array['OWNER', 'ADMIN']));

drop policy if exists purchases_delete on public.purchases;
create policy purchases_delete on public.purchases
  for delete to authenticated
  using (public.my_business_role(business_id) = any (array['OWNER', 'ADMIN']));

-- Fotos de facturas: depósito privado; se ven con enlaces firmados de corta duración
insert into storage.buckets (id, name, public)
values ('purchase-invoices', 'purchase-invoices', false)
on conflict (id) do nothing;

drop policy if exists purchase_invoices_select on storage.objects;
create policy purchase_invoices_select on storage.objects for select to authenticated
  using (bucket_id = 'purchase-invoices'
         and public.my_business_role((storage.foldername(name))[1]) in ('OWNER', 'ADMIN'));

drop policy if exists purchase_invoices_insert on storage.objects;
create policy purchase_invoices_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'purchase-invoices'
              and public.my_business_role((storage.foldername(name))[1]) in ('OWNER', 'ADMIN'));

drop policy if exists purchase_invoices_update on storage.objects;
create policy purchase_invoices_update on storage.objects for update to authenticated
  using (bucket_id = 'purchase-invoices'
         and public.my_business_role((storage.foldername(name))[1]) in ('OWNER', 'ADMIN'))
  with check (bucket_id = 'purchase-invoices'
              and public.my_business_role((storage.foldername(name))[1]) in ('OWNER', 'ADMIN'));

drop policy if exists purchase_invoices_delete on storage.objects;
create policy purchase_invoices_delete on storage.objects for delete to authenticated
  using (bucket_id = 'purchase-invoices'
         and public.my_business_role((storage.foldername(name))[1]) in ('OWNER', 'ADMIN'));
