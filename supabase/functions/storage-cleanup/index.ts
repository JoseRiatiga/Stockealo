// Stockealo · storage-cleanup (0.13.4)
//
// Limpieza única de archivos que ya no usa nadie, desde el panel admin.
//   { "action": "count" }  → { count, bytes }            (no borra nada)
//   { "action": "delete" } → { deleted, bytes }          (borra lo que cuenta "count")
//
// Quién es huérfano lo decide la base con public.admin_orphan_files(), llamada con el
// token de quien pide: si no es administrador de la app, la base lo rechaza. La lista
// de archivos nunca sale del cuerpo de la petición.
//
// Variables provistas por Supabase: SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY

import { createClient } from "jsr:@supabase/supabase-js@2";

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

type Orphans = { count: number; bytes: number; files: { bucket: string; name: string }[] };

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const authHeader = req.headers.get("Authorization") ?? "";
  const asCaller = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_ANON_KEY")!, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false, autoRefreshToken: false },
  });

  // La base revisa que sea administrador de la app
  const { data, error } = await asCaller.rpc("admin_orphan_files");
  if (error) return json({ error: error.message.includes("not_admin") ? "not_admin" : "lookup_failed" }, 403);
  const orphans = data as Orphans;

  let action = "count";
  try {
    action = (await req.json())?.action ?? "count";
  } catch (_) {
    // sin cuerpo: solo contar
  }
  if (action !== "delete") return json({ count: orphans.count, bytes: orphans.bytes });

  const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  let deleted = 0;
  for (const bucket of ["product-images", "purchase-invoices"]) {
    const names = orphans.files.filter((f) => f.bucket === bucket).map((f) => f.name);
    for (let i = 0; i < names.length; i += 500) {
      const chunk = names.slice(i, i + 500);
      const { error: removeError } = await admin.storage.from(bucket).remove(chunk);
      if (removeError) return json({ error: "delete_failed", deleted }, 500);
      deleted += chunk.length;
    }
  }
  return json({ deleted, bytes: orphans.bytes });
});
