// Stockealo · delete-account
//
// Elimina por completo la cuenta que llama (identificada por su JWT):
//   1. Los negocios donde es el único OWNER, con sus fotos en Storage (las tablas
//      hijas caen por ON DELETE CASCADE).
//   2. Sus membresías en negocios ajenos.
//   3. Su perfil en public.users.
//   4. Su usuario de Supabase Auth.
//
// La app solo puede borrar su propia cuenta: el id y el correo salen del token,
// nunca del cuerpo de la petición.
//
// Variables provistas por Supabase: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY

import { createClient } from "jsr:@supabase/supabase-js@2";

const BUCKET = "product-images";

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

  const jwt = req.headers.get("Authorization")?.replace(/^Bearer\s+/i, "") ?? "";
  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false, autoRefreshToken: false } },
  );

  const { data: auth, error: authError } = await admin.auth.getUser(jwt);
  const email = auth?.user?.email?.toLowerCase();
  if (authError || !auth?.user || !email) return json({ error: "not_authenticated" }, 401);
  // Comparación sin mayúsculas, pero literal: "_" y "%" no deben actuar como comodines
  const emailPattern = email.replace(/[\\%_]/g, (c) => "\\" + c);

  // 1. Negocios donde es dueño único
  const { data: owned, error: ownedError } = await admin
    .from("business_members")
    .select("business_id")
    .ilike("user_email", emailPattern)
    .eq("role", "OWNER");
  if (ownedError) return json({ error: "lookup_failed" }, 500);

  for (const { business_id: businessId } of owned ?? []) {
    const { count } = await admin
      .from("business_members")
      .select("id", { count: "exact", head: true })
      .eq("business_id", businessId)
      .eq("role", "OWNER")
      .not("user_email", "ilike", emailPattern);
    if ((count ?? 0) > 0) continue; // otro dueño conserva el negocio

    await removeBusinessImages(admin, businessId);
    const { error } = await admin.from("businesses").delete().eq("id", businessId);
    if (error) return json({ error: "business_delete_failed" }, 500);
  }

  // 2 y 3. Membresías restantes y perfil
  const { error: membersError } = await admin.from("business_members").delete().ilike("user_email", emailPattern);
  const { error: profileError } = await admin.from("users").delete().ilike("email", emailPattern);
  if (membersError || profileError) return json({ error: "profile_delete_failed" }, 500);

  // 4. Usuario de Auth (al final: si algo falla antes, la cuenta sigue usable para reintentar)
  const { error: deleteError } = await admin.auth.admin.deleteUser(auth.user.id);
  if (deleteError) return json({ error: "auth_delete_failed" }, 500);

  return json({ deleted: true });
});

// deno-lint-ignore no-explicit-any
async function removeBusinessImages(admin: any, businessId: string): Promise<void> {
  for (;;) {
    const { data: files, error } = await admin.storage.from(BUCKET).list(businessId, { limit: 1000 });
    if (error || !files?.length) return;
    // deno-lint-ignore no-explicit-any
    const paths = files.map((f: any) => `${businessId}/${f.name}`);
    const { error: removeError } = await admin.storage.from(BUCKET).remove(paths);
    if (removeError || files.length < 1000) return;
  }
}
