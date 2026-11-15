-- 0.15.0, etapa 4 de roles (docs/plan-roles.md): horario de acceso (Pro Servicios).
-- La persona solo usa la app en sus días y horas. Va por persona, como texto JSON con el
-- mismo formato que los horarios de Servicios (WorkSchedule): {"1": [480, 1080], ...}.
-- null = sin horario (entra cuando quiera). El Dueño nunca tiene horario.
-- La app lo cumple; la nube no lo revisa, para no rechazar ventas hechas en horario que
-- suben después sin internet.

alter table public.business_members add column if not exists access_schedule text;
