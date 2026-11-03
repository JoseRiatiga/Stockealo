-- Stockealo Pro, fase 5 (versión 0.9.2): tienda en línea
--
-- Cada negocio con Pro puede publicar su tienda en stockealo.online/tienda/<slug>.
-- El comprador ve los productos con stock, arma un carrito y envía el pedido por
-- WhatsApp al negocio: no hay pagos en línea ni pedidos guardados en el servidor.
--
-- Seguridad:
--   • online_stores no tiene acceso directo: solo funciones
--   • la tienda pública solo existe si está encendida, el negocio no está borrado
--     y tiene Pro activo; solo expone nombre, categoría, precio, foto y (si el dueño
--     quiere) unidades. Nunca costos, clientes ni ventas.
--   • solo el dueño o un administrador del negocio la configuran
-- No modifica tablas existentes.

create table if not exists public.online_stores (
  business_id text primary key references public.businesses (id) on delete cascade,
  -- Nombre en la dirección: minúsculas, números y guiones (3 a 40)
  slug text not null unique check (slug ~ '^[a-z0-9][a-z0-9-]{1,38}[a-z0-9]$'),
  enabled boolean not null default true,
  -- WhatsApp que recibe los pedidos, internacional y solo dígitos (573001234567)
  whatsapp text not null check (whatsapp ~ '^[0-9]{8,15}$'),
  welcome text check (welcome is null or char_length(welcome) <= 280),
  show_stock boolean not null default false,
  updated_at timestamptz not null default now()
);
alter table public.online_stores enable row level security;
revoke all on public.online_stores from anon, authenticated;

-- ---------------------------------------------------------------------------
-- Configuración de la tienda de un negocio (cualquier miembro la puede ver)
-- ---------------------------------------------------------------------------
create or replace function public.get_my_store(p_business_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_store public.online_stores;
begin
  if public.my_business_role(p_business_id) is null then
    raise exception 'not_member';
  end if;
  select * into v_store from public.online_stores where business_id = p_business_id;
  if not found then
    return null;
  end if;
  return jsonb_build_object(
    'slug', v_store.slug,
    'enabled', v_store.enabled,
    'whatsapp', v_store.whatsapp,
    'welcome', v_store.welcome,
    'show_stock', v_store.show_stock
  );
end;
$$;

revoke all on function public.get_my_store(text) from public, anon;
grant execute on function public.get_my_store(text) to authenticated;

-- ---------------------------------------------------------------------------
-- Crear o cambiar la tienda (dueño o administrador, con Pro para encenderla)
-- ---------------------------------------------------------------------------
create or replace function public.save_my_store(
  p_business_id text,
  p_slug text,
  p_enabled boolean,
  p_whatsapp text,
  p_welcome text default null,
  p_show_stock boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_slug text := lower(trim(coalesce(p_slug, '')));
  v_whatsapp text := regexp_replace(coalesce(p_whatsapp, ''), '[^0-9]', '', 'g');
  v_welcome text := nullif(trim(coalesce(p_welcome, '')), '');
begin
  if coalesce(public.my_business_role(p_business_id), '') not in ('OWNER', 'ADMIN') then
    raise exception 'not_allowed';
  end if;
  if v_slug !~ '^[a-z0-9][a-z0-9-]{1,38}[a-z0-9]$'
     or v_slug in ('app', 'admin', 'tienda', 'api', 'www', 'stockealo', 'soporte', 'ayuda') then
    raise exception 'invalid_slug';
  end if;
  if v_whatsapp !~ '^[0-9]{8,15}$' then
    raise exception 'invalid_whatsapp';
  end if;
  if char_length(coalesce(v_welcome, '')) > 280 then
    raise exception 'welcome_too_long';
  end if;
  if exists (select 1 from public.online_stores where slug = v_slug and business_id <> p_business_id) then
    raise exception 'slug_taken';
  end if;
  if coalesce(p_enabled, false) and not coalesce((public.business_pro_until(p_business_id) ->> 'active')::boolean, false) then
    raise exception 'pro_required';
  end if;

  insert into public.online_stores (business_id, slug, enabled, whatsapp, welcome, show_stock, updated_at)
  values (p_business_id, v_slug, coalesce(p_enabled, false), v_whatsapp, v_welcome, coalesce(p_show_stock, false), now())
  on conflict (business_id) do update set
    slug = excluded.slug,
    enabled = excluded.enabled,
    whatsapp = excluded.whatsapp,
    welcome = excluded.welcome,
    show_stock = excluded.show_stock,
    updated_at = now();

  return public.get_my_store(p_business_id);
end;
$$;

revoke all on function public.save_my_store(text, text, boolean, text, text, boolean) from public, anon;
grant execute on function public.save_my_store(text, text, boolean, text, text, boolean) to authenticated;

-- ---------------------------------------------------------------------------
-- Tienda pública (cualquiera, sin sesión). null si no existe o no está disponible.
-- ---------------------------------------------------------------------------
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
        'image_url', case when p.image_url like 'https://%' then p.image_url end,
        'stock', case when v_store.show_stock then p.current_stock end
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
