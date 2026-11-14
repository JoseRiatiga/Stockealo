-- 0.14.0: datos extra de la orden para taller, servicio técnico y lavandería (estado
-- propio, fecha de entrega, presupuesto, fotos, accesorios y garantía), en un solo JSON.
alter table public.work_orders add column if not exists extra jsonb;
