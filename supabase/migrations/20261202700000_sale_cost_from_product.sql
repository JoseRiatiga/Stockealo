-- 0.15.0, «Ver costos» (opción 1 del dueño, 14 nov 2026): el costo se oculta en las
-- pantallas (como antes) y el aviso de pérdida sigue funcionando sin internet. Para que la
-- nube no dependa del costo que manda el celular, ella misma pone el costo de cada venta a
-- partir del producto: el mayor entre el que llega y el actual.

create or replace function public._check_sale()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_gross numeric;
  v_disc numeric;
  v_limit numeric;
  v_needs boolean := false;
  v_cost numeric;
begin
  if auth.uid() is null then
    return new;
  end if;

  if tg_op = 'INSERT' then
    -- Un reintento de una venta que ya está: lo revisa la parte de cambios
    if exists (select 1 from public.sales s where s.id = new.id) then
      return new;
    end if;
    -- El costo lo pone la nube a partir del producto (el mayor entre el del celular y el
    -- actual): nadie hace pasar una venta con pérdida mandando un costo más bajo
    if new.product_id is not null then
      select p.cost_price into v_cost from public.products p where p.id = new.product_id and p.business_id = new.business_id;
      if v_cost is not null then
        new.unit_cost := greatest(coalesce(new.unit_cost, 0), v_cost);
      end if;
    end if;
    if new.service_id is null then
      if not public.has_permission(new.business_id, 'sell') then
        raise exception 'perm_denied:sell';
      end if;
    elsif not public.has_permission(new.business_id, 'servicesCharge') then
      raise exception 'perm_denied:servicesCharge';
    end if;
    -- Descuento: precio por cantidad menos promociones, frente a lo cobrado
    v_gross := coalesce(new.unit_price, 0) * coalesce(new.quantity, 0) - coalesce(new.promotion_discount, 0);
    v_disc := v_gross - coalesce(new.total_amount, 0);
    if new.service_id is null and v_disc > 0.5 then
      if not public.has_permission(new.business_id, 'discount') then
        v_needs := true;
      else
        v_limit := public.my_limit(new.business_id, 'discountPct');
        if v_limit is not null and v_gross > 0 and v_disc * 100 / v_gross > v_limit + 0.01 then
          v_needs := true;
        end if;
      end if;
    end if;
    if new.service_id is null
       and coalesce(new.unit_cost, 0) * coalesce(new.quantity, 0) - coalesce(new.total_amount, 0) > 0.5
       and not public.has_permission(new.business_id, 'sellBelowCost') then
      v_needs := true;
    end if;
    if upper(coalesce(new.payment_method, '')) = 'FIADO' and not public.has_permission(new.business_id, 'credit') then
      v_needs := true;
    end if;
    if v_needs and (
      new.auth_request_id is null
      or not public._auth_ok(new.auth_request_id, new.business_id)
      -- La misma autorización sirve para las líneas de una sola venta, no para otra
      or exists (
        select 1 from public.sales s
        where s.auth_request_id = new.auth_request_id and s.id <> new.id and s.sale_date <> new.sale_date
      )
    ) then
      raise exception 'needs_authorization';
    end if;
    return new;
  end if;

  -- UPDATE: anular necesita «Anular venta»; una venta vieja, además, su autorización
  if old.voided_at is null and new.voided_at is not null then
    if not public.has_permission(new.business_id, 'voidSale') then
      raise exception 'perm_denied:voidSale';
    end if;
    v_limit := public.my_limit(new.business_id, 'voidHours');
    if v_limit is not null and old.sale_date < now() - make_interval(secs => (v_limit * 3600)::double precision) and (
      new.void_auth_request_id is null
      or not public._auth_ok(new.void_auth_request_id, new.business_id)
      or exists (
        select 1 from public.sales s
        where s.void_auth_request_id = new.void_auth_request_id and s.id <> new.id and s.sale_date <> new.sale_date
      )
    ) then
      raise exception 'needs_authorization';
    end if;
  end if;
  -- Lo cobrado no se cambia después (solo se anula)
  if (new.total_amount, new.unit_price, new.quantity, new.payment_method)
       is distinct from (old.total_amount, old.unit_price, old.quantity, old.payment_method)
     and not public.has_permission(new.business_id, 'voidSale') then
    raise exception 'perm_denied:sale_locked';
  end if;
  return new;
end;
$$;

