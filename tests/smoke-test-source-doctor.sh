#!/bin/bash
# tests/smoke-test-source-doctor.sh — Skaymer AR. source doctor (hook TEST).
set -u; cd "$(dirname "$0")/.." || exit 1
SH="$(command -v sh)"; TR="$(mktemp -d /tmp/dcm-doc.XXXXXX)" || exit 99
export DNSCRYPT_TEST_MODE=1 DNSCRYPT_TEST_ROOT="$TR" DNSCRYPT_TEST_DATA_DIR="$TR/data" DNSCRYPT_TEST_MODDIR="$TR/mod"
mkdir -p "$TR/data/config" "$TR/mod/system/bin" "$TR/mod/scripts" "$TR/mod/config/catalog" "$TR/mod/config/blocklist-sources"
cp system/bin/dnscrypt-manager "$TR/mod/system/bin/"; cp scripts/*.sh "$TR/mod/scripts/"
cp config/catalog/*.tsv "$TR/mod/config/catalog/"; cp config/blocklist-sources/*.src "$TR/mod/config/blocklist-sources/"; cp config/dnscrypt-proxy.toml "$TR/data/config/"
M="$TR/mod/system/bin/dnscrypt-manager"; trap 'rm -rf "$TR"' EXIT
"$SH" "$M" migrate >/dev/null 2>&1
PASS=0; FAILN=0; ok(){ PASS=$((PASS+1)); printf '  OK   %s\n' "$1"; }; bad(){ FAILN=$((FAILN+1)); printf '  FAIL %s\n' "$1"; }
g(){ printf '%s\n' "$1" | grep "^$2=" | tail -1 | cut -d= -f2-; }

R=$(DCM_FETCH_TEST_RC=22 DCM_FETCH_TEST_HTTP=404 "$SH" "$M" source doctor rc1_coinblocker 2>&1)
[ "$(g "$R" failure_class)" = http_404 ] && ok "coinblocker -> http_404" || bad "404 ($(g "$R" failure_class))"
[ "$(g "$R" runtime_status)" = broken ] && ok "coinblocker runtime_status=broken" || bad "runtime"
[ "$(g "$R" source_type)" = catalog ] && ok "source_type=catalog" || bad "type"
printf '%s\n' "$R" | grep -qi "no reintentar" && ok "recomendacion: no reintentar 404" || bad "rec 404"

R=$(DCM_FETCH_TEST_RC=6 DCM_TEST_SELFBLOCK=yes "$SH" "$M" source doctor rc1_phishing_army 2>&1)
[ "$(g "$R" failure_class)" = self_blocked ] && ok "phishing curl6 + selfblock -> self_blocked" || bad "selfblock"
[ "$(g "$R" source_hostname_blocked)" = yes ] && ok "source_hostname_blocked=yes" || bad "blocked"

R=$(DCM_FETCH_TEST_RC=6 DCM_TEST_SELFBLOCK=no "$SH" "$M" source doctor rc1_phishing_army 2>&1)
[ "$(g "$R" failure_class)" = dns_system_failed ] && ok "phishing curl6 sin selfblock -> dns_system_failed (NO broken)" || bad "dnsfail"
printf '%s\n' "$R" | grep -qi "conservar ultima copia" && ok "recomienda conservar ultima copia valida" || bad "rec dns"

# fuente antigua (legacy_src): cryptomining .src -> NoCoin
R=$(DCM_FETCH_TEST_RC=6 "$SH" "$M" source doctor cryptomining 2>&1)
[ "$(g "$R" source_type)" = legacy_src ] && ok "detecta fuente antigua (legacy_src)" || bad "legacy_src ($(g "$R" source_type))"
printf '%s\n' "$R" | grep -q "nocoin\|adblock-nocoin" && ok "cryptomining .src apunta a NoCoin" || bad "nocoin url"

# id invalido / desconocido
"$SH" "$M" source doctor 'evil;rm' 2>&1 | grep -qi "id invalido" && ok "id con metacaracteres rechazado" || bad "id meta"
R=$("$SH" "$M" source doctor noexiste_zzz 2>&1); [ "$(g "$R" failure_class)" = unsupported_format ] && ok "id desconocido -> unsupported_format" || bad "desconocido"

# campos obligatorios presentes
R=$(DCM_FETCH_TEST_RC=22 DCM_FETCH_TEST_HTTP=404 "$SH" "$M" source doctor rc1_coinblocker 2>&1)
for f in source_id source_type url hostname system_resolution proxy_resolution source_hostname_blocked http_status content_type bytes format_detected last_valid_available runtime_status failure_class; do
  printf '%s\n' "$R" | grep -q "^$f=" && ok "campo $f" || bad "falta $f"
done
echo ""; echo "Resumen source-doctor: $PASS OK, $FAILN FAIL"; [ "$FAILN" -eq 0 ] && exit 0 || exit 1
