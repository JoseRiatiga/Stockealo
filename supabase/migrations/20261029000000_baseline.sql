-- =====================================================================
-- Stockealo · Migración base (snapshot del esquema real en Supabase)
-- Capturado el 2026-10-29 desde el proyecto evdwwmkafwjyfawsufjb,
-- antes de la Fase 1 de seguridad.
--
-- Este archivo DOCUMENTA el estado actual; ya está aplicado en producción.
-- No volver a ejecutarlo sobre la base existente.
--
-- Estado de seguridad al momento del snapshot:
--   * RLS DESACTIVADO en las 7 tablas, 0 políticas.
--   * El rol anon tiene SELECT/INSERT/UPDATE/DELETE sobre todas.
--   * users.password guarda un hash SHA-256 propio (sin Supabase Auth).
--   * Bucket product-images público, con escritura abierta a cualquier rol.
-- =====================================================================

CREATE TABLE IF NOT EXISTS public.users (
    id          TEXT PRIMARY KEY,
    email       TEXT NOT NULL UNIQUE,
    password    TEXT NOT NULL,
    name        TEXT,
    phone       TEXT,
    avatar_path TEXT,
    created_at  TIMESTAMPTZ DEFAULT now()
);

-- Nota: en la nube businesses NO tiene columna de dueño; la propiedad se
-- deriva de business_members.role = 'OWNER'.
CREATE TABLE IF NOT EXISTS public.businesses (
    id         TEXT PRIMARY KEY,
    name       TEXT NOT NULL,
    type       TEXT NOT NULL,
    currency   TEXT NOT NULL DEFAULT 'COP',
    is_deleted INTEGER NOT NULL DEFAULT 0,
    deleted_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.business_members (
    id          TEXT PRIMARY KEY,
    business_id TEXT REFERENCES public.businesses(id) ON DELETE CASCADE,
    user_id     TEXT NOT NULL,
    user_email  TEXT NOT NULL,
    user_name   TEXT NOT NULL,
    role        TEXT NOT NULL DEFAULT 'CASHIER',
    created_at  TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.categories (
    id          TEXT PRIMARY KEY,
    business_id TEXT REFERENCES public.businesses(id) ON DELETE CASCADE,
    name        TEXT NOT NULL,
    color_hex   TEXT DEFAULT '0xFF059669',
    created_at  TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.products (
    id              TEXT PRIMARY KEY,
    business_id     TEXT REFERENCES public.businesses(id) ON DELETE CASCADE,
    name            TEXT NOT NULL,
    sku             TEXT NOT NULL,
    category        TEXT NOT NULL DEFAULT 'General',
    cost_price      NUMERIC NOT NULL DEFAULT 0,
    sale_price      NUMERIC NOT NULL,
    current_stock   INTEGER NOT NULL DEFAULT 0,
    min_stock_alert INTEGER NOT NULL DEFAULT 5,
    image_url       TEXT,
    created_at      TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.customers (
    id           TEXT PRIMARY KEY,
    business_id  TEXT REFERENCES public.businesses(id) ON DELETE CASCADE,
    name         TEXT NOT NULL,
    phone        TEXT,
    address      TEXT,
    debt_balance NUMERIC NOT NULL DEFAULT 0,
    created_at   TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.sales (
    id             TEXT PRIMARY KEY,
    business_id    TEXT REFERENCES public.businesses(id) ON DELETE CASCADE,
    product_id     TEXT REFERENCES public.products(id) ON DELETE SET NULL,
    quantity       INTEGER NOT NULL,
    unit_price     NUMERIC NOT NULL,
    unit_cost      NUMERIC NOT NULL DEFAULT 0,
    total_amount   NUMERIC NOT NULL,
    payment_method TEXT NOT NULL DEFAULT 'Efectivo',
    customer_id    TEXT REFERENCES public.customers(id) ON DELETE SET NULL,
    sale_date      TIMESTAMPTZ DEFAULT now(),
    product_name   TEXT,
    customer_name  TEXT
);

ALTER TABLE public.users            DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.businesses       DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.business_members DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.categories       DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.products         DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.customers        DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.sales            DISABLE ROW LEVEL SECURITY;

-- Storage: bucket público product-images (creado desde el panel).
-- Políticas actuales sobre storage.objects, para el rol public:
CREATE POLICY "Permitir ver imágenes de productos" ON storage.objects
    FOR SELECT TO public USING (bucket_id = 'product-images');
CREATE POLICY "Permitir subida de imágenes de productos" ON storage.objects
    FOR INSERT TO public WITH CHECK (bucket_id = 'product-images');
CREATE POLICY "Permitir actualizar imágenes de productos" ON storage.objects
    FOR UPDATE TO public USING (bucket_id = 'product-images');
