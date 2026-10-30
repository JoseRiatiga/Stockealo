-- Fase 1 · Etapa 3: Row Level Security.
--
-- Cada cuenta solo lee y modifica los negocios donde es miembro, según su rol:
--   OWNER  todo, incluido cambiar roles, quitar miembros y borrar el negocio
--   ADMIN  catálogo, stock, ventas, clientes, datos del negocio e invitar cajeros
--   CASHIER ver, vender (incluye descontar stock) y gestionar clientes y abonos
-- Sin sesión (rol anon) no se puede leer ni escribir ninguna tabla.
--
-- La identidad es el correo verificado de la sesión (auth.email()), porque
-- business_members.user_id guarda el id de la app y en cuentas antiguas difiere
-- del id de Supabase Auth.
--
-- Aplicar SOLO cuando la mayoría de usuarios tenga la versión de la app con las
-- Etapas 1–3: las versiones anteriores no inician sesión en Supabase y dejan de
-- sincronizar. Para deshacer: supabase/rollback/stage3_rls_rollback.sql

-- ---------------------------------------------------------------------------
-- Funciones auxiliares (SECURITY DEFINER: leen business_members sin pasar por RLS)
-- ---------------------------------------------------------------------------

-- Rol de la cuenta en sesión dentro de un negocio (null si no es miembro)
create or replace function public.my_business_role(p_business_id text)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select m.role
  from public.business_members m
  where m.business_id = p_business_id
    and lower(m.user_email) = lower(auth.email())
  order by case m.role when 'OWNER' then 1 when 'ADMIN' then 2 else 3 end
  limit 1;
$$;

