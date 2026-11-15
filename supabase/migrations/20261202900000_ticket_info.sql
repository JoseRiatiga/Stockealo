-- 0.15.0: el tiquete con los datos del negocio (NIT, dirección, teléfono) y su propia
-- despedida. Un solo campo con texto JSON: {"tax_id": "...", "address": "...",
-- "phone": "...", "footer": "..."}. null = el tiquete de siempre.

alter table public.businesses add column if not exists ticket_info text;
