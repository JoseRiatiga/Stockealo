-- 0.14.0: alquiler de silla. El empleado paga un valor fijo por día, semana o mes y se
-- queda con todo lo de sus servicios; al pagarle se descuenta el alquiler.
alter table public.staff add column if not exists chair_rent numeric;
alter table public.staff add column if not exists rent_period text check (rent_period is null or rent_period in ('DIA', 'SEMANA', 'MES'));
