-- 0.13.1: horario de trabajo de los empleados (Servicios › Empleados)
--   • businesses.services_schedule: horario del negocio para todos (JSON en texto,
--     {"1":[480,1080], …}: día 1 = lunes, minutos desde la medianoche)
--   • staff.schedule: horario propio de un empleado; si está vacío usa el del negocio
-- Fuera del turno solo se avisa; no bloquea nada.

alter table public.businesses add column if not exists services_schedule text;
alter table public.staff add column if not exists schedule text;
