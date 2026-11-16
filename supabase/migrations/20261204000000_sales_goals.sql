-- 0.16.0, fase 0: metas de ventas (semanal o mensual, del negocio o de una persona).
--
-- • sales_goals: una fila por negocio, periodo, persona y fecha de inicio. La meta vale
--   desde esa semana o ese mes hasta que se ponga otra; amount 0 = se quitó.
-- • Solo el dueño las pone. El equipo ve la del negocio y cada persona solo la suya.
-- • member_sales: lo vendido por cada persona en un rango (quién hizo cada venta lo
--   guarda la nube en created_by). El dueño ve a todos; los demás, solo lo suyo.

create table if not exists public.sales_goals (
  id text primary key,
  business_id text not null references public.businesses(id) on delete cascade,
  period text not null check (period in ('WEEK', 'MONTH')),
  member_user_id text,
  member_name text check (member_name is null or length(member_name) <= 80),
  amount numeric not null default 0 check (amount >= 0 and amount < 1e13),
  starts_on date not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists sales_goals_business_idx on public.sales_goals (business_id);

alter table public.sales_goals enable row level security;

drop policy if exists sales_goals_select on public.sales_goals;
create policy sales_goals_select on public.sales_goals
  for select to authenticated using (
    public.my_business_role(business_id) = 'OWNER'
    or (public.my_business_role(business_id) is not null
        and (member_user_id is null or member_user_id = auth.uid()::text))
  );

drop policy if exists sales_goals_insert on public.sales_goals;
create policy sales_goals_insert on public.sales_goals
  for insert to authenticated with check (public.my_business_role(business_id) = 'OWNER');

drop policy if exists sales_goals_update on public.sales_goals;
create policy sales_goals_update on public.sales_goals
  for update to authenticated
  using (public.my_business_role(business_id) = 'OWNER')
  with check (public.my_business_role(business_id) = 'OWNER');

drop policy if exists sales_goals_delete on public.sales_goals;
create policy sales_goals_delete on public.sales_goals
  for delete to authenticated using (public.my_business_role(business_id) = 'OWNER');

create or replace function public.member_sales(p_business_id text, p_from timestamptz, p_to timestamptz)
returns table (user_id text, total numeric)
language sql
stable
security definer
set search_path = ''
as $$
  select s.created_by::text, coalesce(sum(s.total_amount), 0)
  from public.sales s
  where s.business_id = p_business_id
    and s.voided_at is null
    and s.created_by is not null
    and s.sale_date >= p_from and s.sale_date < p_to
    and public.my_business_role(p_business_id) is not null
    and (public.my_business_role(p_business_id) = 'OWNER' or s.created_by = auth.uid())
  group by s.created_by;
$$;

revoke all on function public.member_sales(text, timestamptz, timestamptz) from public, anon;
grant execute on function public.member_sales(text, timestamptz, timestamptz) to authenticated;
