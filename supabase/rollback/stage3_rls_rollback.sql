-- Deshace la Etapa 3 (20261031000000_stage3_rls.sql) y vuelve al estado previo:
-- RLS desactivado y acceso del rol anon. Úsalo solo en una emergencia; deja la
-- base otra vez expuesta con la clave pública.
--
-- No borra link_my_memberships ni las funciones de la Etapa 2 (son aditivas).

-- Tablas: quitar políticas y RLS
do $$
declare
  t text;
  p record;
begin
  foreach t in array array['users', 'businesses', 'business_members', 'categories', 'products', 'customers', 'sales'] loop
    for p in select policyname from pg_policies where schemaname = 'public' and tablename = t loop
      execute format('drop policy %I on public.%I', p.policyname, t);
    end loop;
    execute format('alter table public.%I disable row level security', t);
  end loop;
end $$;

grant all on all tables in schema public to anon;
alter default privileges in schema public grant all on tables to anon;

drop trigger if exists limit_cashier_updates on public.products;
drop trigger if exists limit_cashier_updates on public.sales;
drop function if exists public.limit_cashier_updates();

-- Storage: volver a las políticas abiertas originales
drop policy if exists product_images_select on storage.objects;
drop policy if exists product_images_insert on storage.objects;
drop policy if exists product_images_update on storage.objects;
drop policy if exists product_images_delete on storage.objects;

create policy "Permitir ver imágenes de productos" on storage.objects for select to public
  using (bucket_id = 'product-images');
create policy "Permitir subida de imágenes de productos" on storage.objects for insert to public
  with check (bucket_id = 'product-images');
create policy "Permitir actualizar imágenes de productos" on storage.objects for update to public
  using (bucket_id = 'product-images');

-- Las funciones auxiliares e índices se pueden quedar: no dan acceso por sí solos.
