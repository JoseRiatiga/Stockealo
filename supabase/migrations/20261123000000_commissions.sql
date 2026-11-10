-- Stockealo 0.12.0: comisiones y liquidaciones del módulo Servicios
--
--   • commissions: lo que gana cada persona por servicio cobrado (% sobre lo cobrado,
--     repartido si lo hicieron varios), las propinas y los ajustes por anulaciones.
--   • staff_payouts: cada pago a una persona (suma de comisiones y propinas pendientes).
--   • Acceso: ven los miembros del negocio. Cualquier miembro registra o borra
--     comisiones pendientes (el cajero cobra y anula); marcar una comisión como pagada,
--     cambiar una pagada y registrar liquidaciones, solo el dueño o un administrador.
-- No borra ni cambia datos existentes.

create table if not exists public.commissions (
  id text primary key,
  business_id text not null references public.businesses (id) on delete cascade,
  staff_id text not null references public.staff (id) on delete cascade,
  work_order_id text,
  sale_id text,
  kind text not null default 'SERVICIO' check (kind in ('SERVICIO', 'PROPINA', 'AJUSTE')),
  label text not null,
  base numeric not null default 0,
  pct numeric not null default 0 check (pct >= 0 and pct <= 100),
  amount numeric not null default 0,
  date timestamptz not null,
  payout_id text,
  updated_at timestamptz not null default now()
);
create index if not exists idx_commissions_business_date on public.commissions (business_id, date desc);
create index if not exists idx_commissions_staff_pending on public.commissions (staff_id) where payout_id is null;
create index if not exists idx_commissions_sale on public.commissions (sale_id);

create table if not exists public.staff_payouts (
  id text primary key,
  business_id text not null references public.businesses (id) on delete cascade,
  staff_id text not null references public.staff (id) on delete cascade,
  from_date timestamptz not null,
  to_date timestamptz not null,
  commissions numeric not null default 0,
  tips numeric not null default 0,
  total numeric not null default 0,
  paid_at timestamptz not null,
  paid_by text
);
create index if not exists idx_staff_payouts_business on public.staff_payouts (business_id, paid_at desc);

alter table public.commissions enable row level security;
alter table public.staff_payouts enable row level security;

drop policy if exists commissions_select on public.commissions;
create policy commissions_select on public.commissions for select to authenticated
  using (public.my_business_role(business_id) is not null);
drop policy if exists commissions_insert on public.commissions;
create policy commissions_insert on public.commissions for insert to authenticated
  with check (
    public.my_business_role(business_id) is not null
    and (payout_id is null or public.my_business_role(business_id) = any (array['OWNER', 'ADMIN']))
  );
drop policy if exists commissions_update on public.commissions;
create policy commissions_update on public.commissions for update to authenticated
  using (
    public.my_business_role(business_id) = any (array['OWNER', 'ADMIN'])
    or (public.my_business_role(business_id) is not null and payout_id is null)
  )
  with check (
    public.my_business_role(business_id) = any (array['OWNER', 'ADMIN'])
    or (public.my_business_role(business_id) is not null and payout_id is null)
  );
drop policy if exists commissions_delete on public.commissions;
create policy commissions_delete on public.commissions for delete to authenticated
  using (
    public.my_business_role(business_id) = any (array['OWNER', 'ADMIN'])
    or (public.my_business_role(business_id) is not null and payout_id is null)
  );

drop policy if exists staff_payouts_select on public.staff_payouts;
create policy staff_payouts_select on public.staff_payouts for select to authenticated
  using (public.my_business_role(business_id) is not null);
drop policy if exists staff_payouts_write on public.staff_payouts;
create policy staff_payouts_write on public.staff_payouts for all to authenticated
  using (public.my_business_role(business_id) = any (array['OWNER', 'ADMIN']))
  with check (public.my_business_role(business_id) = any (array['OWNER', 'ADMIN']));

revoke all on public.commissions from anon;
revoke all on public.staff_payouts from anon;
grant select, insert, update, delete on public.commissions to authenticated;
grant select, insert, update, delete on public.staff_payouts to authenticated;
