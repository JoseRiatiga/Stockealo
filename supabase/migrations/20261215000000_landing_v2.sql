-- Portada nueva de stockealo.online (plan aprobado el 25 nov, docs/plan-portada.md)
--
-- public_landing:
--   • Tiendas: solo las que tienen 8 productos o más (con stock y precio). Si no hay al
--     menos 3, no devuelve ninguna y la portada no muestra la sección (así no aparecen
--     tiendas de prueba como ejemplo).
--   • Cada tienda trae también cuántas sedes abiertas tiene el negocio («3 sedes»).
--   • slot_prices: precios de las sedes extra (branch_slot_prices), solo si los precios
--     están encendidos, igual que los planes.
-- landing_click: el contador de «Crear cuenta» (idea 3 del plan). Sin rastreadores ni
--   cookies: solo cuenta, por día, de dónde llegó la persona (instagram, whatsapp,
--   google…). No guarda IP ni nada de la persona.

create table if not exists public.landing_clicks (
  day date not null default ((now() at time zone 'America/Bogota')::date),
  source text not null check (char_length(source) between 1 and 40),
  clicks integer not null default 0,
  primary key (day, source)
);
alter table public.landing_clicks enable row level security;
revoke all on public.landing_clicks from anon, authenticated;

-- «Crear cuenta» desde la portada. p_source: de dónde vino (se normaliza a minúsculas,
-- letras, números y guiones; si viene vacío o raro, «directo»).
create or replace function public.landing_click(p_source text default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_source text := lower(regexp_replace(coalesce(p_source, ''), '[^a-zA-Z0-9_.-]', '', 'g'));
begin
  if v_source = '' then
    v_source := 'directo';
  end if;
  v_source := left(v_source, 40);
  insert into public.landing_clicks (source, clicks) values (v_source, 1)
  on conflict (day, source) do update set clicks = public.landing_clicks.clicks + 1;
end;
$$;
revoke all on function public.landing_click(text) from public;
grant execute on function public.landing_click(text) to anon, authenticated;

create or replace function public.public_landing()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  with pricing as (
    select coalesce((select s.value from public.pro_settings s where s.key = 'show_pricing'), 'off') = 'on' as on_
  ),
  stores as (
    select b.name, s.slug, b.logo_url, b.color, s.business_id,
           (select count(*) from public.products pr
             where pr.business_id = s.business_id and pr.current_stock > 0 and pr.sale_price > 0) as products,
           (select count(*) from public.branches br
             where br.business_id = s.business_id and br.status = 'ACTIVE') as extra_branches
      from public.online_stores s
      join public.businesses b on b.id = s.business_id
     where s.enabled
       and coalesce(b.is_deleted, 0) = 0
       and coalesce((public.business_pro_until(s.business_id) ->> 'active')::boolean, false)
  ),
  shown as (
    select * from stores where products >= 8
  )
  select jsonb_build_object(
    'whatsapp', (select s.value from public.pro_settings s where s.key = 'whatsapp'),
    'show_pricing', (select on_ from pricing),
    'plans', coalesce((
      select jsonb_agg(jsonb_build_object(
        'kind', p.kind, 'period', p.period, 'currency', p.currency, 'price', p.price,
        'regular_price', p.regular_price, 'label', p.label) order by p.sort)
      from public.pro_plans p
      where p.active and p.currency = 'COP' and (select on_ from pricing)
    ), '[]'::jsonb),
    'slot_prices', coalesce((
      select jsonb_agg(jsonb_build_object(
        'kind', sp.kind, 'month', sp.month_price, 'year', sp.year_price,
        'bulk_month', sp.bulk_month_price, 'bulk_year', sp.bulk_year_price, 'bulk_from', sp.bulk_from) order by sp.kind)
      from public.branch_slot_prices sp
      where (select on_ from pricing)
    ), '[]'::jsonb),
    'stores', case when (select count(*) from shown) >= 3 then coalesce((
      select jsonb_agg(jsonb_build_object(
        'name', x.name,
        'slug', x.slug,
        'logo_url', case when x.logo_url like 'https://%' then x.logo_url end,
        'color', x.color,
        'products', x.products,
        -- La Principal + las sedes extra abiertas
        'branches', x.extra_branches + 1
      ) order by x.products desc, x.name)
      from shown x
    ), '[]'::jsonb) else '[]'::jsonb end
  );
$$;
revoke all on function public.public_landing() from public;
grant execute on function public.public_landing() to anon, authenticated;
