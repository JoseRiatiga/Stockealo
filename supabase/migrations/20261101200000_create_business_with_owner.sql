-- Crear un negocio con su dueño en un solo paso.
--
-- Con RLS, un negocio nuevo no se puede insertar con upsert (INSERT ... ON
-- CONFLICT): Postgres también exige que la fila nueva cumpla la política de
-- lectura, y nadie puede "ver" un negocio que todavía no tiene miembros. Esta
-- función crea el negocio y registra a quien la llama como OWNER a la vez.
--
-- Es idempotente (se puede reintentar desde la cola de sincronización) y solo
-- asigna dueño si el negocio aún no tiene miembros, así que no permite tomar
-- negocios ajenos.

create or replace function public.create_business_with_owner(
  p_id text,
  p_name text,
  p_type text default null,
  p_currency text default null,
  p_created_at timestamptz default null,
  p_member_id text default null,
  p_user_id text default null,
  p_user_name text default null
)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_email text := lower(auth.email());
begin
  if auth.uid() is null or v_email is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  insert into public.businesses (id, name, type, currency, created_at)
  values (
    p_id,
    p_name,
    coalesce(nullif(p_type, ''), 'Comercio General'),
    coalesce(nullif(p_currency, ''), 'COP'),
    coalesce(p_created_at, now())
  )
  on conflict (id) do nothing;

  if not exists (select 1 from public.business_members m where m.business_id = p_id) then
    insert into public.business_members (id, business_id, user_id, user_email, user_name, role, created_at)
    values (
      coalesce(nullif(p_member_id, ''), gen_random_uuid()::text),
      p_id,
      coalesce(nullif(p_user_id, ''), auth.uid()::text),
      v_email,
      coalesce(nullif(trim(p_user_name), ''), split_part(v_email, '@', 1)),
      'OWNER',
      now()
    )
    on conflict (id) do nothing;
  end if;
end;
$$;

revoke all on function public.create_business_with_owner(text, text, text, text, timestamptz, text, text, text) from public, anon;
grant execute on function public.create_business_with_owner(text, text, text, text, timestamptz, text, text, text) to authenticated;
