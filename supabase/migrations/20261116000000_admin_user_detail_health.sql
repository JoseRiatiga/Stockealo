-- Panel de administrador (versión 0.9.9): ficha de usuario, salud y uso de Supabase
--
-- Solo para administradores (admin_guard). Nunca devuelve productos, ventas,
-- clientes, fiados ni ganancias de los negocios: solo lo necesario para dar soporte
-- y administrar Stockealo (cuenta, negocios, Pro, códigos y pagos de Pro).
-- No modifica tablas.

-- ---------------------------------------------------------------------------
-- Ficha de un usuario
-- ---------------------------------------------------------------------------
create or replace function public.admin_user_detail(p_email text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_email text := lower(trim(coalesce(p_email, '')));
  v_user auth.users%rowtype;
begin
  perform public.admin_guard();
  select * into v_user from auth.users u where lower(u.email) = v_email limit 1;
  if not found then
    raise exception 'user_not_found';
  end if;

  return jsonb_build_object(
    'account', jsonb_build_object(
      'email', v_user.email,
      'name', (select p.name from public.users p where lower(p.email) = v_email limit 1),
      'phone', (select p.phone from public.users p where lower(p.email) = v_email limit 1),
      'created_at', v_user.created_at,
      'last_sign_in_at', v_user.last_sign_in_at,
      'email_confirmed_at', v_user.email_confirmed_at,
      'provider', coalesce(v_user.raw_app_meta_data ->> 'provider', 'email')
    ),
    'businesses', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', b.id,
        'name', b.name,
        'role', m.role,
        'country', b.country,
        'created_at', b.created_at,
        'pro', public.business_pro_until(b.id),
        'store_slug', s.slug,
        'store_enabled', coalesce(s.enabled, false)
      ) order by b.created_at)
      from public.business_members m
      join public.businesses b on b.id = m.business_id and coalesce(b.is_deleted, 0) = 0
      left join public.online_stores s on s.business_id = b.id
      where lower(m.user_email) = v_email
    ), '[]'::jsonb),
    'redemptions', coalesce((
      select jsonb_agg(jsonb_build_object(
        'code', r.code, 'redeemed_at', r.redeemed_at,
        'business', (select b.name from public.businesses b where b.id = r.business_id)
      ) order by r.redeemed_at desc)
      from public.code_redemptions r
      where lower(r.user_email) = v_email
    ), '[]'::jsonb),
    'payments', coalesce((
      select jsonb_agg(jsonb_build_object(
        'created_at', pp.created_at, 'plan_id', pp.plan_id, 'period', pp.period,
        'amount_in_cents', pp.amount_in_cents, 'currency', pp.currency,
        'status', pp.status, 'payment_method', pp.payment_method,
        'business', (select b.name from public.businesses b where b.id = pp.business_id)
      ) order by pp.created_at desc)
      from public.pro_payments pp
      where lower(pp.user_email) = v_email
    ), '[]'::jsonb),
    'subscriptions', coalesce((
      select jsonb_agg(jsonb_build_object(
        'kind', sub.kind, 'source', sub.source, 'starts_at', sub.starts_at, 'ends_at', sub.ends_at,
        'active', (sub.starts_at <= now() and (sub.ends_at is null or sub.ends_at > now())),
        'business', (select b.name from public.businesses b where b.id = sub.business_id)
      ) order by sub.starts_at desc)
      from public.subscriptions sub
      where lower(sub.owner_email) = v_email
         or sub.business_id in (select m.business_id from public.business_members m where lower(m.user_email) = v_email)
    ), '[]'::jsonb)
  );
end;
$$;

revoke all on function public.admin_user_detail(text) from public, anon;
grant execute on function public.admin_user_detail(text) to authenticated;

-- ---------------------------------------------------------------------------
-- Salud de Stockealo: a quién conviene escribirle hoy
-- ---------------------------------------------------------------------------
create or replace function public.admin_health()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform public.admin_guard();
  return jsonb_build_object(
    -- Cuentas de más de un día sin ningún negocio en la nube: o no han empezado, o
    -- tienen sus datos solo en el celular/navegador y pueden perderlos
    'no_cloud', coalesce((
      select jsonb_agg(x order by x->>'created_at' desc)
      from (
        select jsonb_build_object(
          'email', u.email,
          'name', (select p.name from public.users p where lower(p.email) = lower(u.email) limit 1),
          'phone', (select p.phone from public.users p where lower(p.email) = lower(u.email) limit 1),
          'created_at', u.created_at,
          'last_sign_in_at', u.last_sign_in_at
        ) as x
        from auth.users u
        where u.created_at < now() - interval '1 day'
          and not exists (select 1 from public.business_members m where lower(m.user_email) = lower(u.email))
        limit 50
      ) t
    ), '[]'::jsonb),
    -- Pro que vence en los próximos 7 días (para avisar y que renueven)
    'expiring', coalesce((
      select jsonb_agg(jsonb_build_object(
        'business', b.name,
        'owner_email', sub.owner_email,
        'phone', (select p.phone from public.users p where lower(p.email) = lower(sub.owner_email) limit 1),
        'kind', sub.kind,
        'ends_at', sub.ends_at
      ) order by sub.ends_at)
      from public.subscriptions sub
      left join public.businesses b on b.id = sub.business_id
      where sub.ends_at is not null
        and sub.ends_at > now()
        and sub.ends_at <= now() + interval '7 days'
        -- si ya renovó (tiene otra que sigue después), no hace falta avisar
        and not exists (
          select 1 from public.subscriptions s2
           where s2.id <> sub.id
             and coalesce(s2.business_id, '') = coalesce(sub.business_id, '')
             and lower(coalesce(s2.owner_email, '')) = lower(coalesce(sub.owner_email, ''))
             and (s2.ends_at is null or s2.ends_at > sub.ends_at)
        )
    ), '[]'::jsonb),
    -- Pagos de Pro que no se completaron en los últimos 7 días
    'failed_payments', coalesce((
      select jsonb_agg(jsonb_build_object(
        'user_email', pp.user_email,
        'business', (select b.name from public.businesses b where b.id = pp.business_id),
        'plan_id', pp.plan_id,
        'status', pp.status,
        'amount_in_cents', pp.amount_in_cents,
        'created_at', pp.created_at
      ) order by pp.created_at desc)
      from public.pro_payments pp
      where pp.created_at > now() - interval '7 days'
        and pp.status in ('DECLINED', 'ERROR', 'VOIDED')
    ), '[]'::jsonb),
    -- Cuentas que no han vuelto a iniciar sesión en 30 días
    'inactive_30d', (
      select count(*) from auth.users u
       where coalesce(u.last_sign_in_at, u.created_at) < now() - interval '30 days'
    ),
    -- Uso de Supabase frente a los límites del plan gratis (500 MB de base de datos,
    -- 1 GB de archivos). Si se cambia de plan, se ajustan aquí.
    'usage', jsonb_build_object(
      'db_bytes', pg_database_size(current_database()),
      'db_limit_bytes', 500 * 1024 * 1024,
      'storage_bytes', (select coalesce(sum((o.metadata ->> 'size')::bigint), 0) from storage.objects o),
      'storage_objects', (select count(*) from storage.objects o),
      'storage_limit_bytes', 1024 * 1024 * 1024
    )
  );
end;
$$;

revoke all on function public.admin_health() from public, anon;
grant execute on function public.admin_health() to authenticated;
