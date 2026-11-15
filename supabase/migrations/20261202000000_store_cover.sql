-- 0.15.0: portada propia de la tienda (pedido del dueño, 14 nov 2026).
-- El negocio sube su propia foto de portada (su logo grande, un banner o una foto del
-- local). null = no hay foto propia: la portada sigue como antes (fotos de productos
-- según hero_photos, o solo el color).

alter table public.online_stores add column if not exists hero_image_url text;

-- get_my_store y get_public_store ya devuelven 'hero_photos'; se les suma
-- 'hero_image_url' sin reescribir el resto (la versión vigente de get_public_store es
-- la de 20261130300000_promotions.sql). Si ya lo tienen, no se toca nada.
do $$
declare
  v_fn text;
  v_def text;
begin
  foreach v_fn in array array['public.get_my_store(text)', 'public.get_public_store(text)'] loop
    v_def := pg_get_functiondef(v_fn::regprocedure);
    if position('hero_image_url' in v_def) = 0 then
      if position('''hero_photos'', v_store.hero_photos' in v_def) = 0 then
        raise exception 'No se encontró hero_photos en %', v_fn;
      end if;
      v_def := replace(
        v_def,
        '''hero_photos'', v_store.hero_photos',
        '''hero_photos'', v_store.hero_photos, ''hero_image_url'', case when v_store.hero_image_url like ''https://%'' then v_store.hero_image_url end'
      );
      execute v_def;
    end if;
  end loop;
end;
$$;

-- Guardar con la portada propia (las versiones de 6, 8 y 9 datos siguen para la app anterior)
create or replace function public.save_my_store(
  p_business_id text, p_slug text, p_enabled boolean, p_whatsapp text, p_welcome text, p_show_stock boolean,
  p_template text, p_hero_title text, p_hero_photos boolean, p_hero_image_url text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_hero_image_url is not null and p_hero_image_url not like 'https://%' then
    raise exception 'invalid_image';
  end if;
  perform public.save_my_store(p_business_id, p_slug, p_enabled, p_whatsapp, p_welcome, p_show_stock, p_template, p_hero_title, p_hero_photos);
  update public.online_stores set hero_image_url = nullif(trim(p_hero_image_url), ''), updated_at = now()
  where business_id = p_business_id;
  return public.get_my_store(p_business_id);
end;
$$;

revoke all on function public.save_my_store(text, text, boolean, text, text, boolean, text, text, boolean, text) from public, anon;
grant execute on function public.save_my_store(text, text, boolean, text, text, boolean, text, text, boolean, text) to authenticated;
