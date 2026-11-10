-- Stockealo 0.12.0: mensajes por fase del módulo Servicios
--
--   • businesses.service_messages: los textos de cada fase (Recibido, En proceso,
--     Listo, Entregado) y si están encendidos. Vacío = los de la plantilla.
-- No borra ni cambia datos existentes.

alter table public.businesses add column if not exists service_messages jsonb;
