// Stockealo · register-account (0.18.4, registro sin código)
//
// Crea la cuenta sin pedir el código del correo, para que quien solo quiere probar la
// app entre de una vez. La cuenta queda en public.unverified_accounts hasta que pruebe
// su correo (verify-email). Mientras tanto la nube no le da nada por correo: ni
// invitaciones ni acceso de administrador (reglas de la migración 20261213000000).
//
// Si el correo ya tiene cuenta o algo le corresponde (invitación, perfil, plan, pago,
// cupón, administrador), responde { mode: "code" } y la app sigue con el registro con
// código de siempre. Solo hay dos respuestas, "created" o "code", para no decir de
// forma directa qué correos tienen cuenta.
//
// Límite: 5 intentos por hora desde la misma conexión.
// Variables provistas por Supabase: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY

import { createClient } from "jsr:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-stockealo-branches",
};

const MAX_PER_HOUR = 5;

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

function clientIp(req: Request): string {
  const fwd = req.headers.get("x-forwarded-for")?.split(",")[0]?.trim();
  return fwd || req.headers.get("cf-connecting-ip") || req.headers.get("x-real-ip") || "desconocida";
}

function isPasswordError(code?: string, message?: string): boolean {
  const msg = `${code ?? ""} ${message ?? ""}`.toLowerCase();
  return msg.includes("weak_password") || msg.includes("password should");
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  let email: string, password: string, name: string | null, phone: string | null;
  try {
    const body = await req.json();
    email = String(body.email ?? "").trim().toLowerCase();
    password = String(body.password ?? "");
    name = body.name ? String(body.name).trim().slice(0, 120) : null;
    phone = body.phone ? String(body.phone).trim().slice(0, 40) : null;
  } catch {
    return json({ error: "invalid_body" }, 400);
  }
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) || email.length > 254) return json({ error: "invalid_email" }, 400);
  if (password.length < 6 || password.length > 72) return json({ error: "weak_password" }, 400);

  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false, autoRefreshToken: false } },
  );

  // Límite por conexión (se guarda la huella de la IP, no la IP)
  const ipHash = await sha256("stockealo-register:" + clientIp(req));
  const since = new Date(Date.now() - 3600_000).toISOString();
  const { count, error: countError } = await admin
    .from("register_attempts")
    .select("id", { count: "exact", head: true })
    .eq("ip_hash", ipHash)
    .gte("at", since);
  if (countError) return json({ error: "server_error" }, 500);
  if ((count ?? 0) >= MAX_PER_HOUR) return json({ error: "rate_limited" }, 429);
  await admin.from("register_attempts").insert({ ip_hash: ipHash });
  // Limpieza de vez en cuando: los intentos de hace más de un día ya no cuentan
  if (Math.random() < 0.05) {
    await admin.from("register_attempts").delete().lt("at", new Date(Date.now() - 86400_000).toISOString());
  }

  const { data: check, error: checkError } = await admin.rpc("_register_check", { p_email: email });
  if (checkError) return json({ error: "server_error" }, 500);
  const verdict = String(check ?? "code");
  const metadata = { name, phone };

  if (verdict === "new") {
    const { data: created, error } = await admin.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
      user_metadata: metadata,
    });
    if (error || !created?.user) {
      if (isPasswordError(error?.code, error?.message)) return json({ error: "weak_password" }, 400);
      // Otro registro del mismo correo ganó la carrera: que siga con código
      return json({ mode: "code" });
    }
    // La marca se pone con la llave del correo y revisando otra vez (Codex, 24 nov)
    const { data: marked, error: rowError } = await admin.rpc("_register_mark", {
      p_user: created.user.id,
      p_email: email,
    });
    if (rowError || marked !== true) {
      // Nunca dejar una cuenta confirmada sin su marca de «sin verificar»
      await admin.auth.admin.deleteUser(created.user.id);
      return rowError ? json({ error: "server_error" }, 500) : json({ mode: "code" });
    }
    return json({ mode: "created" });
  }

  if (verdict.startsWith("reuse:")) {
    const id = verdict.slice("reuse:".length);
    // Primero la marca, después la confirmación
    const { data: marked, error: rowError } = await admin.rpc("_register_mark", { p_user: id, p_email: email });
    if (rowError) return json({ error: "server_error" }, 500);
    if (marked !== true) return json({ mode: "code" });
    const { error } = await admin.auth.admin.updateUserById(id, {
      password,
      email_confirm: true,
      user_metadata: metadata,
    });
    if (error) {
      await admin.from("unverified_accounts").delete().eq("user_id", id);
      if (isPasswordError(error.code, error.message)) return json({ error: "weak_password" }, 400);
      return json({ error: "server_error" }, 500);
    }
    return json({ mode: "created" });
  }

  return json({ mode: "code" });
});
