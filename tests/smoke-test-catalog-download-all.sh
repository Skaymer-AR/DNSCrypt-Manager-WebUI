#!/bin/bash
# Prueba aislada de límites ampliados y descarga global asíncrona.
set -u
cd "$(dirname "$0")/.." || exit 1
ROOT="$(pwd)"; SH="$(command -v sh)"
[ -n "$SH" ] || exit 99
TR="$(mktemp -d /tmp/dcm-download-all.XXXXXX)" || exit 99
export DNSCRYPT_TEST_MODE=1 DNSCRYPT_TEST_ROOT="$TR" \
  DNSCRYPT_TEST_DATA_DIR="$TR/data" DNSCRYPT_TEST_MODDIR="$TR/mod" \
  DNSCRYPT_TEST_FREE_KB=3000000 DNSCRYPT_TEST_CAT_CONCURRENCY_FILE="$TR/fx/concurrency" \
  DNSCRYPT_TEST_CAT_DELAY=1 DNSCRYPT_TEST_CAT_MANIFEST_COUNTER="$TR/fx/manifest-count"
mkdir -p "$TR/data/bin" "$TR/data/config" "$TR/mod/system/bin" "$TR/fx"
cp system/bin/dnscrypt-manager "$TR/mod/system/bin/"
mkdir -p "$TR/mod/scripts" "$TR/mod/config/catalog" "$TR/mod/config/blocklist-sources"
cp scripts/*.sh "$TR/mod/scripts/"
cp config/catalog/*.tsv "$TR/mod/config/catalog/"
cp config/blocklist-sources/*.src "$TR/mod/config/blocklist-sources/"
cp config/dnscrypt-proxy.toml "$TR/data/config/dnscrypt-proxy.toml"
cp tests/fixtures/fake-dnscrypt-proxy "$TR/data/bin/dnscrypt-proxy"
chmod 0755 "$TR/data/bin/dnscrypt-proxy"
M="$TR/mod/system/bin/dnscrypt-manager"; DATA="$TR/data"; FX="$TR/fx"
PASS=0; FAILN=0
ok(){ PASS=$((PASS+1)); printf '  OK   %s\n' "$1"; }
bad(){ FAILN=$((FAILN+1)); printf '  FAIL %s\n' "$1"; }
cleanup(){
  if [ -n "${WORKER:-}" ]; then kill "$WORKER" 2>/dev/null || :; fi
  if [ "${DCM_KEEP_TEST_TMP:-0}" = "1" ]; then echo "TEST TMP: $TR"; else rm -rf "$TR"; fi
}
trap cleanup EXIT INT TERM
cli(){ "$SH" "$M" "$@"; }
inlib(){ (cd "$TR/mod" && "$SH" -c '. scripts/common.sh 2>/dev/null; . scripts/security.sh 2>/dev/null; . scripts/catalog.sh 2>/dev/null; cat_sync_index >/dev/null; '"$1" ); }

echo "== Migración y límites por defecto =="
cli migrate >/dev/null 2>&1 || { echo "FATAL: migrate" >&2; exit 99; }
LIMITS=$(inlib 'printf "%s %s %s %s %s %s %s %s %s %s\n" "$SEC_MAX_DOMAINS" "$SEC_MAX_BLOCKED_DOMAINS" "$SEC_MAX_LIST_BYTES" "$CAT_MAX_SOURCE_DOMAINS" "$CAT_MAX_SOURCE_BYTES" "$CAT_MAX_ACTIVE_DOMAINS" "$CAT_MAX_ACTIVE_SOURCE_ENTRIES" "$CAT_MAX_ACTIVE_SOURCE_BYTES" "$CAT_DOWNLOAD_JOBS" "$CAT_DOWNLOAD_RESERVE_KB"')
[ "$LIMITS" = "5000000 5000000 268435456 5000000 268435456 5000000 10000000 1073741824 4 524288" ] \
  && ok "fuente/merge final: hasta 5 millones; feeds 256 MiB; caché activa 1 GiB" \
  || bad "límites por defecto inesperados: $LIMITS"
[ "$(inlib 'printf "%s %s\n" "$SEC_MAX_IMPORT_LINES" "$SEC_MAX_IMPORT_BYTES"')" = "5000 1048576" ] \
  && ok "el límite de 5.000 líneas queda acotado a importación de allowlist" \
  || bad "límite de importación allowlist"
inlib 'sec_init_dirs; sec_ensure_sources' >/dev/null 2>&1
ADS_SRC="$DATA/security/blocklists/sources.d/ads.src"
sed 's/^max_bytes=268435456$/max_bytes=26214400/' "$ADS_SRC" > "$FX/ads.old"
printf 'custom_note=preservar\n' >> "$FX/ads.old"
cp "$FX/ads.old" "$ADS_SRC"
inlib 'sec_ensure_sources' >/dev/null 2>&1
grep -qx 'max_bytes=268435456' "$ADS_SRC" && grep -qx 'custom_note=preservar' "$ADS_SRC" \
  && ok "upgrade eleva el tope de fábrica y conserva otros metadatos locales" \
  || bad "migración del límite legacy"

echo "== Catálogo pequeño de fixtures para el job real =="
awk -F '\t' -v OFS='\t' '
  /^#/ {print; next}
  $1=="rc1_urlhaus" {
    split("test_source_a test_source_b test_source_c test_source_d", ids, " ")
    for (i=1; i<=4; i++) {
      row=$0; n=split(row, f, "\t"); f[1]=ids[i]; f[7]="domains"
      f[8]="https://fixtures.invalid/" ids[i] ".txt"; f[10]="unverified"; f[27]="0"
      for (j=1; j<=n; j++) printf "%s%s", f[j], (j<n ? OFS : ORS)
    }
  }
' "$TR/mod/config/catalog/blocklists.index.tsv" > "$TR/index.small"
cp "$TR/index.small" "$TR/mod/config/catalog/blocklists.index.tsv"
cp "$TR/index.small" "$DATA/catalog/blocklists.index.tsv"
for i in $(seq 1 30); do printf 'feed%s.example.net\n' "$i"; done > "$FX/feed.txt"
export DNSCRYPT_TEST_CAT_BODY_FILE="$FX/feed.txt" DNSCRYPT_TEST_CAT_HTTP=200 DNSCRYPT_TEST_CAT_RC=0
mkdir -p "$DATA/security/active" "$DATA/catalog"
printf '%s\n' 'keep.active.example.net' > "$DATA/security/active/blocked-names.txt"
printf '%s\n' rc1_urlhaus > "$DATA/catalog/enabled.txt"
cp "$DATA/catalog/enabled.txt" "$FX/enabled.before"
 : > "$FX/manifest-count"
 : > "$FX/concurrency.active"
 : > "$FX/concurrency.max"
ACTIVE_SHA=$(sha256sum "$DATA/security/active/blocked-names.txt" | cut -d' ' -f1)
cat > "$FX/cli-wrapper" <<EOF
#!/bin/sh
exec "$SH" "$M" "\$@"
EOF
chmod 0755 "$FX/cli-wrapper"

# El dispatcher lanza el mismo worker que usa la WebUI, fuera del proceso que
# atiende ksu.exec; solo esta fixture local puede responder a sus descargas.
START=$(inlib "DCM_SELF='$FX/cli-wrapper'; export DCM_SELF; cat_download_all_start --confirmed")
printf '%s\n' "$START" | grep -q 'descarga global iniciada' \
  && ok "botón/CLI inician tarea de fondo con confirmación explícita" \
  || bad "inicio de descarga global: $START"

_state=queued; _tries=0
while [ "$_tries" -lt 100 ]; do
  STATUS=$(cli catalog download-all status --json 2>/dev/null)
  _state=$(printf '%s' "$STATUS" | python3 -c 'import json,sys; print(json.load(sys.stdin)["state"])' 2>/dev/null || printf 'invalid')
  case "$_state" in done|partial) break ;; esac
  _tries=$((_tries + 1)); sleep 0.1
done
printf '%s' "$STATUS" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["state"]=="done" and d["total"]==4 and d["success"]==4 and d["failed"]==0 and d["skipped"]==0' >/dev/null 2>&1 \
  && ok "job descarga/verifica todas las fuentes elegibles y publica progreso JSON" \
  || bad "estado final inesperado: $STATUS"
for ID in test_source_a test_source_b test_source_c test_source_d; do
  [ "$(wc -l < "$DATA/catalog/cache/$ID.list" | tr -d ' ')" = 30 ] || break
done
[ "${ID:-}" = test_source_d ] && ok "las cuatro listas quedan normalizadas en caché" || bad "faltan listas cacheadas"
[ "$(cat "$FX/concurrency.max")" -ge 2 ] && [ "$(cat "$FX/concurrency.max")" -le 4 ] \
  && ok "la descarga paraleliza hasta cuatro feeds sin exceder el límite" \
  || bad "descargas no solapadas o límite de concurrencia excedido: $(cat "$FX/concurrency.max")"
[ "$(wc -l < "$FX/manifest-count" | tr -d ' ')" = 1 ] \
  && ok "el manifiesto se reconstruye una sola vez al final del lote" \
  || bad "manifiesto reconstruido repetidamente durante el lote"
cmp -s "$FX/enabled.before" "$DATA/catalog/enabled.txt" \
  && [ "$ACTIVE_SHA" = "$(sha256sum "$DATA/security/active/blocked-names.txt" | cut -d' ' -f1)" ] \
  && ok "descargar todas no activa fuentes ni modifica bloqueos DNS vigentes" \
  || bad "la descarga global cambió el estado activo"

mkdir -p "$DATA/catalog/download-all.lock"
inlib 'cat_download_job_write queued guard-test 0 2 0 0 0 preparando' >/dev/null 2>&1
if cli catalog compile > "$FX/compile-during-download.log" 2>&1; then
  bad "compilación concurrente fue aceptada"
else
  grep -q 'mientras la descarga global modifica cachés' "$FX/compile-during-download.log" \
    && ok "la compilación concurrente se rechaza hasta completar las cachés" \
    || bad "faltó mensaje claro de exclusión mutua"
fi
rm -rf "$DATA/catalog/download-all.lock"

echo ""
echo "Resumen download-all: $PASS OK, $FAILN FAIL"
[ "$FAILN" = 0 ]
