-- 0.16.0, fase 2a: tipos de negocio que venden productos.
--
-- • products.brand: la marca del producto («Elf Bar», «Tecnoquímicas»). La tienda en
--   línea filtra por marca.
-- • online_stores.look.adult: la tienda pregunta «¿Tienes 18 años o más?» (licoreras y
--   vapers). save_my_store_look lo guarda junto a lo demás de «Personalizar tienda».
-- • La tienda pública trae la marca de cada producto y cómo se llaman sus listas de
--   variantes («Nicotina» y «Sabor», «Presentación»…), para escribir «Elige el sabor».

alter table public.products add column if not exists brand text;
alter table public.products drop constraint if exists products_brand_check;
alter table public.products add constraint products_brand_check check (brand is null or char_length(brand) <= 60);

-- Tienda pública: la marca y los nombres de las listas de variantes
do $$
declare d text;
begin
  d := pg_get_functiondef('public.get_public_store(text)'::regprocedure);
  if position('''category'', p.category,' in d) = 0 or position('''size'', nullif(trim(v.attribute_value), ''''),' in d) = 0 then
    raise exception 'get_public_store cambió';
  end if;
  d := replace(d, '''category'', p.category,', '''category'', p.category, ''brand'', nullif(trim(coalesce(p.brand, '''')), ''''),');
  d := replace(d, '''size'', nullif(trim(v.attribute_value), ''''),',
    '''size'', nullif(trim(v.attribute_value), ''''), ''size_name'', nullif(trim(coalesce(v.attribute_name, '''')), ''''), ''option_name'', nullif(trim(coalesce(v.attribute2_name, '''')), ''''),');
  execute d;
end $$;

-- «Personalizar tienda» guarda también el aviso +18
do $$
declare d text;
begin
  d := pg_get_functiondef('public.save_my_store_look(text, jsonb)'::regprocedure);
  if position('''payment'', v_payment' in d) = 0 then
    raise exception 'save_my_store_look cambió';
  end if;
  execute replace(d, '''payment'', v_payment', '''payment'', v_payment, ''adult'', coalesce((p_look ->> ''adult'')::boolean, false)');
end $$;
