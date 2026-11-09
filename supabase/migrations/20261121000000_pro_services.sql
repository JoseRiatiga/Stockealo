-- Stockealo 0.12.0: plan Pro Servicios y precios ocultos
--
-- • Nuevo tipo de suscripción 'services' (Pro Servicios): todo Pro + el módulo
--   Servicios. Es por negocio (como Pro Negocio) y solo mensual.
-- • business_pro_until devuelve también 'services' (si el negocio tiene el módulo).
-- • Canje de códigos, «Dar Pro» del panel, creación de códigos y pagos aceptan el tipo nuevo.
-- • Ajuste 'show_pricing' (apagado): la app no muestra precios ni compra hasta
--   encenderlo desde el panel.
-- • Fila del plan mensual de Pro Servicios en COP, apagada y sin precio definido.
-- No borra datos.

-- ---------------------------------------------------------------------------
-- Tipos permitidos
-- ---------------------------------------------------------------------------
alter table public.pro_plans drop constraint if exists pro_plans_kind_check;
alter table public.pro_plans add constraint pro_plans_kind_check
  check (kind in ('business', 'global', 'services'));

alter table public.pro_codes drop constraint if exists pro_codes_kind_check;
alter table public.pro_codes add constraint pro_codes_kind_check
  check (kind in ('business', 'global', 'services'));

alter table public.pro_payments drop constraint if exists pro_payments_kind_check;
alter table public.pro_payments add constraint pro_payments_kind_check
  check (kind in ('business', 'global', 'services'));

alter table public.subscriptions drop constraint if exists subscriptions_kind_check;
alter table public.subscriptions add constraint subscriptions_kind_check
  check (kind in ('business', 'global', 'services'));

-- Pro Negocio y Pro Servicios van atados a un negocio; Pro Global, a la cuenta
alter table public.subscriptions drop constraint if exists subscriptions_check;
alter table public.subscriptions add constraint subscriptions_check
  check ((kind in ('business', 'services')) = (business_id is not null));

-- ---------------------------------------------------------------------------
-- ¿El negocio tiene Pro? Ahora también dice si tiene el módulo Servicios.
--   kind: 'services' si tiene Pro Servicios; si no, 'global' o 'business'.
--   services: true si tiene Pro Servicios vigente.
-- ---------------------------------------------------------------------------
create or replace function public.business_pro_until(p_business_id text)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  with active as (
    select s.kind, s.ends_at
    from public.subscriptions s
    where (s.ends_at is null or s.ends_at > now())
      and s.starts_at <= now()
      and (
        s.business_id = p_business_id
        or (
          s.kind = 'global'
          and exists (
            select 1 from public.business_members m
            where m.business_id = p_business_id
              and m.role = 'OWNER'
              and lower(m.user_email) = lower(s.owner_email)
          )
        )
      )
  )
  select case
    when not exists (select 1 from active) then jsonb_build_object('active', false, 'services', false)
    else jsonb_build_object(
      'active', true,
      -- Si hay alguna permanente, no vence; si no, la que vence más tarde
      'ends_at', (select case when bool_or(ends_at is null) then null else max(ends_at) end from active),
      'kind', (select case
                        when bool_or(kind = 'services') then 'services'
                        when bool_or(kind = 'global') then 'global'
                        else 'business' end
                 from active),
      'services', (select bool_or(kind = 'services') from active),
      'services_ends_at', (select case when bool_or(ends_at is null) then null else max(ends_at) end
                             from active where kind = 'services')
    )
  end;
$$;

revoke all on function public.business_pro_until(text) from public, anon, authenticated;
grant execute on function public.business_pro_until(text) to service_role;

