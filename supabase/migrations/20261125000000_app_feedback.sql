-- Stockealo 0.12.0: sugerencias y fallos
--
--   • app_feedback: lo que envían los usuarios desde Ajustes › Ayuda (fallo, idea o
--     pregunta), con la versión, el equipo, el negocio y el rol; el estado y la
--     respuesta del equipo de Stockealo.
--   • submit_feedback: única forma de enviar (máximo 10 al día por cuenta).
--   • Cada persona ve solo lo suyo; el panel lista y responde con funciones de admin
--     que quedan en el registro de acciones.
-- No modifica tablas existentes.

create table if not exists public.app_feedback (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid(),
  user_email text not null,
  business_id text references public.businesses (id) on delete set null,
  business_name text,
  user_role text,
  kind text not null check (kind in ('FALLO', 'IDEA', 'PREGUNTA')),
  area text,
  message text not null check (char_length(message) between 3 and 2000),
  contact_phone text check (contact_phone is null or char_length(contact_phone) <= 30),
  app_version text,
  platform text,
  status text not null default 'NUEVO' check (status in ('NUEVO', 'REVISION', 'RESUELTO', 'DESCARTADO')),
  admin_reply text check (admin_reply is null or char_length(admin_reply) <= 2000),
  replied_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists idx_app_feedback_user on public.app_feedback (user_id, created_at desc);
create index if not exists idx_app_feedback_status on public.app_feedback (status, created_at desc);

alter table public.app_feedback enable row level security;
revoke all on public.app_feedback from anon, authenticated;
grant select on public.app_feedback to authenticated;

-- Cada persona lee solo lo suyo (para «Lo que he enviado»)
drop policy if exists app_feedback_select_own on public.app_feedback;
create policy app_feedback_select_own on public.app_feedback for select to authenticated
  using (user_id = auth.uid());

-- Enviar: solo por aquí, con límite diario
create or replace function public.submit_feedback(
  p_kind text,
  p_message text,
  p_area text default null,
  p_business_id text default null,
  p_contact_phone text default null,
  p_app_version text default null,
  p_platform text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_email text := lower(auth.email());
  v_role text;
  v_name text;
  v_id uuid;
  v_clean text := trim(coalesce(p_message, ''));
begin
  if v_uid is null or v_email is null then
    raise exception 'not_authenticated';
  end if;
  if p_kind not in ('FALLO', 'IDEA', 'PREGUNTA') then
    raise exception 'invalid_kind';
  end if;
  if char_length(v_clean) < 3 then
    raise exception 'message_too_short';
  end if;
  if char_length(v_clean) > 2000 then
    raise exception 'message_too_long';
  end if;
  if (select count(*) from public.app_feedback
       where user_id = v_uid and created_at > now() - interval '1 day') >= 10 then
    raise exception 'too_many_feedback';
  end if;
  if p_business_id is not null then
    v_role := public.my_business_role(p_business_id);
    if v_role is not null then
      select name into v_name from public.businesses where id = p_business_id;
    end if;
  end if;
  insert into public.app_feedback (user_id, user_email, business_id, business_name, user_role, kind, area, message,
                                   contact_phone, app_version, platform)
  values (v_uid, v_email, case when v_role is null then null else p_business_id end, v_name, v_role, p_kind,
          left(nullif(trim(coalesce(p_area, '')), ''), 40), v_clean,
          left(nullif(trim(coalesce(p_contact_phone, '')), ''), 30),
          left(nullif(trim(coalesce(p_app_version, '')), ''), 30), left(nullif(trim(coalesce(p_platform, '')), ''), 20))
  returning id into v_id;
  return v_id;
end;
$$;
revoke all on function public.submit_feedback(text, text, text, text, text, text, text) from public, anon;
grant execute on function public.submit_feedback(text, text, text, text, text, text, text) to authenticated;

-- Panel: lista con filtros
create or replace function public.admin_list_feedback(p_status text default null, p_kind text default null, p_limit integer default 100)
returns setof public.app_feedback
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform public.admin_require('SUPPORT');
  return query
    select * from public.app_feedback f
     where (p_status is null or f.status = p_status)
       and (p_kind is null or f.kind = p_kind)
     order by (f.status = 'NUEVO') desc, f.created_at desc
     limit least(greatest(coalesce(p_limit, 100), 1), 500);
end;
$$;
revoke all on function public.admin_list_feedback(text, text, integer) from public, anon;
grant execute on function public.admin_list_feedback(text, text, integer) to authenticated;

-- Panel: cambiar estado y responder (la respuesta la ve quien escribió)
create or replace function public.admin_update_feedback(p_id uuid, p_status text, p_reply text default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_reply text := nullif(trim(coalesce(p_reply, '')), '');
begin
  perform public.admin_require('SUPPORT', 'feedback_update', jsonb_build_object('id', p_id, 'status', p_status));
  if p_status not in ('NUEVO', 'REVISION', 'RESUELTO', 'DESCARTADO') then
    raise exception 'invalid_status';
  end if;
  if v_reply is not null and char_length(v_reply) > 2000 then
    raise exception 'message_too_long';
  end if;
  update public.app_feedback
     set status = p_status,
         admin_reply = coalesce(v_reply, admin_reply),
         replied_at = case when v_reply is not null then now() else replied_at end,
         updated_at = now()
   where id = p_id;
  if not found then
    raise exception 'feedback_not_found';
  end if;
end;
$$;
revoke all on function public.admin_update_feedback(uuid, text, text) from public, anon;
grant execute on function public.admin_update_feedback(uuid, text, text) to authenticated;
