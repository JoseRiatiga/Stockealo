#!/usr/bin/env bash
# Revisión antes de publicar (24 nov): cada función que la web llama responde a la
# pregunta previa del navegador (CORS) con TODAS las cabeceras que manda la app.
# El 24 nov el pago, Stocky y otras fallaban en la web desde la 0.18.0 porque la app
# empezó a mandar x-stockealo-branches y las funciones no lo permitían.
#
# Uso: bash tool/check_cors.sh      (sale con 1 si alguna falla)
set -u
cd "$(dirname "$0")/.."
BASE="https://evdwwmkafwjyfawsufjb.supabase.co/functions/v1"
ORIGIN="https://stockealo.online"
# Las de siempre del cliente de Supabase + las propias de la app (lib/core/services/supabase_service.dart)
extra=$(grep -oE "'x-stockealo-[a-z-]+'" lib/core/services/supabase_service.dart | tr -d "'" | sort -u | paste -sd, -)
HEADERS="authorization,apikey,content-type,x-client-info${extra:+,$extra}"
# No se llaman desde el navegador: tareas programadas y el aviso de Wompi
SKIP="daily-backup storage-cleanup wompi-webhook"
fail=0
for dir in supabase/functions/*/; do
  fn=$(basename "$dir")
  [[ " $SKIP " == *" $fn "* ]] && continue
  [[ -f "$dir/index.ts" ]] || continue
  allowed=$(curl -s -i -X OPTIONS "$BASE/$fn" -H "Origin: $ORIGIN" \
    -H "Access-Control-Request-Method: POST" -H "Access-Control-Request-Headers: $HEADERS" \
    | tr -d '\r' | grep -i '^access-control-allow-headers:' | cut -d: -f2- | tr 'A-Z' 'a-z')
  missing=""
  IFS=, read -ra hs <<< "$HEADERS"
  for h in "${hs[@]}"; do
    [[ ",$(echo "$allowed" | tr -d ' ')," == *",$h,"* ]] || missing="$missing $h"
  done
  if [[ -z "$allowed" || -n "$missing" ]]; then
    echo "FALLA  $fn  (no permite:${missing:- ninguna respuesta})"
    fail=1
  else
    echo "OK     $fn"
  fi
done
exit $fail
