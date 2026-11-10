-- Stockealo 0.12.0: el aviso de mantenimiento puede salir con días de anticipación
--
--   • notice_hours pasa de un máximo de 72 h a 720 h (30 días), para avisar
--     «2 días antes», «1 semana antes» o «desde ya».
--   • El mensaje del mantenimiento queda limitado a 300 letras.
-- No cambia el mantenimiento programado que haya ahora.

alter table public.maintenance_window drop constraint if exists maintenance_window_notice_hours_check;
alter table public.maintenance_window add constraint maintenance_window_notice_hours_check
  check (notice_hours >= 0 and notice_hours <= 720);

create or replace function public.admin_set_maintenance(
  p_level integer, p_scopes text[], p_message text, p_starts_at timestamptz, p_ends_at timestamptz,
  p_notice_hours integer default 2, p_confirm text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_starts timestamptz := coalesce(p_starts_at, now());
begin
  perform public.admin_require('OWNER', 'set_maintenance',
    jsonb_build_object('level', p_level, 'scopes', p_scopes, 'starts_at', v_starts, 'ends_at', p_ends_at));
  if p_level is null or p_level not between 1 and 3 then raise exception 'invalid_level'; end if;
  if p_scopes is null or cardinality(p_scopes) = 0
     or exists (select 1 from unnest(p_scopes) s where s not in ('stores', 'app', 'payments')) then
    raise exception 'invalid_scopes';
  end if;
  if p_ends_at is null or p_ends_at <= v_starts or p_ends_at <= now() then raise exception 'invalid_end'; end if;
  if p_ends_at - v_starts > interval '48 hours' then raise exception 'too_long'; end if;
  if p_level = 3 and upper(trim(coalesce(p_confirm, ''))) <> 'MANTENIMIENTO' then raise exception 'confirm_required'; end if;
  if char_length(coalesce(p_message, '')) > 300 then raise exception 'message_too_long'; end if;
  update public.maintenance_window
     set level = p_level, scopes = p_scopes, message = nullif(trim(coalesce(p_message, '')), ''),
         starts_at = v_starts, ends_at = p_ends_at,
         notice_hours = least(greatest(coalesce(p_notice_hours, 2), 0), 720),
         updated_by = lower(auth.jwt() ->> 'email'), updated_at = now()
   where id = 1;
  return public.get_maintenance();
end;
$$;
revoke all on function public.admin_set_maintenance(integer, text[], text, timestamptz, timestamptz, integer, text) from public, anon;
grant execute on function public.admin_set_maintenance(integer, text[], text, timestamptz, timestamptz, integer, text) to authenticated;
