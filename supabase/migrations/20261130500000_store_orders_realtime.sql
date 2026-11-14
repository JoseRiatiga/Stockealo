-- 0.13.5: el pedido nuevo de la tienda avisa al instante en la app (tiempo real).
-- Las reglas de lectura (solo miembros del negocio) también aplican al tiempo real.
alter publication supabase_realtime add table public.store_orders;
