-- Stockealo 0.12.0: la portada sigue el interruptor «Mostrar precios y compra»
--
--   • public_landing solo devuelve planes si pro_settings.show_pricing = 'on'
--     (el mismo interruptor del panel que usa la app).
--   • Devuelve también show_pricing para que la portada oculte lo de pagar en línea.
-- Mismo contenido que 20261115000000_landing_whatsapp.sql más ese filtro.

create or replace function public.public_landing()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'whatsapp', (select s.value from public.pro_settings s where s.key = 'whatsapp'),
    'show_pricing', coalesce((select s.value from public.pro_settings s where s.key = 'show_pricing'), 'off') = 'on',
    'plans', coalesce((
      select jsonb_agg(jsonb_build_object(
        'kind', p.kind, 'period', p.period, 'currency', p.currency, 'price', p.price,
        'regular_price', p.regular_price, 'label', p.label) order by p.sort)
      from public.pro_plans p
      where p.active and p.currency = 'COP'
        and coalesce((select s.value from public.pro_settings s where s.key = 'show_pricing'), 'off') = 'on'
    ), '[]'::jsonb),
    'stores', coalesce((
      select jsonb_agg(x.store order by x.products desc, x.name)
      from (
        select b.name,
               (select count(*) from public.products pr
                 where pr.business_id = s.business_id and pr.current_stock > 0 and pr.sale_price > 0) as products,
               jsonb_build_object(
                 'name', b.name,
                 'slug', s.slug,
                 'logo_url', case when b.logo_url like 'https://%' then b.logo_url end,
                 'color', b.color,
                 'products', (select count(*) from public.products pr
                               where pr.business_id = s.business_id and pr.current_stock > 0 and pr.sale_price > 0)
               ) as store
          from public.online_stores s
          join public.businesses b on b.id = s.business_id
         where s.enabled
           and coalesce(b.is_deleted, 0) = 0
           and coalesce((public.business_pro_until(s.business_id) ->> 'active')::boolean, false)
      ) x
      where x.products > 0
    ), '[]'::jsonb)
  );
$$;

revoke all on function public.public_landing() from public;
grant execute on function public.public_landing() to anon, authenticated;
