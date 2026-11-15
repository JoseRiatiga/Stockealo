// Stockealo · daily-backup (0.16.0, fase 5: copia diaria propia y verificada)
//
// Cada noche (pg_cron, 3 a. m. de Colombia) o a mano desde el panel:
//   1. Pide la lista de tablas a public.backup_tables().
//   2. Por cada tabla, public.backup_dump(tabla) le da todas las filas y cuántas son.
//   3. Guarda backups/<día>/<tabla>.json en el almacenamiento PRIVADO.
//   4. Verifica: vuelve a bajar el archivo y cuenta que tenga las mismas filas.
//   5. Anota el resultado en public.backup_runs y borra las copias de más de 14 días.
//
// Quién puede llamarla:
//   • pg_cron, con la cabecera x-backup-key (la clave vive en Vault y la revisa la base
//     con public.backup_key_ok; nunca está escrita en el código).
//   • Un administrador del panel con su token («Hacer copia ahora»).
//
// Variables provistas por Supabase: SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY

import { createClient } from "jsr:@supabase/supabase-js@2";

const BUCKET = "backups";
const KEEP_DAYS = 14;

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-backup-key",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

/// Día de hoy en Colombia: «2026-11-16»
function today(): string {
  const now = new Date(Date.now() - 5 * 60 * 60 * 1000);
  return now.toISOString().slice(0, 10);
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const url = Deno.env.get("SUPABASE_URL")!;
  const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  // ¿Quién llama? pg_cron con su clave, o un administrador del panel
  const key = req.headers.get("x-backup-key") ?? "";
  let allowed = false;
  let by = "cron";
  if (key) {
    const { data } = await admin.rpc("backup_key_ok", { p_key: key });
    allowed = data === true;
  } else {
    const asCaller = createClient(url, Deno.env.get("SUPABASE_ANON_KEY")!, {
      global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } },
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { error } = await asCaller.rpc("admin_backup_status");
    allowed = !error;
    by = "panel";
  }
  if (!allowed) return json({ error: "not_allowed" }, 403);

  const day = today();
  const started = new Date().toISOString();
  const counts: Record<string, number> = {};
  const problems: string[] = [];
  let bytes = 0;

  const { data: tables, error: tablesError } = await admin.rpc("backup_tables");
  if (tablesError || !Array.isArray(tables)) {
    await admin.from("backup_runs").insert({ day, started_at: started, finished_at: new Date().toISOString(), ok: false, by_who: by, error: "No se pudo leer la lista de tablas" });
    return json({ ok: false, error: "tables" }, 500);
  }

  for (const table of tables as string[]) {
    const { data: dump, error } = await admin.rpc("backup_dump", { p_table: table });
    if (error || !dump) {
      problems.push(`${table}: no se pudo leer`);
      continue;
    }
    const rows = (dump as { rows: unknown[]; count: number }).rows ?? [];
    const expected = (dump as { rows: unknown[]; count: number }).count ?? rows.length;
    const body = JSON.stringify(rows);
    const path = `${day}/${table}.json`;
    const up = await admin.storage.from(BUCKET).upload(path, new Blob([body], { type: "application/json" }), { upsert: true });
    if (up.error) {
      problems.push(`${table}: no se pudo guardar`);
      continue;
    }
    // Verificación: se baja otra vez y se cuentan las filas
    const down = await admin.storage.from(BUCKET).download(path);
    let saved = -1;
    try {
      saved = down.data ? (JSON.parse(await down.data.text()) as unknown[]).length : -1;
    } catch {
      saved = -1;
    }
    if (saved !== expected) problems.push(`${table}: guardó ${saved} de ${expected} filas`);
    counts[table] = expected;
    bytes += body.length;
  }

  // Las copias de más de 14 días sobran
  try {
    const { data: folders } = await admin.storage.from(BUCKET).list("", { limit: 100 });
    const limit = new Date(Date.now() - KEEP_DAYS * 24 * 60 * 60 * 1000).toISOString().slice(0, 10);
    for (const f of folders ?? []) {
      if (!/^\d{4}-\d{2}-\d{2}$/.test(f.name) || f.name >= limit) continue;
      const { data: files } = await admin.storage.from(BUCKET).list(f.name, { limit: 1000 });
      const paths = (files ?? []).map((x) => `${f.name}/${x.name}`);
      if (paths.length) await admin.storage.from(BUCKET).remove(paths);
    }
  } catch (_) {
    problems.push("no se pudieron borrar las copias viejas");
  }

  const ok = problems.length === 0;
  await admin.from("backup_runs").insert({
    day,
    started_at: started,
    finished_at: new Date().toISOString(),
    ok,
    by_who: by,
    tables: counts,
    bytes,
    error: ok ? null : problems.slice(0, 20).join(" · "),
  });
  return json({ ok, day, tables: Object.keys(counts).length, rows: Object.values(counts).reduce((s, n) => s + n, 0), bytes, problems });
});
