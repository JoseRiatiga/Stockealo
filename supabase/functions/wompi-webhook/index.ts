// Stockealo · wompi-webhook
//
// "URL de eventos" de Wompi: recibe los avisos de transacciones y activa Stockealo
// Pro cuando un pago queda aprobado.
//
// Wompi la llama sin sesión (verify_jwt = false). La seguridad está en la firma del
// evento: SHA-256 de los valores de signature.properties + timestamp + el secreto
// de eventos. Un aviso con firma inválida se rechaza.
//
// pro_apply_payment es idempotente: si Wompi avisa dos veces, Pro no se suma dos
// veces. Las transacciones que no son de Stockealo Pro (referencia desconocida) se
// ignoran con 200 para que Wompi no las reintente.
//
// Secretos: WOMPI_EVENTS_SECRET
// Variables provistas por Supabase: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY

import { createClient } from "jsr:@supabase/supabase-js@2";

type WompiEvent = {
  event?: string;
  data?: { transaction?: Record<string, unknown> };
  signature?: { properties?: string[]; checksum?: string };
  timestamp?: number;
};

function reply(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}

async function sha256(text: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return Array.from(new Uint8Array(digest)).map((b) => b.toString(16).padStart(2, "0")).join("");
}

/** Valor de una ruta como "transaction.amount_in_cents" dentro de event.data */
function valueAt(data: Record<string, unknown>, path: string): string {
  let current: unknown = data;
  for (const key of path.split(".")) {
    if (current === null || typeof current !== "object") return "";
    current = (current as Record<string, unknown>)[key];
  }
  return current === undefined || current === null ? "" : String(current);
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return reply({ error: "method_not_allowed" }, 405);

  const eventsSecret = Deno.env.get("WOMPI_EVENTS_SECRET");
  if (!eventsSecret) return reply({ error: "not_configured" }, 503);

  let event: WompiEvent;
  try {
    event = await req.json();
  } catch {
    return reply({ error: "bad_request" }, 400);
  }

  const properties = event.signature?.properties ?? [];
  const checksum = event.signature?.checksum ?? "";
  if (!event.data || !properties.length || !checksum || event.timestamp === undefined) {
    return reply({ error: "bad_signature" }, 401);
  }
  const concatenated = properties.map((p) => valueAt(event.data as Record<string, unknown>, p)).join("");
  const expected = await sha256(`${concatenated}${event.timestamp}${eventsSecret}`);
  if (expected.toLowerCase() !== checksum.toLowerCase()) return reply({ error: "bad_signature" }, 401);

  if (event.event !== "transaction.updated") return reply({ ok: true, ignored: event.event });

  const tx = event.data.transaction ?? {};
  const reference = String(tx.reference ?? "");
  if (!reference.startsWith("STK-")) return reply({ ok: true, ignored: "not_stockealo" });

  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false, autoRefreshToken: false } },
  );
  const { data, error } = await admin.rpc("pro_apply_payment", {
    p_reference: reference,
    p_transaction_id: String(tx.id ?? ""),
    p_status: String(tx.status ?? ""),
    p_method: String(tx.payment_method_type ?? ""),
    p_amount_in_cents: Number(tx.amount_in_cents ?? 0),
    p_currency: String(tx.currency ?? ""),
  });
  if (error) {
    if (error.message.includes("payment_not_found")) return reply({ ok: true, ignored: "unknown_reference" });
    console.error("wompi-webhook", error.message);
    // 500: Wompi reintenta más tarde
    return reply({ error: "server_error" }, 500);
  }
  return reply({ ok: true, result: data });
});
