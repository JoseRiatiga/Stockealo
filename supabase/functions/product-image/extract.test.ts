// Pruebas de la lógica pura de product-image. Se corren con Node 23+ o Deno:
//   node --test supabase/functions/product-image/extract.test.ts
import assert from "node:assert/strict";
import { test } from "node:test";
import { findImageInHtml, isPrivateIPv4, isPrivateIPv6, sniffType } from "./extract.ts";

test("encuentra la imagen principal en las formas más comunes", () => {
  assert.equal(
    findImageInHtml('<meta property="og:image" content="https://img.ltwebstatic.com/blusa.jpg">'),
    "https://img.ltwebstatic.com/blusa.jpg",
  );
  // content antes que property, y entidades HTML
  assert.equal(
    findImageInHtml('<meta content="https://a.com/x.webp?w=800&amp;h=800" property="og:image" />'),
    "https://a.com/x.webp?w=800&h=800",
  );
  assert.equal(
    findImageInHtml('<meta name="twitter:image" content="https://b.com/t.png">'),
    "https://b.com/t.png",
  );
  // la versión segura tiene prioridad
  assert.equal(
    findImageInHtml(
      '<meta property="og:image" content="http://c.com/a.jpg"><meta property="og:image:secure_url" content="https://c.com/a.jpg">',
    ),
    "https://c.com/a.jpg",
  );
  // JSON-LD de producto con barras escapadas
  assert.equal(
    findImageInHtml('<script type="application/ld+json">{"@type":"Product","image":["https:\\/\\/d.com\\/p.jpg"]}</script>'),
    "https://d.com/p.jpg",
  );
  assert.equal(findImageInHtml('<link rel="image_src" href="/fotos/1.jpg">'), "/fotos/1.jpg");
  assert.equal(findImageInHtml("<html><body>sin imagen</body></html>"), null);
});

test("bloquea direcciones internas", () => {
  for (const ip of ["127.0.0.1", "10.1.2.3", "172.16.0.1", "192.168.1.1", "169.254.169.254", "0.0.0.0", "100.64.0.1"]) {
    assert.equal(isPrivateIPv4(ip), true, ip);
  }
  for (const ip of ["8.8.8.8", "104.16.1.1", "172.32.0.1"]) assert.equal(isPrivateIPv4(ip), false, ip);
  assert.equal(isPrivateIPv4("999.1.1.1"), true);
  for (const ip of ["::1", "fd00::1", "fe80::1", "::ffff:127.0.0.1", "[::1]"]) assert.equal(isPrivateIPv6(ip), true, ip);
  assert.equal(isPrivateIPv6("2606:4700::1111"), false);
});

test("reconoce imágenes por sus primeros bytes y rechaza lo demás", () => {
  const pad = (b: number[]) => new Uint8Array([...b, ...new Array(16).fill(0)]);
  assert.equal(sniffType(pad([0xff, 0xd8, 0xff])), "image/jpeg");
  assert.equal(sniffType(pad([0x89, 0x50, 0x4e, 0x47])), "image/png");
  assert.equal(sniffType(pad([0x52, 0x49, 0x46, 0x46, 0, 0, 0, 0, 0x57, 0x45, 0x42, 0x50])), "image/webp");
  assert.equal(sniffType(pad([...new TextEncoder().encode("<svg")])), null);
});
