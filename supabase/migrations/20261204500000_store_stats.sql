-- 0.16.0, fase 4: estadísticas de la tienda en línea.
--
-- • store_stats: un conteo por día, tipo y producto. NO guarda nada de quién visita
--   (ni nombre, ni teléfono, ni IP): solo cuántas veces pasó.
--     VISIT   una visita (la tienda la cuenta una vez por visita, no por recarga)
--     ADD     agregaron un producto al carrito
--     SHARED  llegó por el link de un producto compartido
--     QR      llegó escaneando el QR del mostrador
-- • track_store_event: lo llama la tienda pública (sin cuenta). Solo cuenta en tiendas
--   encendidas y productos de ese negocio.
-- • get_store_stats: los números para la app (dueño o administrador). Los pedidos salen
--   de store_orders (sin los rechazados).

create table if not exists public.store_stats (
  business_id text not null references public.businesses(id) on delete cascade,
  day date not null,
  kind text not null check (kind in ('VISIT', 'ADD', 'SHARED', 'QR')),
  product_id text not null default '',
  count integer not null default 0 check (count >= 0),
  primary key (business_id, day, kind, product_id)
);

alter table public.store_stats enable row level security;

drop policy if exists store_stats_select on public.store_stats;
create policy store_stats_select on public.store_stats
  for select to authenticated using (coalesce(public.my_business_role(business_id), '') in ('OWNER', 'ADMIN'));

create or replace function public.track_store_event(p_slug text, p_kind text, p_product_id text default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_business text;
  v_product text := coalesce(nullif(trim(p_product_id), ''), '');
  v_day date := (now() at time zone 'America/Bogota')::date;
begin
  if p_kind not in ('VISIT', 'ADD', 'SHARED', 'QR') then
    return;
  end if;
  select s.business_id into v_business from public.online_stores s
  where s.slug = lower(trim(coalesce(p_slug, ''))) and s.enabled;
  if v_business is null then
    return;
  end if;
  if v_product <> '' and not exists (select 1 from public.products p where p.id = v_product and p.business_id = v_business) then
    return;
  end if;
  -- La visita no lleva producto
  if p_kind in ('VISIT', 'QR') then
    v_product := '';
  end if;
  insert into public.store_stats (business_id, day, kind, product_id, count)
  values (v_business, v_day, p_kind, v_product, 1)
  on conflict (business_id, day, kind, product_id)
  do update set count = least(public.store_stats.count + 1, 1000000);
end;
$$;

revoke all on function public.track_store_event(text, text, text) from public;
grant execute on function public.track_store_event(text, text, text) to anon, authenticated;

create or replace function public.get_store_stats(p_business_id text, p_from date, p_to date)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_from timestamptz := (p_from::timestamp at time zone 'America/Bogota');
  v_to timestamptz := ((p_to + 1)::timestamp at time zone 'America/Bogota');
begin
  if coalesce(public.my_business_role(p_business_id), '') not in ('OWNER', 'ADMIN') then
    raise exception 'not_allowed';
  end if;
  return jsonb_build_object(
    'days', coalesce((
      select jsonb_agg(jsonb_build_object(
        'day', d.day,
        'visits', coalesce((select sum(s.count) from public.store_stats s where s.business_id = p_business_id and s.day = d.day and s.kind = 'VISIT'), 0),
        'adds', coalesce((select sum(s.count) from public.store_stats s where s.business_id = p_business_id and s.day = d.day and s.kind = 'ADD'), 0),
        'orders', (select count(*) from public.store_orders o where o.business_id = p_business_id and o.status <> 'RECHAZADO'
                     and (o.created_at at time zone 'America/Bogota')::date = d.day),
        'total', coalesce((select sum(o.total) from public.store_orders o where o.business_id = p_business_id and o.status <> 'RECHAZADO'
                     and (o.created_at at time zone 'America/Bogota')::date = d.day), 0)
      ) order by d.day)
      from (select generate_series(p_from, p_to, interval '1 day')::date as day) d
    ), '[]'::jsonb),
    'top_ordered', coalesce((
      select jsonb_agg(t order by (t ->> 'qty')::numeric desc)
      from (
        select jsonb_build_object(
          'product_id', l ->> 'product_id',
          'name', max(l ->> 'name'),
          'qty', sum(coalesce((l ->> 'quantity')::numeric, 0)),
          'total', sum(coalesce((l ->> 'subtotal')::numeric, 0))
        ) t
        from public.store_orders o, jsonb_array_elements(case when jsonb_typeof(o.lines) = 'array' then o.lines else '[]'::jsonb end) l
        where o.business_id = p_business_id and o.status <> 'RECHAZADO' and o.created_at >= v_from and o.created_at < v_to
        group by l ->> 'product_id'
        order by sum(coalesce((l ->> 'quantity')::numeric, 0)) desc
        limit 5
      ) x
    ), '[]'::jsonb),
    'top_added', coalesce((
      select jsonb_agg(jsonb_build_object('product_id', a.product_id, 'name', coalesce(p.name, 'Producto'), 'adds', a.adds) order by a.adds desc)
      from (
        select s.product_id, sum(s.count) adds from public.store_stats s
        where s.business_id = p_business_id and s.kind = 'ADD' and s.product_id <> '' and s.day between p_from and p_to
        group by s.product_id order by sum(s.count) desc limit 5
      ) a
      left join public.products p on p.id = a.product_id
    ), '[]'::jsonb),
    'shared', coalesce((select sum(s.count) from public.store_stats s where s.business_id = p_business_id and s.kind = 'SHARED' and s.day between p_from and p_to), 0),
    'qr', coalesce((select sum(s.count) from public.store_stats s where s.business_id = p_business_id and s.kind = 'QR' and s.day between p_from and p_to), 0)
  );
end;
$$;

revoke all on function public.get_store_stats(text, date, date) from public, anon;
grant execute on function public.get_store_stats(text, date, date) to authenticated;
