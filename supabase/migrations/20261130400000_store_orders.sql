-- 0.13.4: pedidos de la tienda en línea y «Por entregar» (decisiones del dueño, 14 nov 2026)
--   • El pedido se guarda con un código por negocio, sin fecha: T-0001, T-0002…
--     Lo crea el comprador (sin cuenta) con create_store_order; solo puede crear el suyo.
--   • El negocio lo ve en Ventas › Cotizaciones (la app lo baja) y lo pasa a venta.
--   • Cada venta puede quedar «Por entregar» (recoge después o envío) hasta «Entregado».

create table if not exists public.store_orders (
  id text primary key default gen_random_uuid()::text,
  business_id text not null references public.businesses (id) on delete cascade,
  number integer not null,
  code text not null,
  customer_name text not null check (char_length(customer_name) between 1 and 80),
  customer_phone text check (customer_phone is null or char_length(customer_phone) <= 30),
  note text check (note is null or char_length(note) <= 500),
  lines jsonb not null,
  total numeric not null check (total >= 0),
  status text not null default 'PENDIENTE' check (status in ('PENDIENTE', 'CONFIRMADO', 'RECHAZADO')),
  created_at timestamptz not null default now(),
  unique (business_id, number)
);
create index if not exists idx_store_orders_business on public.store_orders (business_id, status);

alter table public.store_orders enable row level security;
drop policy if exists store_orders_select on public.store_orders;
create policy store_orders_select on public.store_orders for select to authenticated
  using (public.my_business_role(business_id) is not null);
drop policy if exists store_orders_update on public.store_orders;
create policy store_orders_update on public.store_orders for update to authenticated
  using (public.my_business_role(business_id) is not null)
  with check (public.my_business_role(business_id) is not null);

-- El comprador crea su pedido. Devuelve { id, code }.
create or replace function public.create_store_order(
  p_slug text, p_customer_name text, p_customer_phone text, p_note text, p_lines jsonb, p_total numeric
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_store public.online_stores;
  v_number integer;
  v_id text;
  v_code text;
  v_name text := left(trim(coalesce(p_customer_name, '')), 80);
begin
  select * into v_store from public.online_stores where slug = lower(trim(coalesce(p_slug, '')));
  if not found or not v_store.enabled then
    raise exception 'store_not_found';
  end if;
  if not coalesce((public.business_pro_until(v_store.business_id) ->> 'active')::boolean, false) then
    raise exception 'store_not_found';
  end if;
  if v_name = '' then
    raise exception 'name_required';
  end if;
  if jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) = 0 or jsonb_array_length(p_lines) > 100 then
    raise exception 'invalid_lines';
  end if;
  -- Contador por negocio sin saltos ni repetidos aunque lleguen dos pedidos a la vez
  perform pg_advisory_xact_lock(hashtext('store_orders:' || v_store.business_id));
  select coalesce(max(number), 0) + 1 into v_number from public.store_orders where business_id = v_store.business_id;
  v_code := 'T-' || lpad(v_number::text, 4, '0');
  insert into public.store_orders (business_id, number, code, customer_name, customer_phone, note, lines, total)
  values (
    v_store.business_id, v_number, v_code, v_name,
    nullif(left(trim(coalesce(p_customer_phone, '')), 30), ''),
    nullif(left(trim(coalesce(p_note, '')), 500), ''),
    p_lines, greatest(coalesce(p_total, 0), 0)
  )
  returning id into v_id;
  return jsonb_build_object('id', v_id, 'code', v_code);
end;
$$;

revoke all on function public.create_store_order(text, text, text, text, jsonb, numeric) from public;
grant execute on function public.create_store_order(text, text, text, text, jsonb, numeric) to anon, authenticated;

-- «Por entregar»
alter table public.sales add column if not exists delivery_status text;
alter table public.sales add column if not exists delivery_note text;
alter table public.sales add column if not exists delivered_at timestamptz;
