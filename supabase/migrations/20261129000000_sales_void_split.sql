-- Ventas anuladas sin borrar y pago mixto (re-diseño 0.13.0, bloque 4)
--
-- Antes, anular una venta la borraba de la nube. Ahora queda en el historial como
-- «Anulada», con el motivo y quién la anuló, y deja de contar en los totales.
-- El pago mixto guarda cuánto entró por cada medio (JSON: {"EFECTIVO": 20000, "NEQUI": 21500}).
-- Solo agrega cuatro columnas opcionales; no cambia datos existentes.
--
-- IMPORTANTE: aplicarla ANTES de publicar la 0.13.0. Mientras no esté, la app sube la
-- venta sin estas columnas (no falla), pero la nube la seguiría contando como válida.

alter table public.sales add column if not exists voided_at timestamptz;
alter table public.sales add column if not exists void_reason text;
alter table public.sales add column if not exists voided_by text;
alter table public.sales add column if not exists payment_split text;
