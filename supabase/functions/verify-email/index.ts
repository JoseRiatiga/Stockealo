// Stockealo · verify-email (0.18.4, registro sin código)
//
// Saca la cuenta de public.unverified_accounts cuando la sesión prueba el correo. La
// nube lo revisa con lo que guardó Supabase al iniciar la sesión (no basta con que la
// app lo diga):
//   * otp   → entró con el código del correo (aviso «Verifica tu correo», recuperar la
//             contraseña o el registro con código).
//   * oauth → entró con Google, que ya probó el correo. Como Google se une a la cuenta
//             que tenga ese correo, la contraseña que tenía se borra: si alguien había
//             registrado el correo de otra persona, deja de servirle.
// En los dos casos se cierran las otras sesiones de la cuenta.
//
// La app la llama después de verificar el código (en recuperar la contraseña, después
// de guardar la nueva) y al entrar con Google. Si la cuenta ya estaba verificada no
// hace nada.
//
// Variables provistas por Supabase: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY

import { createClient } from "jsr:@supabase/supabase-js@2";

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

function jwtPayload(jwt: string): Record<string, unknown> {
  try {
    const part = jwt.split(".")[1].replace(/-/g, "+").replace(/_/g, "/");
    return JSON.parse(atob(part.padEnd(part.length + ((4 - (part.length % 4)) % 4), "=")));
  } catch {
    return {};
  }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const jwt = req.headers.get("Authorization")?.replace(/^Bearer\s+/i, "") ?? "";
  if (!jwt) return json({ error: "unauthorized" }, 401);

  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false, autoRefreshToken: false } },
  );

  // getUser valida el token con Supabase (firma, vencimiento y sesión viva)
  const { data: userData, error: userError } = await admin.auth.getUser(jwt);
  const user = userData?.user;
  if (userError || !user) return json({ error: "unauthorized" }, 401);

  const { data: row, error: rowError } = await admin
    .from("unverified_accounts")
    .select("user_id")
    .eq("user_id", user.id)
    .maybeSingle();
  if (rowError) return json({ error: "server_error" }, 500);
  if (!row) return json({ verified: true });

  const sessionId = String(jwtPayload(jwt).session_id ?? "");
  if (!sessionId) return json({ verified: false });
  const { data: methods, error: methodsError } = await admin.rpc("_session_methods", {
    p_user: user.id,
    p_session: sessionId,
  });
  if (methodsError) return json({ error: "server_error" }, 500);
  const list: string[] = Array.isArray(methods) ? methods.map(String) : [];

  const byCode = list.includes("otp");
  const byGoogle = !byCode && list.includes("oauth");
  if (!byCode && !byGoogle) return json({ verified: false });

  if (byGoogle) {
    // Contraseña al azar que nadie conoce: ya no entra quien no sea el dueño del correo
    const random = Array.from(crypto.getRandomValues(new Uint8Array(32)))
      .map((b) => b.toString(16).padStart(2, "0")).join("");
    const { error } = await admin.auth.admin.updateUserById(user.id, { password: random });
    if (error) return json({ error: "server_error" }, 500);
  }

  // Cierra las demás sesiones (las de quien hubiera registrado el correo)
  try {
    await admin.auth.admin.signOut(jwt, "others");
  } catch (_) {
    // Si falla, igual queda verificada: la contraseña ya cambió o es del dueño
  }

  const { error: deleteError } = await admin.from("unverified_accounts").delete().eq("user_id", user.id);
  if (deleteError) return json({ error: "server_error" }, 500);
  return json({ verified: true, password_cleared: byGoogle });
});