-- ¿El negocio todavía no tiene miembros? (permite al creador registrarse como dueño)
create or replace function public.business_has_no_members(p_business_id text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select not exists (select 1 from public.business_members m where m.business_id = p_business_id);
$$;

-- ¿La cuenta en sesión comparte algún negocio con este perfil?
create or replace function public.shares_business_with(p_user_id text, p_email text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.business_members mine
    join public.business_members theirs on theirs.business_id = mine.business_id
    where lower(mine.user_email) = lower(auth.email())
      and (theirs.user_id = p_user_id or lower(theirs.user_email) = lower(p_email))
  );
$$;

revoke all on function public.my_business_role(text) from public, anon;
revoke all on function public.business_has_no_members(text) from public, anon;
revoke all on function public.shares_business_with(text, text) from public, anon;
grant execute on function public.my_business_role(text) to authenticated;
grant execute on function public.business_has_no_members(text) to authenticated;
grant execute on function public.shares_business_with(text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- El cajero puede descontar stock y sincronizar, pero no cambiar nada más
-- ---------------------------------------------------------------------------
create or replace function public.limit_cashier_updates()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_stock integer;
begin
  -- Llamadas del servidor (service role) no tienen correo y no se limitan
  if public.my_business_role(old.business_id) is distinct from 'CASHIER' then
    return new;
  end if;

  if tg_table_name = 'products' then
    v_stock := new.current_stock;
    new := old;
    new.current_stock := v_stock;
  else
    new := old; -- ventas: la sincronización del cajero no puede editarlas
  end if;
  return new;
end;
$$;

drop trigger if exists limit_cashier_updates on public.products;
create trigger limit_cashier_updates
  before update on public.products
  for each row execute function public.limit_cashier_updates();

drop trigger if exists limit_cashier_updates on public.sales;
create trigger limit_cashier_updates
  before update on public.sales
  for each row execute function public.limit_cashier_updates();

-- ---------------------------------------------------------------------------
-- Índices para que las comprobaciones de permisos no recorran toda la tabla
-- ---------------------------------------------------------------------------
create index if not exists business_members_business_email_idx
  on public.business_members (business_id, lower(user_email));
create index if not exists business_members_email_idx
  on public.business_members (lower(user_email));
create index if not exists categories_business_idx on public.categories (business_id);
create index if not exists products_business_idx on public.products (business_id);
create index if not exists customers_business_idx on public.customers (business_id);
create index if not exists sales_business_idx on public.sales (business_id);

-- ---------------------------------------------------------------------------
-- Sin sesión no hay acceso a ninguna tabla
-- ---------------------------------------------------------------------------
revoke all on all tables in schema public from anon;
alter default privileges in schema public revoke all on tables from anon;

alter table public.users enable row level security;
alter table public.businesses enable row level security;
alter table public.business_members enable row level security;
alter table public.categories enable row level security;
alter table public.products enable row level security;
alter table public.customers enable row level security;
alter table public.sales enable row level security;

-- ---------------------------------------------------------------------------
-- users: tu perfil y el de tus compañeros de negocio
-- ---------------------------------------------------------------------------
create policy users_select on public.users for select to authenticated
  using (lower(email) = lower(auth.email()) or public.shares_business_with(id, email));
create policy users_insert on public.users for insert to authenticated
  with check (lower(email) = lower(auth.email()));
create policy users_update on public.users for update to authenticated
  using (lower(email) = lower(auth.email()))
  with check (lower(email) = lower(auth.email()));
-- Sin política de delete: lo hace la Edge Function delete-account

-- ---------------------------------------------------------------------------
-- businesses
-- ---------------------------------------------------------------------------
create policy businesses_select on public.businesses for select to authenticated
  using (public.my_business_role(id) is not null);
create policy businesses_insert on public.businesses for insert to authenticated
  with check (true);
create policy businesses_update on public.businesses for update to authenticated
  using (public.my_business_role(id) in ('OWNER', 'ADMIN'))
  with check (public.my_business_role(id) in ('OWNER', 'ADMIN'));
create policy businesses_delete on public.businesses for delete to authenticated
  using (public.my_business_role(id) = 'OWNER');

-- ---------------------------------------------------------------------------
-- business_members
-- ---------------------------------------------------------------------------
create policy members_select on public.business_members for select to authenticated
  using (public.my_business_role(business_id) is not null);
create policy members_insert on public.business_members for insert to authenticated
  with check (
    public.my_business_role(business_id) = 'OWNER'
    or (public.my_business_role(business_id) = 'ADMIN' and role = 'CASHIER')
    or (
      role = 'OWNER'
      and lower(user_email) = lower(auth.email())
      and public.business_has_no_members(business_id)
    )
  );
create policy members_update on public.business_members for update to authenticated
  using (public.my_business_role(business_id) = 'OWNER')
  with check (public.my_business_role(business_id) = 'OWNER');
create policy members_delete on public.business_members for delete to authenticated
  using (
    public.my_business_role(business_id) = 'OWNER'
    or (lower(user_email) = lower(auth.email()) and role <> 'OWNER')
  );

-- ---------------------------------------------------------------------------
-- categories: catálogo, solo dueño y admin lo modifican
-- ---------------------------------------------------------------------------
create policy categories_select on public.categories for select to authenticated
  using (public.my_business_role(business_id) is not null);
create policy categories_insert on public.categories for insert to authenticated
  with check (public.my_business_role(business_id) in ('OWNER', 'ADMIN'));
create policy categories_update on public.categories for update to authenticated
  using (public.my_business_role(business_id) in ('OWNER', 'ADMIN'))
  with check (public.my_business_role(business_id) in ('OWNER', 'ADMIN'));
create policy categories_delete on public.categories for delete to authenticated
  using (public.my_business_role(business_id) in ('OWNER', 'ADMIN'));

-- ---------------------------------------------------------------------------
-- products: el cajero solo puede cambiar el stock (ver limit_cashier_updates)
-- ---------------------------------------------------------------------------
create policy products_select on public.products for select to authenticated
  using (public.my_business_role(business_id) is not null);
create policy products_insert on public.products for insert to authenticated
  with check (public.my_business_role(business_id) in ('OWNER', 'ADMIN'));
create policy products_update on public.products for update to authenticated
  using (public.my_business_role(business_id) is not null)
  with check (public.my_business_role(business_id) is not null);
create policy products_delete on public.products for delete to authenticated
  using (public.my_business_role(business_id) in ('OWNER', 'ADMIN'));

-- ---------------------------------------------------------------------------
-- customers: todos los miembros gestionan clientes y abonos; borrar, dueño y admin
-- ---------------------------------------------------------------------------
create policy customers_select on public.customers for select to authenticated
  using (public.my_business_role(business_id) is not null);
create policy customers_insert on public.customers for insert to authenticated
  with check (public.my_business_role(business_id) is not null);
create policy customers_update on public.customers for update to authenticated
  using (public.my_business_role(business_id) is not null)
  with check (public.my_business_role(business_id) is not null);
create policy customers_delete on public.customers for delete to authenticated
  using (public.my_business_role(business_id) in ('OWNER', 'ADMIN'));

-- ---------------------------------------------------------------------------
-- sales: todos venden; anular (borrar), dueño y admin
-- ---------------------------------------------------------------------------
create policy sales_select on public.sales for select to authenticated
  using (public.my_business_role(business_id) is not null);
create policy sales_insert on public.sales for insert to authenticated
  with check (public.my_business_role(business_id) is not null);
create policy sales_update on public.sales for update to authenticated
  using (public.my_business_role(business_id) is not null)
  with check (public.my_business_role(business_id) is not null);
create policy sales_delete on public.sales for delete to authenticated
  using (public.my_business_role(business_id) in ('OWNER', 'ADMIN'));

-- ---------------------------------------------------------------------------
-- Storage product-images: carpeta = id del negocio. El bucket sigue siendo
-- público para mostrar las fotos por URL; solo dueño y admin suben o borran.
-- ---------------------------------------------------------------------------
drop policy if exists "Permitir ver imágenes de productos" on storage.objects;
drop policy if exists "Permitir subida de imágenes de productos" on storage.objects;
drop policy if exists "Permitir actualizar imágenes de productos" on storage.objects;

create policy product_images_select on storage.objects for select to authenticated
  using (bucket_id = 'product-images'
         and public.my_business_role((storage.foldername(name))[1]) is not null);
create policy product_images_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'product-images'
              and public.my_business_role((storage.foldername(name))[1]) in ('OWNER', 'ADMIN'));
create policy product_images_update on storage.objects for update to authenticated
  using (bucket_id = 'product-images'
         and public.my_business_role((storage.foldername(name))[1]) in ('OWNER', 'ADMIN'))
  with check (bucket_id = 'product-images'
              and public.my_business_role((storage.foldername(name))[1]) in ('OWNER', 'ADMIN'));
create policy product_images_delete on storage.objects for delete to authenticated
  using (bucket_id = 'product-images'
         and public.my_business_role((storage.foldername(name))[1]) in ('OWNER', 'ADMIN'));
