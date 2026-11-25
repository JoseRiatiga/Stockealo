// Stockealo · pro-checkout
//
// Inicia el pago de Stockealo Pro con Wompi.
//
// Entrada (POST, con el JWT de la cuenta):
//   { "business_id": "...", "plan_id": "business_month_cop", "platform": "app" | "web", "coupon"?: "PRIMERMES30",
//     "branch_slots"?: 2, "upgrade"?: true }
//   plan_id = "branch_slots" compra solo cupos de sede con el plan vigente (0.18.3).
// Salida:
//   { "reference": "STK-…", "url": "https://checkout.wompi.co/p/?…" }
//
// El precio sale de pro_plans en el servidor (la app no lo puede cambiar) y el enlace
// lleva la firma de integridad de Wompi. Pro se activa cuando llega el aviso a
// wompi-webhook, no aquí. Con cupón (0.16.0), pro_coupon_price revisa el cupón y da el
// precio con descuento; el uso se cuenta cuando el pago queda aprobado.
// Cupos de sede (0.18.3): el precio sale de branch_slot_quote (la misma cuenta que ve la
// app) y el cupón solo descuenta el plan. Sin branch_slots, todo es como antes.
// Subida a Pro Servicios (0.18.3): con "upgrade": true se descuenta lo que le queda de
// Pro pagado (pro_upgrade_quote) y ese Pro se corta al aprobarse el pago. No se suma a
// un cupón. Sin "upgrade" (app 0.18.2), todo es como antes.
//
// Permisos: Pro Negocio lo compra el dueño o un administrador del negocio;
// Pro Global, solo el dueño (aplica a todos sus negocios).
// Con la llave de pruebas (pub_test_) solo pueden pagar las cuentas de app_admins.
//
// Secretos: WOMPI_INTEGRITY_SECRET
// Ajustes (pro_settings): wompi_public_key
// Mantenimiento (get_maintenance): con "payments" activo en nivel 2 o 3 responde { error: "maintenance" }
// Variables provistas por Supabase: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY

import { createClient } from "jsr:@supabase/supabase-js@2";

// A dónde vuelve el cliente al terminar en Wompi: en el celular, una página que abre
// la app (stockealo://pago); en la web, una que dice "vuelve a la pestaña de Stockealo"
const REDIRECT_URL = "https://stockealo.online/pago/";
const REDIRECT_URL_WEB = "https://stockealo.online/pago/web/";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-stockealo-branches",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

