// Stockealo · legacy-login
//
// Traslada a Supabase Auth las cuentas creadas antes de la Fase 1, cuya contraseña
// vive como hash SHA-256 propio en public.users.password.
//
// La app llama a esta función solo cuando signInWithPassword falla. Si el hash
// antiguo coincide, se crea (o actualiza) el usuario de Supabase Auth con esa misma
// contraseña y se retira el hash. La app vuelve a llamar a signInWithPassword.
//
// Variables provistas por Supabase: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY
//
// Cuando no quede ningún hash de 64 hex en public.users, esta función se puede borrar.

import { createClient } from "jsr:@supabase/supabase-js@2";

// Pepper del antiguo HashHelper (lib/core/utils/hash_helper.dart). No es secreto:
// viajó dentro de cada APK y está en el historial de git. Solo sirve para
// reproducir los hashes antiguos.
const LEGACY_PEPPER = "stockealo_sec_pepper_v1_#92@!";
const AUTH_MANAGED = "SUPABASE_AUTH";
const NOT_MIGRATED = { migrated: false };

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

async function legacyHash(password: string, pepper: string): Promise<string> {
  const bytes = new TextEncoder().encode(`${password}:${pepper}`);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(digest)).map((b) => b.toString(16).padStart(2, "0")).join("");
}

function safeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  let email: string;
  let password: string;
  try {
    const body = await req.json();
    email = String(body.email ?? "").trim().toLowerCase();
    password = String(body.password ?? "");
  } catch {
    return json({ error: "invalid_body" }, 400);
  }
  if (!email.includes("@") || password.length === 0) return json(NOT_MIGRATED);

  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false, autoRefreshToken: false } },
  );

  const { data: profile } = await admin
    .from("users")
    .select("id, name, password")
    .eq("email", email)
    .maybeSingle();

  const stored = profile?.password as string | undefined;
  // Solo hashes SHA-256 antiguos (64 hex); los marcadores no son migrables
  if (!profile || !stored || !/^[0-9a-f]{64}$/.test(stored)) return json(NOT_MIGRATED);
  if (!safeEqual(await legacyHash(password, LEGACY_PEPPER), stored)) return json(NOT_MIGRATED);

  // Crear el usuario de Auth, o fijar su contraseña si ya existía (p. ej. por un OTP)
  const { error: createError } = await admin.auth.admin.createUser({
    email,
    password,
    email_confirm: true,
    user_metadata: { name: profile.name, app_user_id: profile.id },
  });

  if (createError) {
    const existing = await findAuthUserIdByEmail(admin, email);
    if (!existing) return json({ error: "auth_create_failed" }, 500);
    const { error: updateError } = await admin.auth.admin.updateUserById(existing, {
      password,
      email_confirm: true,
    });
    if (updateError) return json({ error: "auth_update_failed" }, 500);
  }

  await admin.from("users").update({ password: AUTH_MANAGED }).eq("id", profile.id);
  return json({ migrated: true });
});

// deno-lint-ignore no-explicit-any
async function findAuthUserIdByEmail(admin: any, email: string): Promise<string | null> {
  for (let page = 1; page <= 50; page++) {
    const { data, error } = await admin.auth.admin.listUsers({ page, perPage: 200 });
    if (error || !data?.users?.length) return null;
    // deno-lint-ignore no-explicit-any
    const match = data.users.find((u: any) => u.email?.toLowerCase() === email);
    if (match) return match.id;
    if (data.users.length < 200) return null;
  }
  return null;
}
