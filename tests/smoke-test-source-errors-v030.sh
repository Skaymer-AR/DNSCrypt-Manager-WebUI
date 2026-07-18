#!/bin/bash
# tests/smoke-test-source-errors-v030.sh — Skaymer AR. Estados de error por fuente
# vistos desde la CLI (integracion source doctor -> failure_class -> nunca "0 aplicados").
set -u; cd "$(dirname "$0")/.." || exit 1
SH="$(command -v sh)"; TR="$(mktemp -d /tmp/dcm-serr.XXXXXX)" || exit 99
export DNSCRYPT_TEST_MODE=1 DNSCRYPT_TEST_ROOT="$TR" DNSCRYPT_TEST_DATA_DIR="$TR/data" DNSCRYPT_TEST_MODDIR="$TR/mod"
mkdir -p "$TR/data/config" "$TR/mod/system/bin" "$TR/mod/scripts" "$TR/mod/config/catalog" "$TR/mod/config/blocklist-sources"
cp system/bin/dnscrypt-manager "$TR/mod/system/bin/"; cp scripts/*.sh "$TR/mod/scripts/"
cp config/catalog/*.tsv "$TR/mod/config/catalog/"; cp config/blocklist-sources/*.src "$TR/mod/config/blocklist-sources/"; cp config/dnscrypt-proxy.toml "$TR/data/config/"
M="$TR/mod/system/bin/dnscrypt-manager"; trap 'rm -rf "$TR"' EXIT
"$SH" "$M" migrate >/dev/null 2>&1
PASS=0; FAILN=0; ok(){ PASS=$((PASS+1)); printf '  OK   %s\n' "$1"; }; bad(){ FAILN=$((FAILN+1)); printf '  FAIL %s\n' "$1"; }
g(){ printf '%s\n' "$1" | grep "^$2=" | tail -1 | cut -d= -f2-; }

# 404 permanente -> failure_class http_404 (mapa: fuente_rota), no "descarga fallida" generica
R=$(DCM_FETCH_TEST_RC=22 DCM_FETCH_TEST_HTTP=404 "$SH" "$M" source doctor rc1_coinblocker 2>&1)
[ "$(g "$R" failure_class)" = http_404 ] && ok "404 -> http_404 (UI: fuente_rota)" || bad "404"
# DNS fail conserva metadata de ultima copia valida (campo presente, no vacio conceptual)
R=$(DCM_FETCH_TEST_RC=6 DCM_TEST_SELFBLOCK=no "$SH" "$M" source doctor rc1_phishing_army 2>&1)
[ "$(g "$R" failure_class)" = dns_system_failed ] && ok "curl6 -> dns_system_failed (UI: error_dns)" || bad "dns"
printf '%s\n' "$R" | grep -q "^last_valid_available=" && ok "reporta last_valid_available (no afirma 0 dominios aplicados)" || bad "lastvalid ausente"
# self-block -> autobloqueada
R=$(DCM_FETCH_TEST_RC=6 DCM_TEST_SELFBLOCK=yes "$SH" "$M" source doctor rc1_phishing_army 2>&1)
[ "$(g "$R" failure_class)" = self_blocked ] && ok "self-block -> self_blocked (UI: autobloqueada)" || bad "selfblock"
# timeout
R=$(DCM_FETCH_TEST_RC=28 "$SH" "$M" source doctor rc1_phishing_army 2>&1)
[ "$(g "$R" failure_class)" = timeout ] && ok "curl28 -> timeout (UI: timeout)" || bad "timeout"
# html
R=$(printf '<html></html>' > "$TR/h"; DCM_FETCH_TEST_RC=0 DCM_FETCH_TEST_HTTP=200 DCM_FETCH_TEST_BODY_FILE="$TR/h" DCM_FETCH_MIN_BYTES=2 "$SH" "$M" source doctor rc1_phishing_army 2>&1)
[ "$(g "$R" failure_class)" = html_instead_of_list ] && ok "HTML -> html_instead_of_list (UI: validacion_fallida)" || bad "html"
echo ""; echo "Resumen source-errors: $PASS OK, $FAILN FAIL"; [ "$FAILN" -eq 0 ] && exit 0 || exit 1
