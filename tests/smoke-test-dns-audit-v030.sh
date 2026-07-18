#!/bin/bash
# tests/smoke-test-dns-audit-v030.sh — Skaymer AR. Auditoria DNS multisenal:
# el shell root que no resuelve NO debe declararse "sin red o DNS caido" cuando
# la consulta directa al proxy responde (-> not_verifiable).
set -u; cd "$(dirname "$0")/.." || exit 1
SH="$(command -v sh)"; TR="$(mktemp -d /tmp/dcm-audit.XXXXXX)" || exit 99
export DNSCRYPT_TEST_MODE=1 DNSCRYPT_TEST_ROOT="$TR" DNSCRYPT_TEST_DATA_DIR="$TR/data" DNSCRYPT_TEST_MODDIR="$TR/mod"
mkdir -p "$TR/data/config" "$TR/data/run" "$TR/mod/system/bin" "$TR/mod/scripts"
cp system/bin/dnscrypt-manager "$TR/mod/system/bin/"; cp scripts/*.sh "$TR/mod/scripts/"
cp tests/fixtures/fake-dnscrypt-proxy "$TR/data/bin/dnscrypt-proxy" 2>/dev/null || { mkdir -p "$TR/data/bin"; cp tests/fixtures/fake-dnscrypt-proxy "$TR/data/bin/dnscrypt-proxy"; }
chmod 0755 "$TR/data/bin/dnscrypt-proxy" 2>/dev/null; cp config/dnscrypt-proxy.toml "$TR/data/config/"
M="$TR/mod/system/bin/dnscrypt-manager"; trap 'rm -rf "$TR"' EXIT
"$SH" "$M" migrate >/dev/null 2>&1
PASS=0; FAILN=0; ok(){ PASS=$((PASS+1)); printf '  OK   %s\n' "$1"; }; bad(){ FAILN=$((FAILN+1)); printf '  FAIL %s\n' "$1"; }
# extrae el estado de una fila del JSON de leak-test
state(){ printf '%s' "$1" | tr ',' '\n' | grep -A2 "\"$2\"" | grep -oE '"(protegido|posible_fuga|no_verificable|conflicto|fallo)"' | head -1 | tr -d '"'; }

echo "== shell NO resuelve + proxy directo SI responde -> no_verificable (no 'fallo') =="
R=$(DCM_TEST_SYSPING=fail DCM_TEST_PROXY_OK=1 "$SH" "$M" leak-test --json 2>&1)
S=$(printf '%s' "$R" | grep -o '"resolucion_sistema"[^}]*' | grep -oE '(protegido|posible_fuga|no_verificable|conflicto|fallo)' | head -1)
[ "$S" = "no_verificable" ] && ok "resolucion_sistema = no_verificable" || bad "esperaba no_verificable, dio: $S"
printf '%s' "$R" | grep -qi "netd" && ok "texto menciona el contexto netd/shell" || bad "sin texto netd"
printf '%s' "$R" | grep -qi "sin red o DNS caido" && bad "NO debe decir 'sin red o DNS caido'" || ok "no dice 'sin red o DNS caido'"

echo "== shell NO resuelve + proxy directo TAMPOCO -> fallo real =="
R=$(DCM_TEST_SYSPING=fail DCM_TEST_PROXY_OK=0 "$SH" "$M" leak-test --json 2>&1)
S=$(printf '%s' "$R" | grep -o '"resolucion_sistema"[^}]*' | grep -oE '(protegido|posible_fuga|no_verificable|conflicto|fallo)' | head -1)
[ "$S" = "fallo" ] && ok "sin proxy directo -> fallo real" || bad "esperaba fallo, dio: $S"

echo "== shell resuelve -> no es fallo (protegido o posible_fuga) =="
R=$(DCM_TEST_SYSPING=ok DCM_TEST_PROXY_OK=1 "$SH" "$M" leak-test --json 2>&1)
S=$(printf '%s' "$R" | grep -o '"resolucion_sistema"[^}]*' | grep -oE '(protegido|posible_fuga|no_verificable|conflicto|fallo)' | head -1)
[ "$S" = "protegido" ] || [ "$S" = "posible_fuga" ] && ok "shell resuelve -> $S (no fallo)" || bad "dio: $S"

echo "== el JSON sigue siendo valido =="
printf '%s' "$R" | grep -q '"resolucion_proxy"' && ok "leak-test --json integro (contiene resolucion_proxy)" || bad "json roto"
echo ""; echo "Resumen dns-audit: $PASS OK, $FAILN FAIL"; [ "$FAILN" -eq 0 ] && exit 0 || exit 1
