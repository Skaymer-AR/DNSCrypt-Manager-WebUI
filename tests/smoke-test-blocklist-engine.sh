#!/bin/bash
# Cadena determinista de fuentes DNS con fixtures locales; no usa upstreams.
set -u
cd "$(dirname "$0")/.." || exit 1
ROOT="$(pwd)"; SH="$(command -v sh)"; PY="$(command -v python3)"
[ -n "$SH" ] && [ -n "$PY" ] || exit 99
TR="$(mktemp -d /tmp/dcm-blocklist-engine.XXXXXX)" || exit 99
export DNSCRYPT_TEST_MODE=1 DNSCRYPT_TEST_ROOT="$TR" DNSCRYPT_TEST_DATA_DIR="$TR/data" DNSCRYPT_TEST_MODDIR="$TR/mod"
mkdir -p "$TR/data/bin" "$TR/data/config" "$TR/mod/system/bin" "$TR/mod/scripts" "$TR/mod/config/catalog" "$TR/fx"
cp system/bin/dnscrypt-manager "$TR/mod/system/bin/"
cp scripts/*.sh "$TR/mod/scripts/"
cp config/catalog/*.tsv "$TR/mod/config/catalog/"
cp config/dnscrypt-proxy.toml "$TR/data/config/dnscrypt-proxy.toml"
cp tests/fixtures/fake-dnscrypt-proxy "$TR/data/bin/dnscrypt-proxy"
chmod 0755 "$TR/data/bin/dnscrypt-proxy"
M="$TR/mod/system/bin/dnscrypt-manager"; DATA="$TR/data"; FX="$TR/fx"
PASS=0; FAILN=0
ok(){ PASS=$((PASS+1)); printf '  OK   %s\n' "$1"; }
bad(){ FAILN=$((FAILN+1)); printf '  FAIL %s\n' "$1"; }
cleanup(){ if [ "${DCM_KEEP_TEST_TMP:-0}" = "1" ]; then echo "TEST TMP: $TR"; else rm -rf "$TR"; fi; }
trap cleanup EXIT INT TERM
cli(){ "$SH" "$M" "$@"; }
inlib(){ (cd "$TR/mod" && "$SH" -c ". scripts/common.sh 2>/dev/null; . scripts/security.sh 2>/dev/null; . scripts/catalog.sh 2>/dev/null; cat_sync_index >/dev/null; $1"); }
cli migrate >/dev/null 2>&1 || { echo "FATAL: migrate" >&2; exit 99; }

echo "== Parser y normalización =="
cat > "$FX/domains.txt" <<'EOF'
# comentario
Ads.Example.NET
0.0.0.0 host.example.net
127.0.0.1 LOCAL.example.net
*.wild.example.net
foo.example.net # inline comment
localhost
localhost.localdomain
1.2.3.4
co.uk
com
https://bad.example/path
münich.example
xn--mnich-kva.example
EOF
inlib "sec_parse_domains '$FX/domains.txt' domains '$FX/domains.out' >/dev/null; cat '$FX/domains.out'" > "$FX/out"
grep -qx 'ads.example.net' "$FX/out" && grep -qx 'wild.example.net' "$FX/out" && grep -qx 'xn--mnich-kva.example' "$FX/out" && ok "domains: lowercase, wildcard DNSCrypt y Punycode" || bad "domains normalization"
if grep -Eq 'localhost|1\.2\.3\.4|co\.uk|^com$|https:|münich' "$FX/out"; then bad "domains inválidos/anchos/Unicode"; else ok "descarta localhost, IP, sufijo amplio, URL y Unicode"; fi
cat > "$FX/hosts.txt" <<'EOF'
0.0.0.0 one.example.net two.example.net
127.0.0.1 three.example.net
192.168.1.1 ignored.example.net
::1 four.example.net
EOF
inlib "sec_parse_domains '$FX/hosts.txt' hosts '$FX/hosts.out' >/dev/null; cat '$FX/hosts.out'" > "$FX/out"
[ "$(wc -l < "$FX/out" | tr -d ' ')" = 3 ] && grep -qx one.example.net "$FX/out" && grep -qx four.example.net "$FX/out" && ok "hosts: loopbacks válidos, IP de red ignorada" || bad "hosts parsing"
cat > "$FX/adblock.txt" <<'EOF'
! lista
||tracker.example.net^
@@||permit.example.net^
bad.example.net##.ad
||path.example.net/ads^
||option.example.net^$third-party
||simple.example.net^
EOF
inlib "cat_abp_extract '$FX/adblock.txt' '$FX/abp.out' >/dev/null; cat '$FX/abp.out'" > "$FX/out"
[ "$(wc -l < "$FX/out" | tr -d ' ')" = 2 ] && grep -qx tracker.example.net "$FX/out" && grep -qx simple.example.net "$FX/out" && ok "ABP simple: solo reglas de dominio convertibles" || bad "ABP conversion"

echo "== Caché, conteos anómalos, licencias y errores HTTP =="
awk -F'\t' -v OFS='\t' '$1=="rc1_urlhaus"{$7="domains";$8="https://fixtures.invalid/urlhaus.txt"}1' "$TR/mod/config/catalog/blocklists.index.tsv" > "$TR/index.new"
mv "$TR/index.new" "$TR/mod/config/catalog/blocklists.index.tsv"
for i in $(seq 0 29); do printf 'a%s.example.net\n' "$i"; done > "$FX/feed-a.txt"
export DNSCRYPT_TEST_CAT_BODY_FILE="$FX/feed-a.txt" DNSCRYPT_TEST_CAT_HTTP=200 DNSCRYPT_TEST_CAT_RC=0
inlib "cat_update_one rc1_urlhaus" > "$FX/update-a.log" 2>&1 && grep -q 'OK (rc1_urlhaus): 30 dominios' "$FX/update-a.log" && ok "PREPARE descarga/parsing de 30 dominios" || bad "initial update"
SHA30=$(sha256sum "$DATA/catalog/cache/rc1_urlhaus.list" | cut -d' ' -f1)
python3 - "$DATA/catalog/blocklists-manifest.json" "$SHA30" <<'PY'
import json,sys
d=json.load(open(sys.argv[1],encoding='utf-8')); s=next(x for x in d['sources'] if x['id']=='rc1_urlhaus')
assert s['valid_domains']==30 and s['cached_domains']==30 and s['normalized_sha256']==sys.argv[2]
assert s['revision'] is None and s['last_success']>0
PY
[ "$?" = 0 ] && ok "manifest JSON contiene URL, conteos, hash y timestamp" || bad "manifest JSON"
cp "$DATA/catalog/cache/rc1_urlhaus.list" "$FX/cache30.list"
for i in $(seq 0 13); do printf 'bad%s.example.net\n' "$i"; done > "$FX/feed-small.txt"
export DNSCRYPT_TEST_CAT_BODY_FILE="$FX/feed-small.txt"
inlib "cat_update_one rc1_urlhaus" > "$FX/drop.log" 2>&1 && bad "caída 30->14 aceptada" || grep -q 'caída anómala' "$FX/drop.log" && ok "caída brusca rechazada" || bad "drop guard"
cmp -s "$FX/cache30.list" "$DATA/catalog/cache/rc1_urlhaus.list" && ok "caída conserva la última caché válida" || bad "drop cache changed"
for i in $(seq 0 59); do printf 'a%s.example.net\n' "$i"; done > "$FX/feed-a60.txt"
export DNSCRYPT_TEST_CAT_BODY_FILE="$FX/feed-a60.txt"
inlib "cat_update_one rc1_urlhaus" >/dev/null 2>&1 && [ "$(wc -l < "$DATA/catalog/cache/rc1_urlhaus.list" | tr -d ' ')" = 60 ] && [ "$(wc -l < "$DATA/catalog/cache/rc1_urlhaus.list.prev" | tr -d ' ')" = 30 ] && ok "acepta crecimiento y conserva .prev" || bad "cache backup"
inlib "cat_rollback_one rc1_urlhaus" > "$FX/rollback.log" 2>&1 && [ "$(wc -l < "$DATA/catalog/cache/rc1_urlhaus.list" | tr -d ' ')" = 30 ] && ok "ROLLBACK fuente restaura caché previa" || bad "source rollback"
inlib "cat_update_one rc1_urlhaus" >/dev/null 2>&1 || bad "re-update source A"
cp "$DATA/catalog/cache/rc1_urlhaus.list" "$FX/cache60-before-metadata-failure.list"
cp "$FX/feed-a60.txt" "$FX/feed-a61-meta.txt"; printf 'new.example.net\n' >> "$FX/feed-a61-meta.txt"
export DNSCRYPT_TEST_CAT_BODY_FILE="$FX/feed-a61-meta.txt"
if inlib "cat_success_write(){ : > \"\$CAT_SUCCESS\"; return 1; }; cat_update_one rc1_urlhaus" > "$FX/metadata-fail.log" 2>&1; then
  bad "falla de metadata aceptada"
else
  cmp -s "$FX/cache60-before-metadata-failure.list" "$DATA/catalog/cache/rc1_urlhaus.list" \
    && [ "$(grep '^rc1_urlhaus' "$DATA/catalog/source-success.tsv" | cut -f7)" = 60 ] \
    && ok "fallo de metadata conserva caché y conteos anteriores" \
    || bad "metadata cache rollback"
fi

for i in $(seq 15 44); do printf 'a%s.example.net\n' "$i"; done > "$FX/feed-b.txt"
awk -F'\t' -v OFS='\t' '$1=="hagezi_multi_pro"{$7="domains";$8="https://fixtures.invalid/hagezi-pro.txt"}1' "$TR/mod/config/catalog/blocklists.index.tsv" > "$TR/index.new"
mv "$TR/index.new" "$TR/mod/config/catalog/blocklists.index.tsv"
export DNSCRYPT_TEST_CAT_BODY_FILE="$FX/feed-b.txt"
inlib "cat_update_one hagezi_multi_pro" > "$FX/update-b.log" 2>&1 && ok "fuente HaGeZi descargada a caché aislada" || bad "source B update"
inlib "cat_enable rc1_urlhaus; cat_enable hagezi_multi_pro; cat_stats_compute" >/dev/null 2>&1
grep -q '#summary.*total_unique.*60' "$DATA/catalog/contribution-stats.tsv" && ok "dos fuentes: 90 líneas, 60 dominios únicos" || bad "dedup stats"
inlib "cat_provenance_generate" >/dev/null 2>&1
grep -q $'a20.example.net\trc1_urlhaus\t' "$DATA/catalog/source-provenance.tsv" && grep -q $'a20.example.net\thagezi_multi_pro\t' "$DATA/catalog/source-provenance.tsv" && ok "provenance conserva ambas fuentes para dominios duplicados" || bad "source provenance"
if inlib "CAT_MAX_ACTIVE_DOMAINS=59; cat_validate_active_limit" > "$FX/active-limit.log" 2>&1; then
  bad "limite de union activa ignorado"
else
  grep -q 'contiene 60 dominios únicos' "$FX/active-limit.log" && ok "límite detecta una unión mayor que el presupuesto" || bad "active catalog limit"
fi
if inlib "CAT_MAX_ACTIVE_SOURCE_ENTRIES=89; cat_validate_active_limit" > "$FX/raw-limit.log" 2>&1; then
  bad "limite de entradas redundantes ignorado"
else
  grep -q 'suman 90 entradas normalizadas' "$FX/raw-limit.log" && ok "límite detecta entradas redundantes aunque el dedupe sea menor" || bad "active raw entries limit"
fi
if inlib "CAT_MAX_ACTIVE_SOURCE_BYTES=1; cat_validate_active_limit" > "$FX/raw-size-limit.log" 2>&1; then
  bad "limite de bytes activos ignorado"
else
  grep -q 'cachés activas suman' "$FX/raw-size-limit.log" && ok "límite de bytes de fuentes activas" || bad "active source bytes limit"
fi

OLD_SHA=$(sha256sum "$DATA/catalog/cache/hagezi_multi_pro.list" | cut -d' ' -f1)
export DNSCRYPT_TEST_CAT_BODY_FILE="$FX/feed-b.txt" DNSCRYPT_TEST_CAT_HTTP=503
inlib "cat_update_one hagezi_multi_pro" > "$FX/http503.log" 2>&1 && bad "HTTP 503 aceptado" || grep -q 'HTTP 503' "$FX/http503.log" && ok "HTTP 503 falla seguro" || bad "HTTP status"
[ "$OLD_SHA" = "$(sha256sum "$DATA/catalog/cache/hagezi_multi_pro.list" | cut -d' ' -f1)" ] && ok "HTTP error conserva hash de caché" || bad "HTTP error cache"
cli catalog list --json > "$FX/list.json"
python3 - "$FX/list.json" <<'PY'
import json,sys
d=json.load(open(sys.argv[1],encoding='utf-8')); s=next(x for x in d['entries'] if x['id']=='hagezi_multi_pro')
assert s['runtime_status']=='download_failed' and s['cache_domains']=='30' and int(s['last_success'])>0, s
PY
[ "$?" = 0 ] && ok "estado WebUI muestra fallo con caché y último éxito" || bad "UI source status"
printf '<!doctype html><html><title>Cloudflare</title></html>\n' > "$FX/html.txt"
export DNSCRYPT_TEST_CAT_BODY_FILE="$FX/html.txt" DNSCRYPT_TEST_CAT_HTTP=200
inlib "cat_update_one hagezi_multi_pro" > "$FX/html.log" 2>&1 && bad "HTML 200 aceptado" || grep -q 'contenido html' "$FX/html.log" && ok "HTML/Cloudflare rechazado" || bad "HTML detection"
printf '{"unexpected":"json response with enough content to pass the minimum feed size check"}\n' > "$FX/json.txt"; export DNSCRYPT_TEST_CAT_BODY_FILE="$FX/json.txt"
inlib "cat_update_one hagezi_multi_pro" > "$FX/json.log" 2>&1 && bad "JSON inesperado aceptado" || grep -q 'contenido json' "$FX/json.log" && ok "JSON inesperado rechazado" || bad "JSON detection"
: > "$FX/empty.txt"; export DNSCRYPT_TEST_CAT_BODY_FILE="$FX/empty.txt"
inlib "cat_update_one hagezi_multi_pro" >/dev/null 2>&1 && bad "respuesta vacía aceptada" || ok "respuesta vacía rechazada"
export DNSCRYPT_TEST_CAT_BODY_FILE="$FX/feed-b.txt" DNSCRYPT_TEST_CAT_HTTP=200 CAT_MAX_SOURCE_BYTES=100
inlib "cat_update_one hagezi_multi_pro" > "$FX/size.log" 2>&1 && bad "límite de tamaño ignorado" || grep -q 'tamano fuera de rango' "$FX/size.log" && ok "límite máximo de bytes respetado" || bad "max bytes"
unset CAT_MAX_SOURCE_BYTES

echo "== Transporte HTTPS y límites en streaming =="
mkdir -p "$FX/curl-bin" "$FX/wget-bin"
for i in $(seq 1 100); do printf x; done > "$FX/oversized-body.txt"
cat > "$FX/curl-bin/curl" <<'EOF'
#!/bin/sh
printf '%s\n' "$@" > "$DNSCRYPT_TEST_CAPTURE_ARGS"
_headers=
while [ "$#" -gt 0 ]; do
  if [ "$1" = "-D" ]; then _headers="$2"; shift 2; else shift; fi
done
printf 'HTTP/2 200 OK\r\n' > "$_headers"
cat "$DNSCRYPT_TEST_FETCH_BODY"
EOF
chmod 0755 "$FX/curl-bin/curl"
export DNSCRYPT_TEST_CAPTURE_ARGS="$FX/curl.args" DNSCRYPT_TEST_FETCH_BODY="$FX/oversized-body.txt"
inlib "unset DNSCRYPT_TEST_CAT_BODY_FILE; PATH='$FX/curl-bin':\$PATH; export PATH; CAT_MAX_SOURCE_BYTES=32; export CAT_MAX_SOURCE_BYTES; cat_fetch_raw https://fixtures.invalid/feed '$FX/curl.raw'" >/dev/null 2>&1 \
  && [ "$(wc -c < "$FX/curl.raw" | tr -d ' ')" = 33 ] \
  && grep -qx -- '--proto' "$FX/curl.args" \
  && grep -qx -- '--proto-redir' "$FX/curl.args" \
  && grep -qx -- '=https' "$FX/curl.args" \
  && ok "curl limita bytes en streaming y fuerza HTTPS en redirects" \
  || bad "curl transport bounds"

cat > "$FX/wget-bin/wget" <<'EOF'
#!/bin/sh
if [ "$1" = "--help" ]; then printf '%s\n' '--max-redirect --server-response'; exit 0; fi
printf '%s\n' "$@" > "$DNSCRYPT_TEST_CAPTURE_ARGS"
printf '  HTTP/1.1 200 OK\r\n' >&2
cat "$DNSCRYPT_TEST_FETCH_BODY"
EOF
chmod 0755 "$FX/wget-bin/wget"
export DNSCRYPT_TEST_CAPTURE_ARGS="$FX/wget.args"
inlib "unset DNSCRYPT_TEST_CAT_BODY_FILE; PATH='$FX/wget-bin':\$PATH; export PATH; have(){ [ \"\$1\" = curl ] && return 1; command -v \"\$1\" >/dev/null 2>&1; }; CAT_MAX_SOURCE_BYTES=32; export CAT_MAX_SOURCE_BYTES; cat_fetch_raw https://fixtures.invalid/feed '$FX/wget.raw'" >/dev/null 2>&1 \
  && [ "$(wc -c < "$FX/wget.raw" | tr -d ' ')" = 33 ] \
  && grep -qx -- '--max-redirect=0' "$FX/wget.args" \
  && grep -qx -- '--server-response' "$FX/wget.args" \
  && ok "fallback GNU Wget desactiva redirects y limita bytes en streaming" \
  || bad "wget transport bounds"

cat > "$FX/wget-bin/wget" <<'EOF'
#!/bin/sh
if [ "$1" = "--help" ]; then echo 'BusyBox wget'; exit 0; fi
: > "$DNSCRYPT_TEST_UNSAFE_WGET_CALLED"
exit 1
EOF
chmod 0755 "$FX/wget-bin/wget"
export DNSCRYPT_TEST_UNSAFE_WGET_CALLED="$FX/unsafe-wget-called"
if inlib "unset DNSCRYPT_TEST_CAT_BODY_FILE; PATH='$FX/wget-bin':\$PATH; export PATH; have(){ [ \"\$1\" = curl ] && return 1; command -v \"\$1\" >/dev/null 2>&1; }; cat_fetch_raw https://fixtures.invalid/feed '$FX/unsafe-wget.raw'" > "$FX/wget-unsafe.log" 2>&1; then
  bad "wget sin guard de redirect fue aceptado"
else
  ! grep -q 'unsafe' "$FX/wget-unsafe.log" && [ ! -f "$DNSCRYPT_TEST_UNSAFE_WGET_CALLED" ] \
    && ok "Wget sin límite de redirects falla cerrado antes de descargar" \
    || bad "unsafe wget fallback"
fi

echo "== Update parcial de varias fuentes y rollback de caché =="
awk -F'\t' -v OFS='\t' '$1=="hagezi_multi_pro"{$10="broken"}1' "$TR/mod/config/catalog/blocklists.index.tsv" > "$TR/index.new"
mv "$TR/index.new" "$TR/mod/config/catalog/blocklists.index.tsv"
cli catalog sync >/dev/null 2>&1
cp "$FX/feed-a60.txt" "$FX/feed-a61.txt"; printf 'a60.example.net\n' >> "$FX/feed-a61.txt"
B_SHA=$(sha256sum "$DATA/catalog/cache/hagezi_multi_pro.list" | cut -d' ' -f1)
export DNSCRYPT_TEST_CAT_BODY_FILE="$FX/feed-a61.txt" DNSCRYPT_TEST_CAT_HTTP=200 DNSCRYPT_TEST_COMPILE_FAIL=1
if cli catalog update enabled > "$FX/batch-rollback.log" 2>&1; then
  bad "batch aceptó una compilación fallida"
else
  [ "$(wc -l < "$DATA/catalog/cache/rc1_urlhaus.list" | tr -d ' ')" = 60 ] \
    && [ "$B_SHA" = "$(sha256sum "$DATA/catalog/cache/hagezi_multi_pro.list" | cut -d' ' -f1)" ] \
    && ok "fallo de compilación restaura caché actualizada y conserva la fuente caída" \
    || bad "batch cache rollback"
fi
unset DNSCRYPT_TEST_COMPILE_FAIL
if cli catalog update enabled > "$FX/batch-partial.log" 2>&1; then
  bad "batch parcial reportado como éxito completo"
else
  [ "$(wc -l < "$DATA/catalog/cache/rc1_urlhaus.list" | tr -d ' ')" = 61 ] \
    && [ "$B_SHA" = "$(sha256sum "$DATA/catalog/cache/hagezi_multi_pro.list" | cut -d' ' -f1)" ] \
    && grep -q 'fuente broken' "$FX/batch-partial.log" \
    && ok "update parcial mantiene éxito de una fuente y caché de la caída" \
    || bad "batch partial update"
fi
awk -F'\t' -v OFS='\t' '$1=="hagezi_multi_pro"{$10="unverified"}1' "$TR/mod/config/catalog/blocklists.index.tsv" > "$TR/index.new"
mv "$TR/index.new" "$TR/mod/config/catalog/blocklists.index.tsv"
cli catalog sync >/dev/null 2>&1

echo "== Allowlist, candidate checks y rollback del artefacto activo =="
cli allowlist add a20.example.net >/dev/null 2>&1 && ok "allowlist del usuario se guarda" || bad "allowlist add"
inlib "cat_stats_compute" >/dev/null 2>&1
awk -F'\t' '$1=="#summary" {for(i=1;i<=NF;i++) if($i=="allowlisted" && $(i+1)>0) found=1} END{exit !found}' "$DATA/catalog/contribution-stats.tsv" \
  && ok "allowlist tiene precedencia en estadísticas" || bad "allowlist stats priority"
inlib "DNSCRYPT_TEST_MODE=0; export DNSCRYPT_TEST_MODE; cmd_is_running(){ return 1; }; sec_regen_and_reload --no-restart" > "$FX/compile.log" 2>&1
ACTIVE="$DATA/security/active/blocked-names.txt"
ALLOWED="$DATA/security/active/allowed-names.txt"
TOML="$DATA/config/dnscrypt-proxy.toml"
[ -s "$ACTIVE" ] && grep -qx 'a20.example.net' "$ACTIVE" && grep -qx 'a20.example.net' "$ALLOWED" && ok "allowlist se conserva como excepción efectiva del proxy" || bad "allowlist active precedence"
grep -q "allowed_names_file = '$ALLOWED'" "$TOML" && ok "TOML apunta al archivo allowed_names" || bad "allowed_names TOML"

ACTIVE_SHA=$(sha256sum "$ACTIVE" | cut -d' ' -f1)
if inlib "DNSCRYPT_TEST_MODE=0; export DNSCRYPT_TEST_MODE; SEC_MAX_BLOCKED_DOMAINS=1; cmd_is_running(){ return 1; }; sec_regen_and_reload --no-restart" > "$FX/total-limit.log" 2>&1; then
  bad "límite global de lista ignorado"
else
  grep -q 'límite seguro es 1' "$FX/total-limit.log" \
    && [ "$ACTIVE_SHA" = "$(sha256sum "$ACTIVE" | cut -d' ' -f1)" ] \
    && ok "límite global preserva blocked-names activo" \
    || bad "global blocked-names limit"
fi

WRAP="$DATA/bin/dnscrypt-proxy"
REAL="$DATA/bin/dnscrypt-proxy.real"
mv "$WRAP" "$REAL"
export DNSCRYPT_TEST_FAKE_REAL="$REAL"
cat > "$WRAP" <<'EOF'
#!/bin/sh
if [ "${DNSCRYPT_TEST_FAKE_CHECK_FAIL:-0}" = "1" ]; then
  for arg in "$@"; do [ "$arg" = "-check" ] && exit 42; done
fi
exec "$DNSCRYPT_TEST_FAKE_REAL" "$@"
EOF
chmod 0755 "$WRAP"

ACTIVE_SHA=$(sha256sum "$ACTIVE" | cut -d' ' -f1)
TOML_SHA=$(sha256sum "$TOML" | cut -d' ' -f1)
export DNSCRYPT_TEST_FAKE_CHECK_FAIL=1
if inlib "DNSCRYPT_TEST_MODE=0; export DNSCRYPT_TEST_MODE; cmd_is_running(){ return 1; }; cat_disable rc1_urlhaus; sec_regen_and_reload --no-restart" > "$FX/check-fail.log" 2>&1; then
  bad "candidate -check fallido aceptado"
else
  grep -q 'rechazó la lista candidata' "$FX/check-fail.log" && ok "configuración inválida no se activa" || bad "candidate check"
fi
[ "$ACTIVE_SHA" = "$(sha256sum "$ACTIVE" | cut -d' ' -f1)" ] && [ "$TOML_SHA" = "$(sha256sum "$TOML" | cut -d' ' -f1)" ] && ok "-check mantiene blocked-names y TOML previos" || bad "check rollback files"
unset DNSCRYPT_TEST_FAKE_CHECK_FAIL
inlib "DNSCRYPT_TEST_MODE=0; export DNSCRYPT_TEST_MODE; cmd_is_running(){ return 1; }; cat_enable rc1_urlhaus; sec_regen_and_reload --no-restart" >/dev/null 2>&1 || bad "restore after check failure"

ACTIVE_SHA=$(sha256sum "$ACTIVE" | cut -d' ' -f1)
if inlib "DNSCRYPT_TEST_MODE=0; export DNSCRYPT_TEST_MODE; cmd_is_running(){ return 0; }; cmd_restart(){ return 1; }; cat_disable rc1_urlhaus; sec_regen_and_reload" > "$FX/restart-fail.log" 2>&1; then
  bad "reinicio fallido aceptado"
else
  ok "fallo de reinicio entra en rollback"
fi
[ "$ACTIVE_SHA" = "$(sha256sum "$ACTIVE" | cut -d' ' -f1)" ] && ok "reinicio fallido restaura el archivo activo" || bad "restart rollback active"
inlib "DNSCRYPT_TEST_MODE=0; export DNSCRYPT_TEST_MODE; cmd_is_running(){ return 1; }; cat_enable rc1_urlhaus; sec_regen_and_reload --no-restart" >/dev/null 2>&1 || bad "restore after restart failure"

ACTIVE_SHA=$(sha256sum "$ACTIVE" | cut -d' ' -f1)
if inlib "DNSCRYPT_TEST_MODE=0; export DNSCRYPT_TEST_MODE; cmd_is_running(){ return 0; }; cmd_restart(){ return 0; }; cmd_test_dns(){ return 1; }; cat_disable rc1_urlhaus; sec_regen_and_reload --verify-dns" > "$FX/dns-fail.log" 2>&1; then
  bad "prueba DNS fallida aceptada"
else
  ok "verificación DNS fallida entra en rollback"
fi
[ "$ACTIVE_SHA" = "$(sha256sum "$ACTIVE" | cut -d' ' -f1)" ] && ok "fallo DNS restaura el archivo activo" || bad "DNS rollback active"
inlib "DNSCRYPT_TEST_MODE=0; export DNSCRYPT_TEST_MODE; cmd_is_running(){ return 1; }; cat_enable rc1_urlhaus; sec_regen_and_reload --no-restart" >/dev/null 2>&1 || bad "restore after DNS failure"

ACTIVE_SHA=$(sha256sum "$ACTIVE" | cut -d' ' -f1)
ALLOWED_SHA=$(sha256sum "$ALLOWED" | cut -d' ' -f1)
TOML_SHA=$(sha256sum "$TOML" | cut -d' ' -f1)
mkdir -p "$FX/wrapbin"
export DNSCRYPT_TEST_REAL_MV="$(command -v mv)" DNSCRYPT_TEST_FAIL_MV_TARGET="$ALLOWED" DNSCRYPT_TEST_FAIL_MV_MARKER="$FX/mv-failed-once"
cat > "$FX/wrapbin/mv" <<'EOF'
#!/bin/sh
last=
for arg in "$@"; do last="$arg"; done
if [ "$last" = "${DNSCRYPT_TEST_FAIL_MV_TARGET:-}" ] && [ ! -f "${DNSCRYPT_TEST_FAIL_MV_MARKER:-}" ]; then
  : > "$DNSCRYPT_TEST_FAIL_MV_MARKER"
  exit 1
fi
exec "$DNSCRYPT_TEST_REAL_MV" "$@"
EOF
chmod 0755 "$FX/wrapbin/mv"
if inlib "PATH='$FX/wrapbin':\$PATH; export PATH; DNSCRYPT_TEST_MODE=0; export DNSCRYPT_TEST_MODE; cmd_is_running(){ return 1; }; cat_disable rc1_urlhaus; sec_regen_and_reload --no-restart" > "$FX/mv-fail.log" 2>&1; then
  bad "fallo de rename aceptado"
else
  [ -f "$DNSCRYPT_TEST_FAIL_MV_MARKER" ] && ok "fallo de rename inyectado durante commit" || bad "atomic mv injection"
fi
if [ "$ACTIVE_SHA" = "$(sha256sum "$ACTIVE" | cut -d' ' -f1)" ] \
  && [ "$ALLOWED_SHA" = "$(sha256sum "$ALLOWED" | cut -d' ' -f1)" ] \
  && [ "$TOML_SHA" = "$(sha256sum "$TOML" | cut -d' ' -f1)" ]; then
  ok "fallo entre renames restaura lista, allowlist y TOML previos"
else
  bad "atomic commit rollback"
fi
inlib "DNSCRYPT_TEST_MODE=0; export DNSCRYPT_TEST_MODE; cmd_is_running(){ return 1; }; cat_enable rc1_urlhaus; sec_regen_and_reload --no-restart" >/dev/null 2>&1 || bad "restore after atomic commit failure"

for i in $(seq 0 29); do printf '0.0.0.0 unknown%s.example.net\n' "$i"; done > "$FX/unknown-feed.txt"
export DNSCRYPT_TEST_CAT_BODY_FILE="$FX/unknown-feed.txt" DNSCRYPT_TEST_CAT_HTTP=200 DNSCRYPT_TEST_CAT_RC=0
if cli catalog enable ray_adguard_mobile_spyware > "$FX/license-cli.log" 2>&1; then
  grep -qx ray_adguard_mobile_spyware "$DATA/catalog/enabled.txt" \
    && [ "$(wc -l < "$DATA/catalog/cache/ray_adguard_mobile_spyware.list" | tr -d ' ')" = 30 ] \
    && grep -q 'OK:.*activada y compilada' "$FX/license-cli.log" \
    && ok "LICENSE_UNKNOWN permite opt-in, descarga fixture, valida y compila" \
    || bad "LICENSE_UNKNOWN enable did not produce a validated active list"
  cli catalog disable ray_adguard_mobile_spyware > "$FX/license-disable.log" 2>&1 \
    && ! grep -qx ray_adguard_mobile_spyware "$DATA/catalog/enabled.txt" \
    && ok "fuente LICENSE_UNKNOWN se puede desactivar después del opt-in" \
    || bad "LICENSE_UNKNOWN disable failed"
else
  bad "CLI rechaza opt-in de LICENSE_UNKNOWN: $(cat "$FX/license-cli.log")"
fi

echo
echo "Resultado: $PASS OK, $FAILN FAIL"
exit "$([ "$FAILN" -eq 0 ] && echo 0 || echo 1)"