async function sha256(text: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return Array.from(new Uint8Array(digest)).map((b) => b.toString(16).padStart(2, "0")).join("");
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const integritySecret = Deno.env.get("WOMPI_INTEGRITY_SECRET");
  if (!integritySecret) return json({ error: "payments_not_configured" }, 503);

  const jwt = req.headers.get("Authorization")?.replace(/^Bearer\s+/i, "") ?? "";
  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false, autoRefreshToken: false } },
  );
  const { data: auth, error: authError } = await admin.auth.getUser(jwt);
  const email = auth?.user?.email?.toLowerCase();
  if (authError || !email) return json({ error: "not_authenticated" }, 401);
  // ilike sin comodines: el "_" de un correo no debe coincidir con otro carácter
  const emailPattern = email.replace(/[\\%_]/g, "\\$&");

  let body: {
    business_id?: unknown;
    plan_id?: unknown;
    platform?: unknown;
    coupon?: unknown;
    branch_slots?: unknown;
    upgrade?: unknown;
  };
  try {
    body = await req.json();
  } catch {
    return json({ error: "bad_request" }, 400);
  }
  const businessId = typeof body.business_id === "string" ? body.business_id : "";
  const planId = typeof body.plan_id === "string" ? body.plan_id : "";
  if (!businessId || !planId) return json({ error: "bad_request" }, 400);
  const slots = body.branch_slots === undefined || body.branch_slots === null ? 0 : Number(body.branch_slots);
  if (!Number.isInteger(slots) || slots < 0 || slots > 50) return json({ error: "bad_request" }, 400);
  const slotsOnly = planId === "branch_slots";
  if (slotsOnly && slots < 1) return json({ error: "bad_request" }, 400);

  // Mantenimiento con los pagos en pausa (nivel 2 o 3): nadie paga mientras tanto,
  // salvo los administradores, que deben poder probar antes de reabrir
  const { data: maintenance } = await admin.rpc("get_maintenance");
  const m = maintenance as { state?: string; level?: number; scopes?: string[] } | null;
  if (m?.state === "active" && (m.level ?? 0) >= 2 && (m.scopes ?? []).includes("payments")) {
    const { data: isAdminRow } = await admin.from("app_admins").select("email").ilike("email", emailPattern).maybeSingle();
    if (!isAdminRow) return json({ error: "maintenance" }, 503);
  }

  const { data: planRow } = slotsOnly ? { data: null } : await admin
    .from("pro_plans")
    .select("id, kind, period, currency, price, active")
    .eq("id", planId)
    .maybeSingle();
  if (!slotsOnly && (!planRow || !planRow.active)) return json({ error: "plan_not_found" }, 404);
  // Wompi cobra en pesos colombianos
  if (planRow && planRow.currency !== "COP") return json({ error: "currency_not_supported" }, 400);

  // Cupos de sede: la nube hace la cuenta (precio, días que faltan, fecha de fin)
  type Quote = { ok: boolean; error?: string; kind?: string; period?: string; amount?: number; ends_at?: string; gap?: number };
  let quote: Quote | null = null;
  if (slots > 0) {
    const { data: q, error: quoteError } = await admin.rpc("branch_slot_quote", {
      p_business_id: businessId,
      p_plan_id: slotsOnly ? null : planId,
      p_slots: slots,
    });
    if (quoteError) {
      console.error("pro-checkout quote", quoteError.message);
      return json({ error: "server_error" }, 500);
    }
    quote = q as Quote;
    if (!quote?.ok) return json({ error: quote?.error ?? "slots_not_allowed" }, 409);
  }
  // Solo cupos: el "plan" es el vigente del negocio
  const plan = planRow ?? { id: "branch_slots", kind: quote!.kind!, period: quote!.period!, price: 0 };

  const { data: member } = await admin
    .from("business_members")
    .select("role")
    .eq("business_id", businessId)
    .ilike("user_email", emailPattern)
    .order("role")
    .limit(1)
    .maybeSingle();
  const role = member?.role as string | undefined;
  const allowed = plan.kind === "global" ? role === "OWNER" : role === "OWNER" || role === "ADMIN";
  if (!allowed) return json({ error: "not_allowed" }, 403);

  // Pro Servicios trae todo Pro: con Pro Servicios vigente no se compra Pro encima
  // (se pagaría algo que ya tiene y empezaría cuando venza Pro Servicios). 24 nov.
  if (plan.kind === "business" && !slotsOnly) {
    const { data: pro } = await admin.rpc("business_pro_until", { p_business_id: businessId });
    if ((pro as { services?: boolean } | null)?.services === true) {
      return json({ error: "included_in_plan" }, 409);
    }
  }

  const { data: setting } = await admin.from("pro_settings").select("value").eq("key", "wompi_public_key").maybeSingle();
  const publicKey = (setting?.value as string | null)?.trim();
  if (!publicKey) return json({ error: "payments_not_configured" }, 503);
  // Con la llave de pruebas (sandbox) solo pagan los administradores: un pago de
  // prueba no mueve plata real y cualquiera tendría Pro gratis
  if (publicKey.startsWith("pub_test_")) {
    const { data: isAdmin } = await admin.from("app_admins").select("email").ilike("email", emailPattern).maybeSingle();
    if (!isAdmin) return json({ error: "payments_not_configured" }, 503);
  }

  // Cupón de descuento (0.16.0): el servidor lo revisa y fija el precio
  const coupon = typeof body.coupon === "string" ? body.coupon.trim().toUpperCase() : "";
  let price = Number(plan.price);
  let couponCode: string | null = null;
  if (coupon && !slotsOnly) {
    const { data: quote, error: couponError } = await admin.rpc("pro_coupon_price", {
      p_code: coupon,
      p_plan_id: plan.id,
      p_email: email,
    });
    if (couponError) {
      const reason = /coupon_[a-z_]+/.exec(couponError.message)?.[0] ?? "coupon_not_found";
      return json({ error: reason }, 400);
    }
    price = Number((quote as { price: number }).price);
    couponCode = (quote as { code: string }).code;
  }

  // Subida a Pro Servicios: descuento por lo que le queda de Pro pagado
  let upgradeCredit = 0;
  let upgradeSubs: string[] = [];
  if (body.upgrade === true && plan.kind === "services" && !slotsOnly) {
    const { data: up, error: upError } = await admin.rpc("pro_upgrade_quote", {
      p_business_id: businessId,
      p_plan_id: plan.id,
    });
    if (upError) {
      console.error("pro-checkout upgrade", upError.message);
      return json({ error: "server_error" }, 500);
    }
    const u = up as { ok: boolean; error?: string; credit?: number; subs?: string[] };
    if (!u?.ok) return json({ error: u?.error ?? "server_error" }, 409);
    upgradeCredit = Number(u.credit ?? 0);
    upgradeSubs = u.subs ?? [];
    if (upgradeCredit > 0 && couponCode) return json({ error: "upgrade_no_coupon" }, 400);
    price -= upgradeCredit;
  }

  const slotAmount = Number(quote?.amount ?? 0);
  const amountInCents = Math.round((price + slotAmount) * 100);
  if (amountInCents <= 0) return json({ error: "bad_request" }, 400);
  const reference = `STK-${crypto.randomUUID().replaceAll("-", "").slice(0, 16).toUpperCase()}`;

  const { error: insertError } = await admin.from("pro_payments").insert({
    reference,
    business_id: businessId,
    kind: plan.kind,
    plan_id: plan.id,
    period: plan.period,
    amount_in_cents: amountInCents,
    currency: "COP",
    user_email: email,
    coupon_code: couponCode,
    regular_amount_in_cents: couponCode || upgradeCredit > 0 ? Math.round((Number(plan.price) + slotAmount) * 100) : null,
    branch_slots: slots,
    slot_gap: Number(quote?.gap ?? 0),
    slots_ends_at: slotsOnly ? quote!.ends_at : null,
    slot_amount_in_cents: slots > 0 ? Math.round(slotAmount * 100) : null,
    upgrade_credit_in_cents: upgradeCredit > 0 ? Math.round(upgradeCredit * 100) : null,
    upgrade_subs: upgradeCredit > 0 ? upgradeSubs : null,
  });
  if (insertError) {
    console.error("pro-checkout insert", insertError.message);
    return json({ error: "server_error" }, 500);
  }

  const signature = await sha256(`${reference}${amountInCents}COP${integritySecret}`);
  const params = new URLSearchParams({
    "public-key": publicKey,
    currency: "COP",
    "amount-in-cents": String(amountInCents),
    reference,
    "signature:integrity": signature,
    "redirect-url": body.platform === "web" ? REDIRECT_URL_WEB : REDIRECT_URL,
    "customer-data:email": email,
  });
  return json({ reference, url: `https://checkout.wompi.co/p/?${params.toString()}` });
});
