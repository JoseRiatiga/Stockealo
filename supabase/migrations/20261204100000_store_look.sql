-- 0.16.0, fase 1: la tienda se ve mejor.
--
-- • Tres plantillas nuevas: 'mercado', 'menu' y 'boutique' (además de 'clasica' y 'moda').
-- • online_stores.look: «Personalizar tienda» en un solo campo JSON:
--     {"accent": "#1D5FA8", "dark": true, "featured": ["id1", "id2"],
--      "schedule": {"days": [1,2,3,4,5,6], "open": "07:00", "close": "20:00"},
--      "payment": "Nequi 300 123 4567 a nombre de Rosa"}
--   Lo guarda save_my_store_look (dueño o administrador) y lo leen get_my_store y
--   get_public_store. Fuera del horario los pedidos se reciben con aviso: la nube no los
--   bloquea (decisión del dueño, 15 nov).
-- • La tienda pública trae la descripción de cada producto (la plantilla Menú la muestra).

alter table public.online_stores add column if not exists look jsonb not null default '{}'::jsonb;

-- Plantillas que se aceptan al guardar
do $$
declare d text;
begin
  d := pg_get_functiondef('public.save_my_store(text, text, boolean, text, text, boolean, text, text)'::regprocedure);
  if position('p_template in (''clasica'', ''moda'')' in d) = 0 then
    raise exception 'save_my_store cambió: revisar la lista de plantillas';
  end if;
  execute replace(d, 'p_template in (''clasica'', ''moda'')', 'p_template in (''clasica'', ''moda'', ''mercado'', ''menu'', ''boutique'')');
end $$;

-- get_my_store y get_public_store devuelven el look; la pública, también la descripción
do $$
declare d text;
begin
  d := pg_get_functiondef('public.get_my_store(text)'::regprocedure);
  if position('''hero_photos'', v_store.hero_photos,' in d) = 0 then
    raise exception 'get_my_store cambió';
  end if;
  execute replace(d, '''hero_photos'', v_store.hero_photos,', '''look'', coalesce(v_store.look, ''{}''::jsonb), ''hero_photos'', v_store.hero_photos,');

  d := pg_get_functiondef('public.get_public_store(text)'::regprocedure);
  if position('''hero_photos'', v_store.hero_photos,' in d) = 0 or position('''category'', p.category,' in d) = 0 then
    raise exception 'get_public_store cambió';
  end if;
  d := replace(d, '''hero_photos'', v_store.hero_photos,', '''look'', coalesce(v_store.look, ''{}''::jsonb), ''hero_photos'', v_store.hero_photos,');
  d := replace(d, '''category'', p.category,', '''category'', p.category, ''description'', nullif(left(trim(coalesce(p.description, '''')), 300), ''''),');
  execute d;
end $$;

create or replace function public.save_my_store_look(p_business_id text, p_look jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_accent text := p_look ->> 'accent';
  v_payment text := nullif(left(trim(coalesce(p_look ->> 'payment', '')), 300), '');
  v_featured jsonb := '[]'::jsonb;
  v_schedule jsonb;
  v_days jsonb;
  v_look jsonb;
begin
  if coalesce(public.my_business_role(p_business_id), '') not in ('OWNER', 'ADMIN') then
    raise exception 'not_allowed';
  end if;
  if not exists (select 1 from public.online_stores where business_id = p_business_id) then
    raise exception 'store_not_found';
  end if;
  if v_accent is not null and v_accent !~ '^#[0-9A-Fa-f]{6}$' then
    v_accent := null;
  end if;
  -- Hasta 6 destacados, solo productos del negocio
  if jsonb_typeof(p_look -> 'featured') = 'array' then
    select coalesce(jsonb_agg(f.id order by f.n), '[]'::jsonb) into v_featured
    from (
      select e.value as id, e.n
      from jsonb_array_elements_text(p_look -> 'featured') with ordinality as e(value, n)
      where exists (select 1 from public.products p where p.id = e.value and p.business_id = p_business_id)
      order by e.n
      limit 6
    ) f;
  end if;
  -- Horario: días 1 a 7 y horas HH:MM
  if jsonb_typeof(p_look -> 'schedule') = 'object' then
    select coalesce(jsonb_agg(distinct (d.value)::int), '[]'::jsonb) into v_days
    from jsonb_array_elements_text(coalesce(p_look -> 'schedule' -> 'days', '[]'::jsonb)) as d(value)
    where d.value ~ '^[1-7]$';
    if jsonb_array_length(v_days) > 0
       and (p_look -> 'schedule' ->> 'open') ~ '^([01]?[0-9]|2[0-3]):[0-5][0-9]$'
       and (p_look -> 'schedule' ->> 'close') ~ '^([01]?[0-9]|2[0-3]):[0-5][0-9]$' then
      v_schedule := jsonb_build_object('days', v_days, 'open', p_look -> 'schedule' ->> 'open', 'close', p_look -> 'schedule' ->> 'close');
    end if;
  end if;

  v_look := jsonb_strip_nulls(jsonb_build_object(
    'accent', upper(v_accent),
    'dark', coalesce((p_look ->> 'dark')::boolean, false),
    'featured', v_featured,
    'schedule', v_schedule,
    'payment', v_payment
  ));
  update public.online_stores set look = v_look, updated_at = now() where business_id = p_business_id;
  return v_look;
end;
$$;

revoke all on function public.save_my_store_look(text, jsonb) from public, anon;
grant execute on function public.save_my_store_look(text, jsonb) to authenticated;
