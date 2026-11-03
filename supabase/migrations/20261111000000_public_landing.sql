-- Página principal de stockealo.online (versión 0.9.2): precios y tiendas publicadas
--
-- Una sola función pública (sin sesión) que devuelve lo que la portada muestra:
--   • los planes Pro visibles (precio, periodo, etiqueta)
--   • las tiendas en línea publicadas (encendidas, con Pro y con productos): nombre,
--     logo, color, dirección y cuántos productos tienen
-- Nada privado: ni correos, ni costos, ni ventas, ni clientes.
-- No modifica tablas existentes.

create or replace function public.public_landing()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
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
