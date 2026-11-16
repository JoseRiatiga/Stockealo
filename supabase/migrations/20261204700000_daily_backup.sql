-- 0.16.0, fase 5: copia diaria propia y verificada (decisión del dueño: sin pasar al
-- plan de pago de Supabase).
--
-- • Almacenamiento «backups» PRIVADO: sin políticas, solo lo lee la llave de servicio.
-- • backup_runs: cada copia (día, tablas y filas, si quedó completa, el problema).
-- • backup_tables / backup_dump / backup_key_ok: los usa SOLO la función daily-backup
--   con la llave de servicio (nadie de la app ni de la tienda las puede llamar).
-- • admin_backup_status: el panel ve las últimas copias (cualquier administrador).
-- • pg_cron llama a daily-backup cada día a las 8:00 UTC (3:00 a. m. de Colombia) con
--   una clave que vive en Vault; la función le pregunta a la base si es la correcta.

insert into storage.buckets (id, name, public)
values ('backups', 'backups', false)
on conflict (id) do update set public = false;

create table if not exists public.backup_runs (
  id bigint generated always as identity primary key,
  day date not null,
  started_at timestamptz not null default now(),
  finished_at timestamptz,
  ok boolean not null default false,
  by_who text not null default 'cron' check (by_who in ('cron', 'panel')),
  tables jsonb not null default '{}'::jsonb,
  bytes bigint not null default 0,
  error text check (error is null or char_length(error) <= 2000)
);
create index if not exists backup_runs_started_idx on public.backup_runs (started_at desc);
alter table public.backup_runs enable row level security;

-- Las tablas que se copian: todas las de public menos los registros de errores y de copias
create or replace function public.backup_tables()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(t.table_name order by t.table_name), '[]'::jsonb)
  from information_schema.tables t
  where t.table_schema = 'public' and t.table_type = 'BASE TABLE'
    and t.table_name not in ('app_errors', 'backup_runs');
$$;

create or replace function public.backup_dump(p_table text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_rows jsonb;
  v_count bigint;
begin
  if not exists (
    select 1 from information_schema.tables t
    where t.table_schema = 'public' and t.table_type = 'BASE TABLE' and t.table_name = p_table
      and t.table_name not in ('app_errors', 'backup_runs')
  ) then
    raise exception 'unknown_table';
  end if;
  execute format('select coalesce(jsonb_agg(to_jsonb(x)), ''[]''::jsonb), count(*) from public.%I x', p_table) into v_rows, v_count;
  return jsonb_build_object('rows', v_rows, 'count', v_count);
end;
$$;

create or replace function public.backup_key_ok(p_key text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(p_key, '') <> '' and exists (
    select 1 from vault.decrypted_secrets s where s.name = 'daily_backup_key' and s.decrypted_secret = p_key
  );
$$;

revoke all on function public.backup_tables() from public, anon, authenticated;
revoke all on function public.backup_dump(text) from public, anon, authenticated;
revoke all on function public.backup_key_ok(text) from public, anon, authenticated;
grant execute on function public.backup_tables() to service_role;
grant execute on function public.backup_dump(text) to service_role;
grant execute on function public.backup_key_ok(text) to service_role;

create or replace function public.admin_backup_status()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform public.admin_require('VIEWER');
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'day', r.day, 'started_at', r.started_at, 'finished_at', r.finished_at, 'ok', r.ok, 'by', r.by_who,
      'tables', (select count(*) from jsonb_object_keys(r.tables)),
      'rows', (select coalesce(sum(v::bigint), 0) from jsonb_each_text(r.tables) e(k, v)),
      'bytes', r.bytes, 'error', r.error
    ) order by r.started_at desc)
    from (select * from public.backup_runs order by started_at desc limit 14) r
  ), '[]'::jsonb);
end;
$$;
revoke all on function public.admin_backup_status() from public, anon;
grant execute on function public.admin_backup_status() to authenticated;

-- La clave de la tarea programada, en Vault (se crea una sola vez, al azar)
do $$
begin
  if not exists (select 1 from vault.secrets where name = 'daily_backup_key') then
    perform vault.create_secret(replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', ''), 'daily_backup_key',
      'Clave de la copia diaria (pg_cron → daily-backup)');
  end if;
end $$;

-- La tarea programada
create extension if not exists pg_net;
create extension if not exists pg_cron;

do $$
begin
  if exists (select 1 from cron.job where jobname = 'stockealo-daily-backup') then
    perform cron.unschedule('stockealo-daily-backup');
  end if;
  perform cron.schedule(
    'stockealo-daily-backup',
    '0 8 * * *',
    $cron$
      select net.http_post(
        url := 'https://evdwwmkafwjyfawsufjb.supabase.co/functions/v1/daily-backup',
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'x-backup-key', (select s.decrypted_secret from vault.decrypted_secrets s where s.name = 'daily_backup_key')
        ),
        body := '{}'::jsonb,
        timeout_milliseconds := 60000
      );
    $cron$
  );
end $$;
