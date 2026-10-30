-- Fase 4 · Ventas en tiempo real.
--
-- La app ya escucha inserciones en `sales`, pero la tabla no estaba publicada
-- para Realtime, así que nunca llegaba nada. Realtime aplica las políticas RLS
-- de quien escucha: cada cuenta solo recibe ventas de sus negocios.
--
-- created_by guarda quién hizo la venta (Supabase Auth) para que el vendedor no
-- reciba la notificación de su propia venta.

alter table public.sales add column if not exists created_by uuid default auth.uid();

alter publication supabase_realtime add table public.sales;
