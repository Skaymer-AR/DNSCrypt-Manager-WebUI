#!/bin/bash
# tests/smoke-test-source-fetch.sh — Skaymer AR. dcm_fetch_url (hook TEST, sin red).
set -u; cd "$(dirname "$0")/.." || exit 1
TR="$(mktemp -d /tmp/dcm-fetch.XXXXXX)" || exit 99; export DATA_DIR="$TR"; mkdir -p "$TR/run"
trap 'rm -rf "$TR"' EXIT
. scripts/fetch.sh
PASS=0; FAILN=0; ok(){ PASS=$((PASS+1)); printf '  OK   %s\n' "$1"; }; bad(){ FAILN=$((FAILN+1)); printf '  FAIL %s\n' "$1"; }
fc(){ printf '%s\n' "$1" | grep '^failure_class=' | tail -1 | cut -d= -f2; }
printf 'example.com\nads.net\nfoo.bar.io\n' > "$TR/dom.txt"
printf '0.0.0.0 ads.net\n0.0.0.0 track.io\n0.0.0.0 x.example\n' > "$TR/hosts.txt"
printf '<!DOCTYPE html><html><body>x</body></html>\n' > "$TR/html.txt"; : > "$TR/empty.txt"

R=$(DNSCRYPT_TEST_MODE=1 DCM_FETCH_TEST_RC=0 DCM_FETCH_TEST_HTTP=200 DCM_FETCH_TEST_BODY_FILE="$TR/dom.txt" DCM_FETCH_MIN_BYTES=5 dcm_fetch_url "https://x/y.txt" "$TR/out.txt" t)
[ "$(fc "$R")" = ok ] && [ -f "$TR/out.txt" ] && ok "ok domains -> escribe destino" || bad "ok domains"
printf '%s\n' "$R" | grep -q "format_detected=domains" && ok "detecta formato domains" || bad "fmt domains"
R=$(DNSCRYPT_TEST_MODE=1 DCM_FETCH_TEST_RC=0 DCM_FETCH_TEST_HTTP=200 DCM_FETCH_TEST_BODY_FILE="$TR/hosts.txt" DCM_FETCH_MIN_BYTES=5 dcm_fetch_url "https://x/y" "" t)
printf '%s\n' "$R" | grep -q "format_detected=hosts" && ok "detecta formato hosts" || bad "fmt hosts"
R=$(DNSCRYPT_TEST_MODE=1 DCM_FETCH_TEST_RC=6 dcm_fetch_url "https://x/y" "$TR/no.txt" t)
[ "$(fc "$R")" = dns_system_failed ] && [ ! -f "$TR/no.txt" ] && ok "curl 6 -> dns_system_failed, NO escribe destino (preserva)" || bad "dns fail"
R=$(DNSCRYPT_TEST_MODE=1 DCM_FETCH_TEST_RC=7 dcm_fetch_url "https://x/y" "" t); [ "$(fc "$R")" = connection_failed ] && ok "curl 7 -> connection_failed" || bad "conn"
R=$(DNSCRYPT_TEST_MODE=1 DCM_FETCH_TEST_RC=28 dcm_fetch_url "https://x/y" "" t); [ "$(fc "$R")" = timeout ] && ok "curl 28 -> timeout" || bad "timeout"
R=$(DNSCRYPT_TEST_MODE=1 DCM_FETCH_TEST_RC=60 dcm_fetch_url "https://x/y" "" t); [ "$(fc "$R")" = tls_failed ] && ok "curl 60 -> tls_failed" || bad "tls"
R=$(DNSCRYPT_TEST_MODE=1 DCM_FETCH_TEST_RC=47 dcm_fetch_url "https://x/y" "" t); [ "$(fc "$R")" = redirect_invalid ] && ok "curl 47 -> redirect_invalid" || bad "redir"
R=$(DNSCRYPT_TEST_MODE=1 DCM_FETCH_TEST_RC=22 DCM_FETCH_TEST_HTTP=404 dcm_fetch_url "https://x/y" "" t); [ "$(fc "$R")" = http_404 ] && ok "curl 22 http 404 -> http_404" || bad "404"
R=$(DNSCRYPT_TEST_MODE=1 DCM_FETCH_TEST_RC=22 DCM_FETCH_TEST_HTTP=500 dcm_fetch_url "https://x/y" "" t); [ "$(fc "$R")" = http_error ] && ok "curl 22 http 500 -> http_error" || bad "500"
R=$(DNSCRYPT_TEST_MODE=1 DCM_FETCH_TEST_RC=0 DCM_FETCH_TEST_HTTP=200 DCM_FETCH_TEST_BODY_FILE="$TR/html.txt" DCM_FETCH_MIN_BYTES=5 dcm_fetch_url "https://x/y" "" t); [ "$(fc "$R")" = html_instead_of_list ] && ok "HTML 200 -> html_instead_of_list" || bad "html"
R=$(DNSCRYPT_TEST_MODE=1 DCM_FETCH_TEST_RC=0 DCM_FETCH_TEST_HTTP=200 DCM_FETCH_TEST_BODY_FILE="$TR/empty.txt" dcm_fetch_url "https://x/y" "" t); [ "$(fc "$R")" = empty ] && ok "vacio -> empty" || bad "empty"
R=$(dcm_fetch_url "http://x/y" "" t); [ "$(fc "$R")" = unsupported_format ] && ok "http plano -> unsupported_format" || bad "http"
R=$(dcm_fetch_url "file:///etc/passwd" "" t); [ "$(fc "$R")" = unsupported_format ] && ok "file:// -> unsupported_format" || bad "file"
R=$(dcm_fetch_url 'https://x/y;rm -rf /' "" t); [ "$(fc "$R")" = validation_failed ] && ok "metacaracteres -> validation_failed" || bad "meta"
R=$(dcm_fetch_url 'https://x/y$(reboot)' "" t); [ "$(fc "$R")" = validation_failed ] && ok "\$() en URL -> validation_failed" || bad "subst"
# preservacion: destino previo intacto tras un fallo
echo "PREVIO" > "$TR/keep.txt"
DNSCRYPT_TEST_MODE=1 DCM_FETCH_TEST_RC=6 dcm_fetch_url "https://x/y" "$TR/keep.txt" t >/dev/null
[ "$(cat "$TR/keep.txt")" = "PREVIO" ] && ok "fallo NO pisa la ultima copia valida" || bad "preservacion"
echo ""; echo "Resumen source-fetch: $PASS OK, $FAILN FAIL"; [ "$FAILN" -eq 0 ] && exit 0 || exit 1
