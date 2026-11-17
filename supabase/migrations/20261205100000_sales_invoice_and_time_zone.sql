-- 0.16.6 · Migración A
-- 1) Comprobante, vendedor y descuento de cada venta también en la nube (decisión N1).
--    Antes vivían solo en el equipo: al bajar ventas en otro equipo se perdían y las
--    líneas de un mismo comprobante no se podían juntar.
-- 2) Zona horaria del negocio (hora del negocio, camino simple decidido el 17 nov).
--    La nube sigue guardando la hora del reloj del negocio; la zona dice cuál es.
--    Vacía = la del país. EE. UU. y México la eligen.

alter table public.sales
  add column if not exists invoice_number text,
  add column if not exists seller_name text,
  add column if not exists discount_amount numeric not null default 0;

create index if not exists sales_business_invoice_idx
  on public.sales (business_id, invoice_number) where invoice_number is not null;

alter table public.businesses
  add column if not exists time_zone text;

-- Solo zonas que la base conoce (America/Bogota, Europe/Madrid…)
alter table public.businesses drop constraint if exists businesses_time_zone_valid;
alter table public.businesses add constraint businesses_time_zone_valid
  check (time_zone is null or (now() at time zone time_zone) is not null);

-- La zona del negocio: la elegida o la de su país
create or replace function public.business_time_zone(p_business_id text)
returns text
language sql
stable
security definer
set search_path to ''
as $$
  select coalesce(
    nullif(b.time_zone, ''),
    case upper(coalesce(b.country, 'CO'))
      when 'CO' then 'America/Bogota'
      when 'MX' then 'America/Mexico_City'
      when 'PE' then 'America/Lima'
      when 'AR' then 'America/Argentina/Buenos_Aires'
      when 'CL' then 'America/Santiago'
      when 'EC' then 'America/Guayaquil'
      when 'US' then 'America/New_York'
      when 'ES' then 'Europe/Madrid'
      else 'America/Bogota'
    end)
  from public.businesses b
  where b.id = p_business_id;
$$;

-- «Ahora» en el mismo marco que guarda la app: la hora del reloj del negocio
-- escrita como si fuera UTC («17:04+00» = las 5:04 p. m. en el negocio)
create or replace function public.business_wall_now(p_business_id text)
returns timestamptz
language sql
stable
security definer
set search_path to ''
as $$
  select (now() at time zone coalesce(public.business_time_zone(p_business_id), 'America/Bogota')) at time zone 'UTC';
$$;

-- Solo las usan reglas del servidor (security definer): la app no las llama
revoke all on function public.business_time_zone(text) from public, anon, authenticated;
revoke all on function public.business_wall_now(text) from public, anon, authenticated;

-- Que la API vea ya las columnas nuevas
notify pgrst, 'reload schema';
