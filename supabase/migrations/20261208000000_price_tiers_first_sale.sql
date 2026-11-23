-- 0.17.0 (docs/plan-0.17.0.md)
--
-- B. Precios al por mayor (Pro): products.price_tiers, una lista JSON de hasta 3
--    escalones {"min": 12, "price": 1800}. Un celular viejo no manda la columna y la
--    nube conserva lo que tenía. La tienda pública la recibe para mostrarla y cobrarla.
-- A. Panel admin: «Negocios sin primera venta» (con productos y sin ventas de verdad),
--    con días desde que se crearon y el teléfono de «Datos del recibo» si lo pusieron.
--    Solo nombre, dueño y conteos: nunca productos, ventas ni plata.

alter table public.products add column if not exists price_tiers jsonb;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'products_price_tiers_check') then
    alter table public.products add constraint products_price_tiers_check
      check (price_tiers is null or (jsonb_typeof(price_tiers) = 'array' and jsonb_array_length(price_tiers) <= 3));
  end if;
end $$;

-- Tienda pública: los escalones de cada producto
do $$
declare d text;
begin
  d := pg_get_functiondef('public.get_public_store(text)'::regprocedure);
  if position('''price'', p.sale_price,' in d) = 0 then
    raise exception 'get_public_store cambió';
  end if;
  d := replace(d, '''price'', p.sale_price,',
    '''price'', p.sale_price, ''price_tiers'', case when jsonb_typeof(p.price_tiers) = ''array'' and jsonb_array_length(p.price_tiers) > 0 then p.price_tiers end,');
  execute d;
end $$;

-- El teléfono de «Datos del recibo»; null si no hay o el texto no es JSON
create or replace function public._ticket_phone(p_info text)
returns text
language plpgsql
immutable
set search_path = ''
as $$
begin
  return nullif(left(trim(coalesce(p_info::jsonb ->> 'phone', '')), 30), '');
exception when others then
  return null;
end;
$$;

revoke all on function public._ticket_phone(text) from public, anon;

-- Panel: negocios con productos y sin primera venta
create or replace function public.admin_first_sale_pending()
returns table(id text, name text, owner_email text, phone text, country text, created_at timestamptz, products integer)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform public.admin_guard();
  return query
    select b.id, b.name,
           (select m.user_email from public.business_members m where m.business_id = b.id and m.role = 'OWNER' limit 1),
           public._ticket_phone(b.ticket_info),
           b.country,
           b.created_at,
           (select count(*)::integer from public.products p where p.business_id = b.id)
      from public.businesses b
     where coalesce(b.is_deleted, 0) = 0
       and exists (select 1 from public.products p where p.business_id = b.id)
       and not exists (
         select 1 from public.sales s
          where s.business_id = b.id and s.voided_at is null and coalesce(s.quantity, 0) > 0
       )
     order by b.created_at desc
     limit 200;
end;
$$;

revoke all on function public.admin_first_sale_pending() from public, anon;
grant execute on function public.admin_first_sale_pending() to authenticated;
