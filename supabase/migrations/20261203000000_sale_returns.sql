-- 0.15.0, punto 16: devolución parcial. Se guarda como una venta en negativo con el mismo
-- medio de pago, ligada a la venta original (return_of), así la caja, los reportes y los
-- totales por medio se ajustan solos. La nube revisa que tenga el permiso «Devolver», que sea
-- de una venta del mismo negocio sin anular y que no pase de lo vendido. Devolver al
-- inventario también suma stock con «Devolver».

alter table public.sales add column if not exists return_of text;

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
    -- Devolución (cantidad en negativo): necesita «Devolver», tiene que ser de una venta
    -- del mismo negocio sin anular y no puede pasar de lo que se vendió
    if coalesce(new.quantity, 0) < 0 then
      if not public.has_permission(new.business_id, 'refund') then
        raise exception 'perm_denied:refund';
      end if;
      if new.return_of is null or not exists (
        select 1 from public.sales o
        where o.id = new.return_of and o.business_id = new.business_id and o.voided_at is null and o.quantity > 0
      ) then
        raise exception 'invalid_return';
      end if;
      if (select o.quantity from public.sales o where o.id = new.return_of)
         + coalesce((select sum(r.quantity) from public.sales r where r.return_of = new.return_of and r.voided_at is null), 0)
         + new.quantity < 0 then
        raise exception 'invalid_return';
      end if;
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


create or replace function public._can_move_stock(p_business_id text, p_delta integer)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when auth.uid() is null then true
    when p_delta < 0 then public.has_permission(p_business_id, 'sell')
      or public.has_permission(p_business_id, 'servicesCharge')
      or public.has_permission(p_business_id, 'stockAdjust')
    else public.has_permission(p_business_id, 'voidSale')
      or public.has_permission(p_business_id, 'refund')
      or public.has_permission(p_business_id, 'stockAdjust')
      or public.has_permission(p_business_id, 'suppliers')
      or public.has_permission(p_business_id, 'productsEdit')
  end;
$$;

-- Una devolución fiada baja la deuda: también con «Devolver»
create or replace function public.adjust_customer_debt(p_customer_id text, p_delta numeric, p_auth_request_id uuid default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_business text;
  v_balance numeric;
  v_limit numeric;
  v_authorized boolean;
begin
  select c.business_id, c.debt_balance into v_business, v_balance from public.customers c where c.id = p_customer_id;
  if v_business is null then
    return;
  end if;
  if public.my_business_role(v_business) is null then
    raise exception 'not_member';
  end if;
  if auth.uid() is not null then
    v_authorized := p_auth_request_id is not null and public._auth_ok(p_auth_request_id, v_business);
    if p_delta > 0 then
      if not public.has_permission(v_business, 'credit') and not v_authorized then
        raise exception 'needs_authorization';
      end if;
      v_limit := public.my_limit(v_business, 'creditMax');
      if v_limit is not null and coalesce(v_balance, 0) + p_delta > v_limit + 0.5 and not v_authorized then
        raise exception 'needs_authorization';
      end if;
    elsif p_delta < 0 then
      if not (public.has_permission(v_business, 'collectDebts') or public.has_permission(v_business, 'voidSale')
              or public.has_permission(v_business, 'refund')) then
        raise exception 'perm_denied:collectDebts';
      end if;
    end if;
  end if;
  update public.customers set debt_balance = greatest(0, debt_balance + p_delta) where id = p_customer_id;
end;
$$;
