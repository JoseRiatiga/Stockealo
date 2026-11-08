-- Página principal (versión 0.9.5): el WhatsApp de contacto sale de la configuración
--
-- Antes estaba escrito a mano en web_site/index.html. Ahora public_landing devuelve
-- también pro_settings.whatsapp (el mismo que se cambia en el panel › Configuración),
-- que ya es público: se muestra en "Cómo pagar".
-- Mismo contenido que 20261111000000_public_landing.sql más el campo whatsapp.

create or replace function public.public_landing()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'whatsapp', (select s.value from public.pro_settings s where s.key = 'whatsapp'),
    'plans', coalesce((
      select jsonb_agg(jsonb_build_object(
        'kind', p.kind, 'period', p.period, 'currency', p.currency, 'price', p.price,
        'regular_price', p.regular_price, 'label', p.label) order by p.sort)
      from public.pro_plans p
      where p.active and p.currency = 'COP'
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
