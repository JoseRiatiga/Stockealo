// Stockealo · product-image
//
// Trae la foto de un producto desde un enlace y la guarda en Storage del negocio.
//
// Entrada (POST, con el JWT de la cuenta):
//   { "business_id": "...", "product_id": "...", "url": "https://…" }
//   El enlace puede ser la página del producto (Shein, Temu, Mercado Libre…) o
//   directamente la imagen.
// Salida:
//   { "url": "https://…/storage/v1/object/public/product-images/<negocio>/<producto>.jpg?t=…" }
// Errores: not_authenticated, bad_request, not_allowed, invalid_url, blocked,
//   no_image, too_large, unsupported_type, fetch_failed, daily_limit
//
// Seguridad:
//   • Solo el dueño o un administrador del negocio (como al crear productos)
//   • Solo http/https en puertos normales; nunca direcciones internas (localhost,
//     redes privadas, metadatos de la nube), revisando también cada redirección
//   • Límites de tiempo, de tamaño (página 1,5 MB, imagen 6 MB) y de tipo
//     (JPEG, PNG, WebP, GIF)
//   • Máximo DAILY_LIMIT importaciones por cuenta y día (tabla image_imports)
//   • La foto se copia a Storage: no se enlaza a la tienda original
//
// Variables provistas por Supabase: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY

import { createClient } from "jsr:@supabase/supabase-js@2";
import { findImageInHtml, isPrivateIPv4, isPrivateIPv6, sniffType } from "./extract.ts";

const DAILY_LIMIT = 40;
const MAX_HTML = 1_500_000;
const MAX_IMAGE = 6_000_000;
const TIMEOUT_MS = 10_000;
const MAX_REDIRECTS = 4;
const BUCKET = "product-images";
const USER_AGENT =
  "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36";

const IMAGE_TYPES: Record<string, string> = {
  "image/jpeg": "jpg",
  "image/jpg": "jpg",
  "image/png": "png",
  "image/webp": "webp",
  "image/gif": "gif",
};

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

class ImportError extends Error {
  constructor(public code: string, public status = 400) {
    super(code);
  }
}

// ---------------------------------------------------------------------------
// Direcciones permitidas
// ---------------------------------------------------------------------------

async function assertPublicUrl(raw: string): Promise<URL> {
  let url: URL;
  try {
    url = new URL(raw);
  } catch {
    throw new ImportError("invalid_url");
  }
  if (url.protocol !== "http:" && url.protocol !== "https:") throw new ImportError("invalid_url");
  if (url.username || url.password) throw new ImportError("invalid_url");
  if (url.port && url.port !== "80" && url.port !== "443") throw new ImportError("blocked");

  const host = url.hostname.toLowerCase();
  if (
    host === "localhost" || host.endsWith(".localhost") || host.endsWith(".local") ||
    host.endsWith(".internal") || host.endsWith(".supabase.co") || !host.includes(".")
  ) {
    throw new ImportError("blocked");
  }
  if (/^\d+\.\d+\.\d+\.\d+$/.test(host)) {
    if (isPrivateIPv4(host)) throw new ImportError("blocked");
    return url;
  }
  if (host.includes(":")) {
    if (isPrivateIPv6(host)) throw new ImportError("blocked");
    return url;
  }
  // Un nombre puede apuntar a una red interna: se revisa a qué direcciones resuelve
  const addresses: string[] = [];
  for (const type of ["A", "AAAA"] as const) {
    try {
      addresses.push(...(await Deno.resolveDns(host, type)));
    } catch {
      // sin registros de ese tipo
    }
  }
  if (addresses.length === 0) throw new ImportError("fetch_failed");
  if (addresses.some((a) => (a.includes(":") ? isPrivateIPv6(a) : isPrivateIPv4(a)))) {
    throw new ImportError("blocked");
  }
  return url;
}

// ---------------------------------------------------------------------------
// Descargas con límites
// ---------------------------------------------------------------------------

async function safeFetch(start: string, accept: string): Promise<{ res: Response; url: URL }> {
  let current = await assertPublicUrl(start);
  for (let hop = 0; hop <= MAX_REDIRECTS; hop++) {
    const res = await fetch(current, {
      redirect: "manual",
      signal: AbortSignal.timeout(TIMEOUT_MS),
      headers: { "User-Agent": USER_AGENT, "Accept": accept, "Accept-Language": "es-CO,es;q=0.9,en;q=0.8" },
    });
    if (res.status >= 300 && res.status < 400) {
      const location = res.headers.get("location");
      await res.body?.cancel();
      if (!location) throw new ImportError("fetch_failed");
      current = await assertPublicUrl(new URL(location, current).toString());
      continue;
    }
    if (!res.ok) {
      await res.body?.cancel();
      throw new ImportError("fetch_failed");
    }
    return { res, url: current };
  }
  throw new ImportError("fetch_failed");
}

