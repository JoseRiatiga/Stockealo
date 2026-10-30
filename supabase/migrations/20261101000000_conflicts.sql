-- Fase 3 · Conflictos entre dispositivos.
--
-- 1. updated_at en productos, clientes, categorías y negocios. Si llega una
--    edición más vieja que la guardada (un teléfono que estuvo sin conexión),
--    se ignora en lugar de pisar el cambio más reciente.
-- 2. El stock y las deudas se ajustan por diferencia ("resta 1", "suma 2.500")
--    para que dos cajeros vendiendo a la vez no se pisen entre sí.

alter table public.products add column if not exists updated_at timestamptz not null default now();
alter table public.customers add column if not exists updated_at timestamptz not null default now();
alter table public.categories add column if not exists updated_at timestamptz not null default now();
alter table public.businesses add column if not exists updated_at timestamptz not null default now();

create or replace function public.keep_newer_row()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  -- Edición más vieja que la guardada: se descarta sin error
  if new.updated_at < old.updated_at then
    return null;
  end if;
  return new;
end;
$$;

revoke all on function public.keep_newer_row() from public, anon, authenticated;

drop trigger if exists keep_newer_row on public.products;
create trigger keep_newer_row before update on public.products
  for each row execute function public.keep_newer_row();
drop trigger if exists keep_newer_row on public.customers;
create trigger keep_newer_row before update on public.customers
  for each row execute function public.keep_newer_row();
drop trigger if exists keep_newer_row on public.categories;
create trigger keep_newer_row before update on public.categories
  for each row execute function public.keep_newer_row();
drop trigger if exists keep_newer_row on public.businesses;
create trigger keep_newer_row before update on public.businesses
  for each row execute function public.keep_newer_row();

-- SECURITY INVOKER: aplican las políticas RLS de quien llama (el cajero puede
-- ajustar stock y deudas de su negocio; nadie ajusta los de otro negocio)
create or replace function public.adjust_product_stock(p_product_id text, p_delta integer)
returns void
language sql
security invoker
set search_path = ''
as $$
  update public.products set current_stock = current_stock + p_delta where id = p_product_id;
$$;

create or replace function public.adjust_customer_debt(p_customer_id text, p_delta numeric)
returns void
language sql
security invoker
set search_path = ''
as $$
  update public.customers set debt_balance = greatest(0, debt_balance + p_delta) where id = p_customer_id;
$$;

revoke all on function public.adjust_product_stock(text, integer) from public, anon;
revoke all on function public.adjust_customer_debt(text, numeric) from public, anon;
grant execute on function public.adjust_product_stock(text, integer) to authenticated;
grant execute on function public.adjust_customer_debt(text, numeric) to authenticated;
