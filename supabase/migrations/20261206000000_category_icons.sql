-- 0.16.8 · Fase 4 (docs/plan-0.16.8.md)
--
-- A. Íconos de categoría (#28)
-- • categories.icon: clave de un dibujo de la app («drink», «shoe»…); null = sin elegir.
-- • La tienda pública trae el ícono de cada categoría (por nombre, en minúscula).
-- • «Personalizar tienda» guarda si se muestran (look.icons; si falta, se muestran).
--
-- C. Fiado en el pago mixto (#19)
-- • Una venta mixta con una parte fiada pide el permiso «credit» igual que un fiado.

alter table public.categories add column if not exists icon text;
alter table public.categories drop constraint if exists categories_icon_check;
alter table public.categories add constraint categories_icon_check check (icon is null or icon ~ '^[a-z_]{1,40}$');

-- Tienda pública: los íconos de las categorías
do $$
declare d text;
begin
  d := pg_get_functiondef('public.get_public_store(text)'::regprocedure);
  if position('''look'', coalesce(v_store.look, ''{}''::jsonb),' in d) = 0 then
    raise exception 'get_public_store cambió';
  end if;
  d := replace(d, '''look'', coalesce(v_store.look, ''{}''::jsonb),',
    '''look'', coalesce(v_store.look, ''{}''::jsonb), ''category_icons'', coalesce((select jsonb_object_agg(lower(trim(c.name)), c.icon) from public.categories c where c.business_id = v_store.business_id and c.icon is not null), ''{}''::jsonb),');
  execute d;
end $$;

-- «Personalizar tienda»: mostrar u ocultar los íconos de categoría
do $$
declare d text;
begin
  d := pg_get_functiondef('public.save_my_store_look(text, jsonb)'::regprocedure);
  if position('''adult'', coalesce((p_look ->> ''adult'')::boolean, false),' in d) = 0 then
    raise exception 'save_my_store_look cambió';
  end if;
  d := replace(d, '''adult'', coalesce((p_look ->> ''adult'')::boolean, false),',
    '''adult'', coalesce((p_look ->> ''adult'')::boolean, false), ''icons'', coalesce((p_look ->> ''icons'')::boolean, true),');
  execute d;
end $$;

-- Ventas: la parte fiada de un pago mixto también pide permiso para fiar
do $$
declare d text;
begin
  d := pg_get_functiondef('public._check_sale()'::regprocedure);
  if position('if upper(coalesce(new.payment_method, '''')) = ''FIADO'' and not public.has_permission(new.business_id, ''credit'') then' in d) = 0 then
    raise exception '_check_sale cambió';
  end if;
  d := replace(d,
    'if upper(coalesce(new.payment_method, '''')) = ''FIADO'' and not public.has_permission(new.business_id, ''credit'') then',
    'if (upper(coalesce(new.payment_method, '''')) = ''FIADO'' or (upper(coalesce(new.payment_method, '''')) = ''MIXTO'' and coalesce(new.payment_split, '''') like ''%"FIADO"%'')) and not public.has_permission(new.business_id, ''credit'') then');
  execute d;
end $$;
