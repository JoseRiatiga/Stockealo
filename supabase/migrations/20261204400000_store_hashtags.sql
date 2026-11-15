-- 0.16.0, fase 3: vender por redes.
--
-- «Personalizar tienda» guarda también los hashtags propios del negocio para Instagram
-- (hasta 10, cada uno «#Palabra» de hasta 40 letras, números o guion bajo). El link de
-- un producto (?p=<id>) y el QR de la tienda no necesitan nada en la nube.

do $$
declare d text;
begin
  d := pg_get_functiondef('public.save_my_store_look(text, jsonb)'::regprocedure);
  if position('''adult'', coalesce((p_look ->> ''adult'')::boolean, false)' in d) = 0 then
    raise exception 'save_my_store_look cambió';
  end if;
  execute replace(d,
    '''adult'', coalesce((p_look ->> ''adult'')::boolean, false)',
    '''adult'', coalesce((p_look ->> ''adult'')::boolean, false), '
    || '''hashtags'', case when jsonb_typeof(p_look -> ''hashtags'') = ''array'' then ('
    || 'select nullif(coalesce(jsonb_agg(h.value), ''[]''::jsonb), ''[]''::jsonb) from ('
    || 'select e.value from jsonb_array_elements_text(p_look -> ''hashtags'') as e(value) '
    || 'where e.value ~ ''^#[0-9A-Za-zÁÉÍÓÚÜÑáéíóúüñ_]{1,40}$'' limit 10) h) end');
end $$;
