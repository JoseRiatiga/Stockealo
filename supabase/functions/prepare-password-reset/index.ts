// Stockealo · prepare-password-reset
//
// La app pide el código de recuperación con shouldCreateUser: false, para que
// "Recuperar clave" no cree cuentas de Auth para cualquier correo. Las cuentas
// creadas antes de la Fase 1 tienen perfil en public.users pero quizá aún no
// tienen usuario en Supabase Auth; esta función se lo crea (sin contraseña)
// solo si el correo ya tiene perfil, para que el código pueda enviarse.
//
// Responde siempre { ok: true }, exista o no la cuenta, para no revelar qué
// correos están registrados.
//
// Variables provistas por Supabase: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY

import { createClient } from "jsr:@supabase/supabase-js@2";

const OK = { ok: true };

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

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  let email: string;
  try {
    const body = await req.json();
    email = String(body.email ?? "").trim().toLowerCase();
  } catch {
    return json({ error: "invalid_body" }, 400);
  }
  if (!email.includes("@")) return json(OK);

  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false, autoRefreshToken: false } },
  );

  // Comparación sin mayúsculas, pero literal: "_" y "%" no deben actuar como comodines
  const emailPattern = email.replace(/[\\%_]/g, (c) => "\\" + c);
  const { data: profile } = await admin
    .from("users")
    .select("id, name")
    .ilike("email", emailPattern)
    .limit(1)
    .maybeSingle();
  if (!profile) return json(OK);

  // Si el usuario de Auth ya existe, createUser falla y no hay nada que hacer
  await admin.auth.admin.createUser({
    email,
    email_confirm: true,
    user_metadata: { name: profile.name, app_user_id: profile.id },
  });
  return json(OK);
});