-- ---------------------------------------------------------------------------
-- Canjear un código. Pro Negocio y Pro Servicios se aplican al negocio indicado
-- (solo su dueño); Pro Global, a la cuenta. Si ya tenía ese plan, los días se suman al final.
-- ---------------------------------------------------------------------------
create or replace function public.redeem_pro_code(p_code text, p_business_id text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_email text := lower(auth.email());
  v_code public.pro_codes%rowtype;
  v_from timestamptz;
  v_end timestamptz;
  v_clean text := upper(regexp_replace(coalesce(p_code, ''), '\s', '', 'g'));
begin
  if v_email is null then
    raise exception 'not_authenticated';
  end if;

  select * into v_code from public.pro_codes where code = v_clean for update;
  if not found then
    raise exception 'code_not_found';
  end if;
  if v_code.expires_at is not null and v_code.expires_at < now() then
    raise exception 'code_expired';
  end if;
  if v_code.uses >= v_code.max_uses then
    raise exception 'code_used';
  end if;
  if exists (select 1 from public.code_redemptions where code = v_clean and user_email = v_email) then
    raise exception 'code_already_redeemed';
  end if;

  if v_code.kind in ('business', 'services') then
    if p_business_id is null or public.my_business_role(p_business_id) is distinct from 'OWNER' then
      raise exception 'owner_only';
    end if;
    select max(ends_at) into v_from from public.subscriptions
      where business_id = p_business_id and kind = v_code.kind and ends_at > now();
  else
    select max(ends_at) into v_from from public.subscriptions
      where kind = 'global' and lower(owner_email) = v_email and ends_at > now();
  end if;

  v_end := case when v_code.days is null then null
                else greatest(coalesce(v_from, now()), now()) + make_interval(days => v_code.days) end;

  insert into public.subscriptions (kind, business_id, owner_email, source, ends_at)
  values (
    v_code.kind,
    case when v_code.kind in ('business', 'services') then p_business_id else null end,
    v_email,
    'code',
    v_end
  );

  update public.pro_codes set uses = uses + 1 where code = v_clean;
  insert into public.code_redemptions (code, user_email, business_id) values (v_clean, v_email, p_business_id);

  return jsonb_build_object('kind', v_code.kind, 'ends_at', v_end, 'days', v_code.days);
end;
$$;

revoke all on function public.redeem_pro_code(text, text) from public, anon;
grant execute on function public.redeem_pro_code(text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- Panel: «Dar Pro» a un negocio eligiendo el plan (Pro Negocio o Pro Servicios)
-- La versión anterior (sin plan) se reemplaza; p_kind por defecto es 'business'.
-- ---------------------------------------------------------------------------
drop function if exists public.admin_grant_pro(text, integer);

create or replace function public.admin_grant_pro(p_business_id text, p_days integer, p_kind text default 'business')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_owner text;
  v_from timestamptz;
begin
  perform public.admin_require('OWNER', 'grant_pro',
    jsonb_build_object('business_id', p_business_id, 'days', p_days, 'kind', p_kind));
  if p_kind not in ('business', 'services') then
    raise exception 'invalid_kind';
  end if;
  if p_days is not null and (p_days < 1 or p_days > 3650) then
    raise exception 'invalid_days';
  end if;
  if not exists (select 1 from public.businesses where id = p_business_id and coalesce(is_deleted, 0) = 0) then
    raise exception 'business_not_found';
  end if;
  select m.user_email into v_owner from public.business_members m
   where m.business_id = p_business_id and m.role = 'OWNER' limit 1;
  -- Se suma después de lo que ya tenga de ese mismo plan
  select greatest(now(), coalesce(max(s.ends_at), now())) into v_from
    from public.subscriptions s
   where s.business_id = p_business_id and s.kind = p_kind and s.ends_at > now();
  insert into public.subscriptions (kind, business_id, owner_email, source, starts_at, ends_at)
  values (p_kind, p_business_id, coalesce(v_owner, auth.email()), 'manual', now(),
          case when p_days is null then null else v_from + make_interval(days => p_days) end);
  return public.business_pro_until(p_business_id);
end;
$$;

revoke all on function public.admin_grant_pro(text, integer, text) from public, anon;
grant execute on function public.admin_grant_pro(text, integer, text) to authenticated;

-- ---------------------------------------------------------------------------
-- Panel: crear códigos, también de Pro Servicios
-- ---------------------------------------------------------------------------
create or replace function public.admin_create_pro_codes(p_kind text, p_days integer, p_count integer default 1,
    p_note text default null, p_max_uses integer default 1, p_valid_days integer default null)
returns setof text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_code text;
begin
  perform public.admin_require('OWNER', 'create_codes',
    jsonb_build_object('kind', p_kind, 'days', p_days, 'count', p_count, 'max_uses', p_max_uses, 'note', p_note));
  if p_kind not in ('business', 'global', 'services') then raise exception 'invalid_kind'; end if;
  if p_count is null or p_count < 1 or p_count > 50 then raise exception 'invalid_count'; end if;
  if p_days is not null and (p_days < 1 or p_days > 3650) then raise exception 'invalid_days'; end if;
  if p_max_uses is null or p_max_uses < 1 or p_max_uses > 1000 then raise exception 'invalid_max_uses'; end if;
  if p_valid_days is not null and (p_valid_days < 1 or p_valid_days > 3650) then raise exception 'invalid_valid_days'; end if;
  for v_code in
    select public.create_pro_codes(p_kind, p_days, p_count, nullif(trim(p_note), ''), p_max_uses)
  loop
    if p_valid_days is not null then
      update public.pro_codes set expires_at = now() + make_interval(days => p_valid_days) where code = v_code;
    end if;
    return next v_code;
  end loop;
end;
$$;

-- ---------------------------------------------------------------------------
-- Pagos aprobados: Pro Servicios también va atado al negocio
-- ---------------------------------------------------------------------------
create or replace function public.pro_apply_payment(
  p_reference text, p_transaction_id text, p_status text, p_method text, p_amount_in_cents bigint, p_currency text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_pay public.pro_payments;
  v_from timestamptz;
  v_end timestamptz;
  v_sub uuid;
begin
  select * into v_pay from public.pro_payments where reference = p_reference for update;
  if not found then
    raise exception 'payment_not_found';
  end if;
  if v_pay.status = 'APPROVED' then
    return jsonb_build_object('status', v_pay.status, 'subscription_id', v_pay.subscription_id);
  end if;
  if p_status = 'APPROVED' and (p_amount_in_cents <> v_pay.amount_in_cents or p_currency <> v_pay.currency) then
    update public.pro_payments
       set status = 'ERROR', wompi_transaction_id = p_transaction_id, payment_method = p_method, updated_at = now()
     where reference = p_reference;
    return jsonb_build_object('status', 'ERROR', 'reason', 'amount_mismatch');
  end if;
  if p_status = 'APPROVED' then
    if v_pay.kind = 'business' then
      v_from := greatest(now(), coalesce((public.business_pro_until(v_pay.business_id) ->> 'ends_at')::timestamptz, now()));
    elsif v_pay.kind = 'services' then
      v_from := greatest(now(), coalesce((
        select max(s.ends_at) from public.subscriptions s
         where s.kind = 'services' and s.business_id = v_pay.business_id and s.ends_at > now()), now()));
    else
      v_from := greatest(now(), coalesce((
        select max(s.ends_at) from public.subscriptions s
         where s.kind = 'global' and lower(s.owner_email) = lower(v_pay.user_email) and s.ends_at > now()), now()));
    end if;
    v_end := case v_pay.period
      when 'week' then v_from + interval '7 days'
      when 'month' then v_from + interval '30 days'
      when 'year' then v_from + interval '365 days'
      else null
    end;
    insert into public.subscriptions (kind, business_id, owner_email, source, starts_at, ends_at)
    values (v_pay.kind, case when v_pay.kind in ('business', 'services') then v_pay.business_id end,
            v_pay.user_email, 'gateway', now(), v_end)
    returning id into v_sub;
  end if;
  update public.pro_payments
     set status = case when p_status in ('APPROVED', 'DECLINED', 'VOIDED', 'ERROR') then p_status else 'PENDING' end,
         wompi_transaction_id = p_transaction_id,
         payment_method = p_method,
         subscription_id = coalesce(v_sub, subscription_id),
         updated_at = now()
   where reference = p_reference;
  return jsonb_build_object('status', p_status, 'subscription_id', v_sub);
end;
$$;
revoke all on function public.pro_apply_payment(text, text, text, text, bigint, text) from public, anon, authenticated;
grant execute on function public.pro_apply_payment(text, text, text, text, bigint, text) to service_role;

-- ---------------------------------------------------------------------------
-- Mostrar precios y compra en la app: apagado hasta que el dueño lo encienda
-- ---------------------------------------------------------------------------
insert into public.pro_settings (key, value) values ('show_pricing', 'off')
on conflict (key) do nothing;

create or replace function public.admin_set_setting(p_key text, p_value text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- No se registra el valor: puede ser una llave
  perform public.admin_require('OWNER', 'set_setting', jsonb_build_object('key', p_key));
  if p_key not in ('nequi_number', 'nequi_name', 'whatsapp', 'founder_slots', 'founder_until', 'legal_notice',
                   'wompi_public_key', 'show_pricing') then
    raise exception 'invalid_setting';
  end if;
  if p_key = 'show_pricing' and coalesce(p_value, '') not in ('on', 'off') then
    raise exception 'invalid_setting';
  end if;
  insert into public.pro_settings (key, value) values (p_key, nullif(trim(coalesce(p_value, '')), ''))
  on conflict (key) do update set value = excluded.value;
end;
$$;

-- ---------------------------------------------------------------------------
-- Plan mensual de Pro Servicios (COP). Apagado: el precio se define después
-- de negociar con el primer cliente y se enciende desde el panel.
-- ---------------------------------------------------------------------------
insert into public.pro_plans (id, kind, period, currency, price, regular_price, label, sort, active)
values ('services_month_cop', 'services', 'month', 'COP', 0, null, null, 7, false)
on conflict (id) do nothing;
