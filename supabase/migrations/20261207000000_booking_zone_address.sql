-- 0.16.9 (docs/plan-0.16.9.md)
--
-- 1. Reservas con la hora del negocio: la página de reservas recibe la zona del
--    negocio y muestra las horas libres con ella, no con la del celular del cliente.
-- 1b. La dirección del negocio en la tienda y las reservas: la misma de «Datos del
--    recibo» (businesses.ticket_info, JSON con "address"). Sale si el negocio la
--    escribió y no apagó «Mostrar la dirección» (look.address; si falta, se muestra).

-- La dirección de «Datos del recibo»; null si no hay o el texto no es JSON
create or replace function public._ticket_address(p_info text)
returns text
language plpgsql
immutable
set search_path = ''
as $$
begin
  return nullif(left(trim(coalesce(p_info::jsonb ->> 'address', '')), 120), '');
exception when others then
  return null;
end;
$$;

-- Reservas: la zona del negocio
do $$
declare d text;
begin
  d := pg_get_functiondef('public.get_public_booking(text,timestamptz,timestamptz)'::regprocedure);
  if position('''schedule'', v_business.services_schedule,' in d) = 0 then
    raise exception 'get_public_booking cambió';
  end if;
  d := replace(d, '''schedule'', v_business.services_schedule,',
    '''schedule'', v_business.services_schedule, ''time_zone'', public.business_time_zone(v_store.business_id),');
  execute d;
end $$;

-- Tienda pública: la dirección (si se muestra) y la zona del negocio
do $$
declare d text;
begin
  d := pg_get_functiondef('public.get_public_store(text)'::regprocedure);
  if position('''country'', v_business.country' in d) = 0 then
    raise exception 'get_public_store cambió';
  end if;
  d := replace(d, '''country'', v_business.country',
    '''country'', v_business.country, ''time_zone'', public.business_time_zone(v_business.id), ''address'', case when coalesce((v_store.look ->> ''address'')::boolean, true) then public._ticket_address(v_business.ticket_info) end');
  execute d;
end $$;

-- «Personalizar tienda»: mostrar u ocultar la dirección
do $$
declare d text;
begin
  d := pg_get_functiondef('public.save_my_store_look(text, jsonb)'::regprocedure);
  if position('''icons'', coalesce((p_look ->> ''icons'')::boolean, true),' in d) = 0 then
    raise exception 'save_my_store_look cambió';
  end if;
  d := replace(d, '''icons'', coalesce((p_look ->> ''icons'')::boolean, true),',
    '''icons'', coalesce((p_look ->> ''icons'')::boolean, true), ''address'', coalesce((p_look ->> ''address'')::boolean, true),');
  execute d;
end $$;
