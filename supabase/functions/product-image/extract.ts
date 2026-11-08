// Stockealo · product-image: lógica pura (sin red), para poder probarla aparte.

export function isPrivateIPv4(ip: string): boolean {
  const p = ip.split(".").map(Number);
  if (p.length !== 4 || p.some((n) => !Number.isInteger(n) || n < 0 || n > 255)) return true;
  const [a, b] = p;
  return a === 0 || a === 10 || a === 127 || (a === 100 && b >= 64 && b <= 127) ||
    (a === 169 && b === 254) || (a === 172 && b >= 16 && b <= 31) || (a === 192 && b === 168) ||
    (a === 192 && b === 0) || (a === 198 && (b === 18 || b === 19)) || a >= 224;
}

export function isPrivateIPv6(ip: string): boolean {
  const v = ip.toLowerCase().replace(/^\[|\]$/g, "");
  if (v === "::" || v === "::1") return true;
  const mapped = v.match(/^::ffff:(\d+\.\d+\.\d+\.\d+)$/);
  if (mapped) return isPrivateIPv4(mapped[1]);
  return v.startsWith("fc") || v.startsWith("fd") || v.startsWith("fe8") || v.startsWith("fe9") ||
    v.startsWith("fea") || v.startsWith("feb") || v.startsWith("ff");
}

function decodeEntities(s: string): string {
  return s.replace(/&amp;/g, "&").replace(/&quot;/g, '"').replace(/&#39;/g, "'").replace(/&#x2F;/gi, "/")
    .replace(/\\u002F/gi, "/").replace(/\\\//g, "/").trim();
}

/** Imagen principal de una página: Open Graph, Twitter, schema.org o image_src */
export function findImageInHtml(html: string): string | null {
  const metaPatterns = [
    /<meta[^>]+(?:property|name)=["']og:image:secure_url["'][^>]*content=["']([^"']+)["']/i,
    /<meta[^>]+content=["']([^"']+)["'][^>]*(?:property|name)=["']og:image:secure_url["']/i,
    /<meta[^>]+(?:property|name)=["']og:image(?::url)?["'][^>]*content=["']([^"']+)["']/i,
    /<meta[^>]+content=["']([^"']+)["'][^>]*(?:property|name)=["']og:image(?::url)?["']/i,
    /<meta[^>]+(?:property|name)=["']twitter:image(?::src)?["'][^>]*content=["']([^"']+)["']/i,
    /<meta[^>]+content=["']([^"']+)["'][^>]*(?:property|name)=["']twitter:image(?::src)?["']/i,
    /<meta[^>]+itemprop=["']image["'][^>]*content=["']([^"']+)["']/i,
    /<link[^>]+rel=["']image_src["'][^>]*href=["']([^"']+)["']/i,
  ];
  for (const re of metaPatterns) {
    const m = html.match(re);
    if (m?.[1]) return decodeEntities(m[1]);
  }
  // JSON-LD de producto: "image": "…" o "image": ["…"]
  const ld = html.match(/"image"\s*:\s*\[?\s*"(https?:[^"]+)"/i);
  if (ld?.[1]) return decodeEntities(ld[1]);
  return null;
}

/** El tipo real del archivo por sus primeros bytes (no se confía en el encabezado) */
export function sniffType(bytes: Uint8Array): string | null {
  if (bytes.length < 12) return null;
  if (bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff) return "image/jpeg";
  if (bytes[0] === 0x89 && bytes[1] === 0x50 && bytes[2] === 0x4e && bytes[3] === 0x47) return "image/png";
  if (bytes[0] === 0x47 && bytes[1] === 0x49 && bytes[2] === 0x46) return "image/gif";
  if (
    bytes[0] === 0x52 && bytes[1] === 0x49 && bytes[2] === 0x46 && bytes[3] === 0x46 &&
    bytes[8] === 0x57 && bytes[9] === 0x45 && bytes[10] === 0x42 && bytes[11] === 0x50
  ) return "image/webp";
  return null;
}

/**
 * La tienda mandó a una página de verificación antibots ("demuestra que no eres un
 * robot") en vez del producto. Por la dirección final es seguro: se revisa siempre.
 */
export function isChallengeUrl(finalUrl: string): boolean {
  const url = finalUrl.toLowerCase();
  return /\/(risk|captcha|challenge|verify|punish)([/?#]|$)/.test(url) || url.includes("captcha");
}

/**
 * Marcas de verificación antibots dentro del HTML. Solo se usa cuando la página no
 * trae imagen: una página de producto normal puede mencionar "captcha" en su código.
 */
export function looksLikeBotChallenge(html: string): boolean {
  return /captcha|cf-chl-|challenge-platform|_incapsula_|are you a robot|verify you are human/i.test(
    html.slice(0, 200_000),
  );
}

const GENERIC_PARTS = new Set(["www", "m", "com", "co", "net", "org", "shop", "store", "es", "mx", "ar", "pe", "cl", "us", "uk"]);

/** Nombre corto de la tienda para el mensaje ("www.shein.com.co" → "Shein") */
export function storeName(host: string): string {
  const parts = host.toLowerCase().split(".").filter((p) => p && !GENERIC_PARTS.has(p));
  const name = parts.length ? parts[parts.length - 1] : host;
  return name.charAt(0).toUpperCase() + name.slice(1);
}
