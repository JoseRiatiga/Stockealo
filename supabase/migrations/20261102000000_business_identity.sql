-- Identidad y preferencias del negocio (versión 0.9.0)
--
-- country                país del negocio (código ISO de 2 letras): prefijo telefónico,
--                        medios de pago y consejos de Stocky
-- icon, color            ícono y color elegidos al crear el negocio
-- logo_url               logo propio (opcional). Se guarda en el bucket product-images,
--                        en la carpeta del negocio, así que lo cubren las políticas
--                        que ya existen (lo ven los miembros; lo cambian dueño y admin)
-- cash_register_enabled  arqueo de caja opcional; apagado por defecto
--
-- Solo agrega columnas: no modifica ni borra datos existentes.

alter table public.businesses
  add column if not exists country text not null default 'CO',
  add column if not exists icon text,
  add column if not exists color text,
  add column if not exists logo_url text,
  add column if not exists cash_register_enabled boolean not null default false;

-- País inicial según la moneda que ya tenía cada negocio
update public.businesses
set country = case currency
  when 'MXN' then 'MX'
  when 'PEN' then 'PE'
  when 'ARS' then 'AR'
  when 'CLP' then 'CL'
  when 'EUR' then 'ES'
  when 'USD' then 'US'
  else 'CO'
end;

alter table public.businesses
  drop constraint if exists businesses_country_format,
  add constraint businesses_country_format check (country ~ '^[A-Z]{2}$'),
  drop constraint if exists businesses_color_format,
  add constraint businesses_color_format check (color is null or color ~ '^#[0-9A-Fa-f]{6}$');
