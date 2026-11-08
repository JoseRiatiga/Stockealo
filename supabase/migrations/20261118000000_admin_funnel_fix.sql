-- Embudo del panel (versión 0.10.0): "Crearon su negocio" contaba correos de
-- negocios viejos o de pruebas que ya no tienen cuenta, y daba más que "Cuentas"
-- (6 de 4). Ahora solo cuenta dueños que sí tienen cuenta. Mismo resto que antes.

create or replace function public.admin_funnel()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform public.admin_guard();
  return jsonb_build_object(
    'accounts', (select count(*) from auth.users),
    'with_business', (
      select count(distinct lower(m.user_email)) from public.business_members m
       join public.businesses b on b.id = m.business_id and coalesce(b.is_deleted, 0) = 0
       where m.role = 'OWNER'
         and exists (select 1 from auth.users u where lower(u.email) = lower(m.user_email))
    ),
    'businesses', (select count(*) from public.businesses b where coalesce(b.is_deleted, 0) = 0),
    'with_products', (
      select count(*) from public.businesses b
       where coalesce(b.is_deleted, 0) = 0 and exists (select 1 from public.products p where p.business_id = b.id)
    ),
    'with_sales', (
      select count(*) from public.businesses b
       where coalesce(b.is_deleted, 0) = 0 and exists (select 1 from public.sales s where s.business_id = b.id)
    ),
    'with_pro', (
      select count(distinct s.business_id) from public.subscriptions s where s.business_id is not null
    )
  );
end;
$$;
revoke all on function public.admin_funnel() from public, anon;
grant execute on function public.admin_funnel() to authenticated;
