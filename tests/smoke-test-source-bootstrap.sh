#!/bin/bash
# tests/smoke-test-source-bootstrap.sh — Skaymer AR. Bootstrap DNS aislado (hooks TEST).
set -u; cd "$(dirname "$0")/.." || exit 1
TR="$(mktemp -d /tmp/dcm-boot.XXXXXX)" || exit 99; export DATA_DIR="$TR"; mkdir -p "$TR/run"
trap 'rm -rf "$TR"' EXIT
. scripts/fetch.sh
PASS=0; FAILN=0; ok(){ PASS=$((PASS+1)); printf '  OK   %s\n' "$1"; }; bad(){ FAILN=$((FAILN+1)); printf '  FAIL %s\n' "$1"; }
gv(){ printf '%s\n' "$1" | grep "^$2=" | tail -1 | cut -d= -f2-; }
printf 'example.com\nads.net\nfoo.bar.io\n' > "$TR/dom.txt"

echo "== descarga normal (sin bootstrap) =="
R=$(DNSCRYPT_TEST_MODE=1 DCM_FETCH_TEST_RC=0 DCM_FETCH_TEST_HTTP=200 DCM_FETCH_TEST_BODY_FILE="$TR/dom.txt" DCM_FETCH_MIN_BYTES=5 dcm_bootstrap_fetch "https://x/y" "$TR/o1.txt" t)
[ "$(gv "$R" failure_class)" = ok ] && [ -f "$TR/o1.txt" ] && ok "descarga normal OK, sin bootstrap" || bad "normal"
printf '%s\n' "$R" | grep -q "bootstrap=" && bad "no debia bootstrapear" || ok "no invoca bootstrap si la normal anda"

echo "== curl 6 + bootstrap resuelve IP -> reintento OK =="
# 1er intento: DNS falla. Reintento con --resolve: OK (cambiamos el hook a mitad no se puede,
# asi que simulamos: la primera llamada da rc6; para el reintento el orquestador re-llama
# dcm_fetch_url con DCM_FETCH_RESOLVE; usamos DCM_FETCH_TEST_RC2 no existe, asi que probamos
# la ruta de resolucion + forma). Validamos que obtiene IP y marca bootstrap=used.
R=$(DNSCRYPT_TEST_MODE=1 DCM_FETCH_TEST_RC=6 DCM_BOOT_TEST_IP=203.0.113.10 dcm_bootstrap_fetch "https://phishing.army/x" "$TR/o2.txt" t)
printf '%s\n' "$R" | grep -q "bootstrap=resolved" && ok "bootstrap obtiene IP (203.0.113.10)" || bad "no resolvio"
printf '%s\n' "$R" | grep -q "ip=203.0.113.10" && ok "usa la IP resuelta con --resolve" || bad "sin ip"

echo "== curl 6 + bootstrap SIN IP -> preserva, no aplica vacio =="
echo "PREVIO" > "$TR/keep.txt"
R=$(DNSCRYPT_TEST_MODE=1 DCM_FETCH_TEST_RC=6 DCM_BOOT_TEST_INSTANCE=fail dcm_bootstrap_fetch "https://x/y" "$TR/keep.txt" t)
printf '%s\n' "$R" | grep -q "bootstrap=failed_no_ip" && ok "instancia no arranca -> failed_no_ip" || bad "no reporto fallo"
[ "$(cat "$TR/keep.txt")" = "PREVIO" ] && ok "preserva la ultima copia valida (no pisa)" || bad "piso la copia"

echo "== 404 NO usa bootstrap (no es problema de DNS) =="
R=$(DNSCRYPT_TEST_MODE=1 DCM_FETCH_TEST_RC=22 DCM_FETCH_TEST_HTTP=404 dcm_bootstrap_fetch "https://x/y" "" t)
printf '%s\n' "$R" | grep -q "bootstrap=" && bad "404 no debe bootstrapear" || ok "404 no invoca bootstrap"
[ "$(gv "$R" failure_class)" = http_404 ] && ok "mantiene http_404" || bad "clase"

echo "== IP malformada rechazada =="
R=$(DNSCRYPT_TEST_MODE=1 DCM_FETCH_TEST_RC=6 DCM_BOOT_TEST_IP="1.2.3.4; rm" dcm_bootstrap_fetch "https://x/y" "" t)
printf '%s\n' "$R" | grep -q "bootstrap=failed_bad_ip" && ok "IP con metacaracteres rechazada" || bad "ip mala aceptada"

echo "== sin procesos residuales del test =="
# (los hooks TEST no lanzan procesos; verificamos que no queden temporales de bootstrap)
ls "$TR/run/" 2>/dev/null | grep -q "bootstrap\." && bad "quedaron temporales de bootstrap" || ok "sin temporales de bootstrap"
echo ""; echo "Resumen source-bootstrap: $PASS OK, $FAILN FAIL"; [ "$FAILN" -eq 0 ] && exit 0 || exit 1
