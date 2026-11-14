-- 0.13.4: promociones (para todos los planes). % de descuento o lleva X, paga Y,
-- con fechas; a todo, a una categoría o a productos marcados. Vender las aplica solas;
-- la tienda en línea (Pro) las muestra con su cinta y el precio tachado.

create table if not exists public.promotions (
  id text primary key,
  business_id text not null references public.businesses (id) on delete cascade,
  name text not null check (char_length(name) <= 60),
  kind text not null check (kind in ('PERCENT', 'BUY_X_PAY_Y')),
  percent_off numeric not null default 0 check (percent_off >= 0 and percent_off <= 90),
  buy_qty integer not null default 2 check (buy_qty between 1 and 20),
  pay_qty integer not null default 1 check (pay_qty between 0 and 19),
  scope text not null default 'ALL' check (scope in ('ALL', 'CATEGORY', 'PRODUCTS')),
  category text,
  product_ids text,
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists idx_promotions_business on public.promotions (business_id);

alter table public.promotions enable row level security;
drop policy if exists promotions_select on public.promotions;
create policy promotions_select on public.promotions for select to authenticated
  using (public.my_business_role(business_id) is not null);
drop policy if exists promotions_write on public.promotions;
create policy promotions_write on public.promotions for all to authenticated
  using (public.my_business_role(business_id) = any (array['OWNER', 'ADMIN']))
  with check (public.my_business_role(business_id) = any (array['OWNER', 'ADMIN']));

-- Cada venta guarda la promoción que se le aplicó
alter table public.sales add column if not exists promotion_id text;
alter table public.sales add column if not exists promotion_name text;
alter table public.sales add column if not exists promotion_discount numeric not null default 0;

create or replace function public.get_public_store(p_slug text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_store public.online_stores;
  v_business public.businesses;
begin
  select * into v_store from public.online_stores where slug = lower(trim(coalesce(p_slug, '')));
  if not found or not v_store.enabled then
    return null;
  end if;
  select * into v_business from public.businesses where id = v_store.business_id;
  if not found or coalesce(v_business.is_deleted, 0) = 1 then
    return null;
  end if;
  -- Sin Pro activo la tienda se apaga sola
  if not coalesce((public.business_pro_until(v_store.business_id) ->> 'active')::boolean, false) then
    return null;
  end if;

  return jsonb_build_object(
    'slug', v_store.slug,
    'whatsapp', v_store.whatsapp,
    'welcome', v_store.welcome,
    'template', v_store.template,
    'hero_title', v_store.hero_title,
    'hero_photos', v_store.hero_photos,
    'business', jsonb_build_object(
      'name', v_business.name,
      'logo_url', v_business.logo_url,
      'color', v_business.color,
      'currency', v_business.currency,
      'country', v_business.country
    ),
    'products', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', p.id,
        'name', p.name,
        'category', p.category,
        'price', p.sale_price,
        'old_price', case when p.compare_price > p.sale_price then p.compare_price end,
        'image_url', case when p.image_url like 'https://%' then p.image_url end,
        'stock', case when v_store.show_stock then p.current_stock end,
        'few', p.current_stock <= 3,
        -- Promoción vigente que más rebaja (0.13.4)
        'promo', (
          select jsonb_build_object(
            'name', pr.name, 'kind', pr.kind, 'percent_off', pr.percent_off,
            'buy_qty', pr.buy_qty, 'pay_qty', pr.pay_qty, 'ends_at', pr.ends_at
          )
          from public.promotions pr
          where pr.business_id = v_store.business_id and pr.is_active
            and now() >= pr.starts_at and now() < pr.ends_at
            and (pr.scope = 'ALL'
              or (pr.scope = 'CATEGORY' and lower(trim(coalesce(pr.category, ''))) = lower(trim(coalesce(p.category, ''))))
              -- Sin convertir a JSON: un texto mal formado no debe tumbar la tienda
              or (pr.scope = 'PRODUCTS' and coalesce(pr.product_ids, '') like '%"' || p.id || '"%'))
          order by case when pr.kind = 'PERCENT' then pr.percent_off else 100.0 * (pr.buy_qty - pr.pay_qty) / greatest(pr.buy_qty, 1) end desc
          limit 1
        ),
        'variants', coalesce((
          select jsonb_agg(jsonb_build_object(
            'id', v.id,
            'size', nullif(trim(v.attribute_value), ''),
            'color', nullif(trim(coalesce(v.attribute2_value, '')), ''),
            'hex', v.color_hex,
            'extra', v.additional_price,
            'stock', case when v_store.show_stock then greatest(v.stock, 0) end,
            'sold_out', v.stock <= 0,
            'few', v.stock between 1 and 3
          ) order by v.created_at)
          from public.product_variants v
          where v.product_id = p.id
        ), '[]'::jsonb)
      ) order by lower(coalesce(p.category, '')), lower(p.name))
      from (
        select * from public.products
        where business_id = v_store.business_id and current_stock > 0 and sale_price > 0
        order by lower(coalesce(category, '')), lower(name)
        limit 500
      ) p
    ), '[]'::jsonb)
  );
end;
$$;

revoke all on function public.get_public_store(text) from public;
grant execute on function public.get_public_store(text) to anon, authenticated;
