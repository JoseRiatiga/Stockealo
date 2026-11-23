-- 0.17.0: sin Pro permanente (decisión del dueño, 23 nov). Lo que se regala desde el
-- panel (Dar Pro / Pro Servicios y los códigos) dura como mucho 1 año; la nube tampoco
-- acepta «permanente» (días en null) aunque alguien lo pida por fuera del panel.

do $$
declare d text;
begin
  d := pg_get_functiondef('public.admin_grant_pro(text,integer,text)'::regprocedure);
  if position('if p_days is not null and (p_days < 1 or p_days > 3650) then' in d) = 0 then
    raise exception 'admin_grant_pro cambió';
  end if;
  d := replace(d, 'if p_days is not null and (p_days < 1 or p_days > 3650) then',
    'if p_days is null or p_days < 1 or p_days > 366 then');
  execute d;
end $$;

do $$
declare d text;
begin
  d := pg_get_functiondef('public.admin_create_pro_codes(text,integer,integer,text,integer,integer)'::regprocedure);
  if position('if p_days is not null and (p_days < 1 or p_days > 3650) then raise exception ''invalid_days''; end if;' in d) = 0 then
    raise exception 'admin_create_pro_codes cambió';
  end if;
  d := replace(d, 'if p_days is not null and (p_days < 1 or p_days > 3650) then raise exception ''invalid_days''; end if;',
    'if p_days is null or p_days < 1 or p_days > 366 then raise exception ''invalid_days''; end if;');
  execute d;
end $$;

-- Hallazgo de la revisión: un código permanente ya creado (días en null) tampoco da
-- Pro sin fin al canjearlo: vale 1 año. Los que haya se pasan a 365 días.
update public.pro_codes set days = 365 where days is null;

do $$
declare d text;
begin
  d := pg_get_functiondef('public.redeem_pro_code(text,text)'::regprocedure);
  if position('v_end := case when v_code.days is null then null' in d) = 0 then
    raise exception 'redeem_pro_code cambió';
  end if;
  d := replace(d, 'v_end := case when v_code.days is null then null',
    'v_end := case when false then null');
  d := replace(d, 'make_interval(days => v_code.days)',
    'make_interval(days => least(coalesce(v_code.days, 365), 366))');
  execute d;
end $$;

-- Un pago de un plan sin periodo conocido (el permanente, apagado) tampoco queda sin fin
do $$
declare d text;
begin
  d := pg_get_functiondef('public.pro_apply_payment(text,text,text,text,bigint,text)'::regprocedure);
  if position('when ''year'' then v_from + interval ''365 days''
      else null' in d) = 0 then
    raise exception 'pro_apply_payment cambió';
  end if;
  d := replace(d, 'when ''year'' then v_from + interval ''365 days''
      else null', 'when ''year'' then v_from + interval ''365 days''
      else v_from + interval ''365 days''');
  execute d;
end $$;
