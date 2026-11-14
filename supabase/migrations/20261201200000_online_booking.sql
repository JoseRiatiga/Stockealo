-- 0.14.0: reservas en línea desde la tienda (solo con Pro Servicios).
--   • get_public_booking: servicios, empleados, horario del negocio y lo ocupado del día.
--   • create_booking: el cliente (sin cuenta) pide su cita; llega PENDIENTE y en línea,
--     y el negocio la confirma en Servicios › Agenda. No deja pedir una hora ocupada.

create or replace function public.get_public_booking(p_slug text, p_from timestamptz, p_to timestamptz)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_store public.online_stores;
  v_business public.businesses;
begin
  select * into v_store from public.online_stores where slug = lower(trim(coalesce(p_slug, '')));
  if not found or not v_store.enabled then
    return null;
  end if;
  select * into v_business from public.businesses where id = v_store.business_id;
  if not found or coalesce(v_business.is_deleted, 0) = 1
     or not coalesce((public.business_pro_until(v_store.business_id) ->> 'services')::boolean, false) then
    return null;
  end if;
  return jsonb_build_object(
    'schedule', v_business.services_schedule,
    'services', coalesce((
      select jsonb_agg(jsonb_build_object('id', s.id, 'name', s.name, 'price', s.price, 'duration_min', coalesce(s.duration_min, 30))
        order by s.name)
      from public.services s where s.business_id = v_store.business_id and s.is_active
    ), '[]'::jsonb),
    'staff', coalesce((
      select jsonb_agg(jsonb_build_object('id', st.id, 'name', st.name) order by st.name)
      from public.staff st where st.business_id = v_store.business_id and st.is_active
    ), '[]'::jsonb),
    -- Solo las horas ocupadas (sin nombres de clientes)
    'busy', coalesce((
      select jsonb_agg(jsonb_build_object(
        'staff_id', a.staff_id, 'starts_at', a.starts_at,
        'ends_at', a.starts_at + make_interval(mins => a.duration_min)))
      from public.appointments a
      where a.business_id = v_store.business_id and a.status in ('PENDIENTE', 'CONFIRMADA')
        and a.starts_at < p_to and a.starts_at + make_interval(mins => a.duration_min) > p_from
    ), '[]'::jsonb)
  );
end;
$$;

revoke all on function public.get_public_booking(text, timestamptz, timestamptz) from public;
grant execute on function public.get_public_booking(text, timestamptz, timestamptz) to anon, authenticated;

create or replace function public.create_booking(
  p_slug text, p_customer_name text, p_customer_phone text, p_service_ids jsonb,
  p_staff_id text, p_starts_at timestamptz, p_note text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_store public.online_stores;
  v_name text := left(trim(coalesce(p_customer_name, '')), 80);
  v_names text;
  v_minutes integer;
  v_id text := gen_random_uuid()::text;
begin
  select * into v_store from public.online_stores where slug = lower(trim(coalesce(p_slug, '')));
  if not found or not v_store.enabled
     or not coalesce((public.business_pro_until(v_store.business_id) ->> 'services')::boolean, false) then
    raise exception 'store_not_found';
  end if;
  if v_name = '' then raise exception 'name_required'; end if;
  if coalesce(trim(p_customer_phone), '') = '' then raise exception 'phone_required'; end if;
  if p_starts_at < now() then raise exception 'past_time'; end if;
  if jsonb_typeof(p_service_ids) <> 'array' or jsonb_array_length(p_service_ids) = 0 then
    raise exception 'services_required';
  end if;
  select string_agg(s.name, ', ' order by s.name), sum(coalesce(s.duration_min, 30))
    into v_names, v_minutes
  from public.services s
  where s.business_id = v_store.business_id and s.is_active
    and s.id in (select jsonb_array_elements_text(p_service_ids));
  if v_names is null then raise exception 'services_required'; end if;
  if p_staff_id is not null and not exists (
    select 1 from public.staff where id = p_staff_id and business_id = v_store.business_id and is_active) then
    raise exception 'staff_not_found';
  end if;
  -- Dos personas no pueden pedir la misma hora con el mismo empleado
  perform pg_advisory_xact_lock(hashtext('booking:' || v_store.business_id));
  if p_staff_id is not null and exists (
    select 1 from public.appointments a
    where a.business_id = v_store.business_id and a.staff_id = p_staff_id and a.status in ('PENDIENTE', 'CONFIRMADA')
      and a.starts_at < p_starts_at + make_interval(mins => v_minutes)
      and a.starts_at + make_interval(mins => a.duration_min) > p_starts_at) then
    raise exception 'slot_taken';
  end if;
  insert into public.appointments (id, business_id, customer_name, customer_phone, service_ids, service_names,
    staff_id, starts_at, duration_min, status, source, notes)
  values (v_id, v_store.business_id, v_name, left(trim(p_customer_phone), 30), p_service_ids::text, v_names,
    p_staff_id, p_starts_at, least(greatest(v_minutes, 5), 600), 'PENDIENTE', 'TIENDA',
    nullif(left(trim(coalesce(p_note, '')), 300), ''));
  return jsonb_build_object('id', v_id, 'services', v_names, 'minutes', v_minutes);
end;
$$;

revoke all on function public.create_booking(text, text, text, jsonb, text, timestamptz, text) from public;
grant execute on function public.create_booking(text, text, text, jsonb, text, timestamptz, text) to anon, authenticated;
