-- 0.16.0, fase 5: reporte automático de errores para el panel de administración.
--
-- • app_errors: cada error que manda la app, la tienda o el panel. Sin datos de
--   clientes: el mensaje y el rastro llegan con los correos y teléfonos tapados.
--   Nadie la lee directo (sin políticas): solo por las funciones de abajo.
-- • report_app_error: lo llama la app (también sin cuenta, por ejemplo la tienda).
--   Recorta los textos y, si un mismo error llega más de 200 veces en una hora, deja de
--   guardarlo para que no se llene. Borra los de más de 90 días.
-- • admin_error_groups: los errores agrupados para el panel (cualquier administrador).

create table if not exists public.app_errors (
  id bigint generated always as identity primary key,
  created_at timestamptz not null default now(),
  app text not null check (app in ('app', 'admin', 'tienda')),
  version text not null check (char_length(version) <= 30),
  platform text not null check (char_length(platform) <= 20),
  kind text not null check (char_length(kind) <= 20),
  fingerprint text not null check (char_length(fingerprint) <= 40),
  message text not null check (char_length(message) <= 500),
  stack text check (stack is null or char_length(stack) <= 4000)
);

create index if not exists app_errors_fingerprint_idx on public.app_errors (fingerprint, created_at desc);
create index if not exists app_errors_created_idx on public.app_errors (created_at desc);

alter table public.app_errors enable row level security;

create or replace function public.report_app_error(
  p_app text, p_version text, p_platform text, p_kind text, p_fingerprint text, p_message text, p_stack text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_app not in ('app', 'admin', 'tienda') or coalesce(trim(p_message), '') = '' or coalesce(trim(p_fingerprint), '') = '' then
    return;
  end if;
  if (select count(*) from public.app_errors e
      where e.fingerprint = left(p_fingerprint, 40) and e.created_at > now() - interval '1 hour') >= 200 then
    return;
  end if;
  insert into public.app_errors (app, version, platform, kind, fingerprint, message, stack)
  values (p_app, left(coalesce(p_version, '?'), 30), left(coalesce(p_platform, '?'), 20), left(coalesce(p_kind, '?'), 20),
          left(p_fingerprint, 40), left(p_message, 500), left(p_stack, 4000));
  -- Limpieza de vez en cuando: los de más de 90 días sobran
  if random() < 0.02 then
    delete from public.app_errors where created_at < now() - interval '90 days';
  end if;
end;
$$;

revoke all on function public.report_app_error(text, text, text, text, text, text, text) from public;
grant execute on function public.report_app_error(text, text, text, text, text, text, text) to anon, authenticated;

create or replace function public.admin_error_groups(p_days integer default 7)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform public.admin_require('VIEWER');
  return coalesce((
    select jsonb_agg(g order by (g ->> 'count')::int desc, g ->> 'last_at' desc)
    from (
      select jsonb_build_object(
        'fingerprint', e.fingerprint,
        'message', (array_agg(e.message order by e.created_at desc))[1],
        'count', count(*),
        'last_at', max(e.created_at),
        'versions', (select jsonb_agg(distinct x.version) from public.app_errors x where x.fingerprint = e.fingerprint and x.created_at > now() - make_interval(days => greatest(p_days, 1))),
        'platforms', (select jsonb_agg(distinct x.platform) from public.app_errors x where x.fingerprint = e.fingerprint and x.created_at > now() - make_interval(days => greatest(p_days, 1))),
        'apps', (select jsonb_agg(distinct x.app) from public.app_errors x where x.fingerprint = e.fingerprint and x.created_at > now() - make_interval(days => greatest(p_days, 1))),
        'stack', (array_agg(e.stack order by e.created_at desc))[1]
      ) g
      from public.app_errors e
      where e.created_at > now() - make_interval(days => greatest(least(p_days, 90), 1))
      group by e.fingerprint
      order by count(*) desc
      limit 100
    ) t
  ), '[]'::jsonb);
end;
$$;

revoke all on function public.admin_error_groups(integer) from public, anon;
grant execute on function public.admin_error_groups(integer) to authenticated;
