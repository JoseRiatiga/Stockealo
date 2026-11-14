-- 0.14.0: «Habilitar múltiples servicios» se guarda en el negocio (antes solo en el
-- aparato): así lo ve igual todo el equipo.
alter table public.businesses add column if not exists services_multi boolean not null default false;