async function readLimited(res: Response, max: number): Promise<Uint8Array> {
  const declared = Number(res.headers.get("content-length") ?? "0");
  if (declared > max) {
    await res.body?.cancel();
    throw new ImportError("too_large");
  }
  const reader = res.body?.getReader();
  if (!reader) return new Uint8Array();
  const chunks: Uint8Array[] = [];
  let total = 0;
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    total += value.length;
    if (total > max) {
      await reader.cancel();
      throw new ImportError("too_large");
    }
    chunks.push(value);
  }
  const out = new Uint8Array(total);
  let offset = 0;
  for (const c of chunks) {
    out.set(c, offset);
    offset += c.length;
  }
  return out;
}

async function fetchImage(link: string): Promise<{ bytes: Uint8Array; type: string }> {
  const { res, url } = await safeFetch(link, "text/html,application/xhtml+xml,image/*;q=0.9,*/*;q=0.8");
  const contentType = (res.headers.get("content-type") ?? "").split(";")[0].trim().toLowerCase();

  // Enlace directo a la imagen
  if (contentType.startsWith("image/")) {
    const bytes = await readLimited(res, MAX_IMAGE);
    const type = sniffType(bytes);
    if (!type) throw new ImportError("unsupported_type");
    return { bytes, type };
  }

  // Página del producto: se busca su imagen principal
  const html = new TextDecoder().decode(await readLimited(res, MAX_HTML));
  const found = findImageInHtml(html);
  if (!found) throw new ImportError("no_image");
  const imageUrl = new URL(found, url).toString();
  // Sin AVIF: algunos navegadores y celulares viejos no lo muestran
  const img = await safeFetch(imageUrl, "image/webp,image/png,image/jpeg,image/gif;q=0.9,*/*;q=0.5");
  const bytes = await readLimited(img.res, MAX_IMAGE);
  const type = sniffType(bytes);
  if (!type) throw new ImportError("unsupported_type");
  return { bytes, type };
}

// ---------------------------------------------------------------------------

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false, autoRefreshToken: false } },
  );
  const jwt = req.headers.get("Authorization")?.replace(/^Bearer\s+/i, "") ?? "";
  const { data: auth, error: authError } = await admin.auth.getUser(jwt);
  const user = auth?.user;
  const email = user?.email?.toLowerCase();
  if (authError || !user || !email) return json({ error: "not_authenticated" }, 401);

  let body: { business_id?: unknown; product_id?: unknown; url?: unknown };
  try {
    body = await req.json();
  } catch {
    return json({ error: "bad_request" }, 400);
  }
  const businessId = typeof body.business_id === "string" ? body.business_id.trim() : "";
  const productId = typeof body.product_id === "string" ? body.product_id.trim() : "";
  const link = typeof body.url === "string" ? body.url.trim() : "";
  // Los ids forman la ruta en Storage: nada de "/" ni ".."
  const safeId = /^[A-Za-z0-9_-]{1,64}$/;
  if (!safeId.test(businessId) || !safeId.test(productId) || !link || link.length > 2000) {
    return json({ error: "bad_request" }, 400);
  }

  // Igual que al crear productos: dueño o administrador del negocio
  const emailPattern = email.replace(/[\\%_]/g, "\\$&");
  const { data: member } = await admin
    .from("business_members")
    .select("role")
    .eq("business_id", businessId)
    .ilike("user_email", emailPattern)
    .in("role", ["OWNER", "ADMIN"])
    .limit(1)
    .maybeSingle();
  if (!member) return json({ error: "not_allowed" }, 403);

  const since = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();
  const { count } = await admin
    .from("image_imports")
    .select("id", { count: "exact", head: true })
    .eq("user_id", user.id)
    .gte("created_at", since);
  if ((count ?? 0) >= DAILY_LIMIT) return json({ error: "daily_limit" }, 429);
  await admin.from("image_imports").insert({ user_id: user.id });

  try {
    const { bytes, type } = await fetchImage(link);
    const ext = IMAGE_TYPES[type] ?? "jpg";
    const path = `${businessId}/${productId}.${ext}`;
    const { error: uploadError } = await admin.storage.from(BUCKET).upload(path, bytes, {
      contentType: type,
      upsert: true,
    });
    if (uploadError) {
      console.error("Storage:", uploadError.message);
      return json({ error: "fetch_failed" }, 502);
    }
    const { data } = admin.storage.from(BUCKET).getPublicUrl(path);
    return json({ url: `${data.publicUrl}?t=${Date.now()}` });
  } catch (e) {
    if (e instanceof ImportError) return json({ error: e.code }, e.status);
    console.error("product-image:", e instanceof Error ? e.message : e);
    return json({ error: "fetch_failed" }, 502);
  }
});
