#!/bin/bash
##############################################################################
# tests/smoke-test-environment-v030.sh  —  Creado por Skaymer AR
# Verifica 'dnscrypt-manager environment status' (deteccion de Hybrid Mount).
# Sondas forzadas bajo TEST_MODE; no toca el sistema real.
##############################################################################
set -u
cd "$(dirname "$0")/.." || exit 1
SH="$(command -v sh)"
TR="$(mktemp -d /tmp/dcm-env.XXXXXX)" || exit 99
export DNSCRYPT_TEST_MODE=1 DNSCRYPT_TEST_ROOT="$TR" DNSCRYPT_TEST_DATA_DIR="$TR/data" DNSCRYPT_TEST_MODDIR="$TR/mod"
mkdir -p "$TR/data/config" "$TR/mod/system/bin" "$TR/mod/scripts"
cp system/bin/dnscrypt-manager "$TR/mod/system/bin/"; cp scripts/*.sh "$TR/mod/scripts/"
cp config/dnscrypt-proxy.toml "$TR/data/config/"
M="$TR/mod/system/bin/dnscrypt-manager"
trap 'rm -rf "$TR"' EXIT
PASS=0; FAILN=0
ok(){ PASS=$((PASS+1)); printf '  OK   %s\n' "$1"; }
bad(){ FAILN=$((FAILN+1)); printf '  FAIL %s\n' "$1"; }
run(){ "$SH" "$M" environment status 2>&1; }

echo "== KSU Next: instalado pero NO expuesto (Hybrid Mount OFF) =="
O=$(DNSCRYPT_TEST_MANAGER=kernelsu_next DNSCRYPT_TEST_DIRECT_CLI=1 DNSCRYPT_TEST_SYSTEMLESS_CLI=0 DNSCRYPT_TEST_SELINUX=enforcing run)
echo "$O" | grep -q "hybrid_mount_required  : yes" && ok "hybrid_mount_required=yes en KSU Next" || bad "required"
echo "$O" | grep -q "hybrid_mount_detected  : no" && ok "hybrid_mount_detected=no (instalado, no expuesto)" || bad "detected no"
echo "$O" | grep -qi "Activa Hybrid Mount" && ok "muestra el mensaje accionable especifico" || bad "mensaje"
echo "$O" | grep -qi "rc=127\|not found" && bad "no debe mostrar rc=127 crudo" || ok "no muestra rc=127 crudo"

echo "== KSU Next: expuesto (Hybrid Mount ON) -> sin advertencia =="
O=$(DNSCRYPT_TEST_MANAGER=kernelsu_next DNSCRYPT_TEST_DIRECT_CLI=1 DNSCRYPT_TEST_SYSTEMLESS_CLI=1 DNSCRYPT_TEST_SELINUX=enforcing run)
echo "$O" | grep -q "hybrid_mount_detected  : yes" && ok "detected=yes cuando /system expone el modulo en KSU Next" || bad "detected yes"
echo "$O" | grep -qi "Activa Hybrid Mount" && bad "no debe advertir si ya esta expuesto" || ok "sin advertencia cuando esta expuesto"

echo "== Magisk: CLI visible -> sin advertencia falsa, no afirma Hybrid Mount =="
O=$(DNSCRYPT_TEST_MANAGER=magisk DNSCRYPT_TEST_DIRECT_CLI=1 DNSCRYPT_TEST_SYSTEMLESS_CLI=1 DNSCRYPT_TEST_SELINUX=enforcing run)
echo "$O" | grep -q "hybrid_mount_required  : no" && ok "Magisk: hybrid_mount_required=no" || bad "magisk required"
echo "$O" | grep -q "hybrid_mount_detected  : unknown" && ok "Magisk: detected=unknown (no afirma por /system)" || bad "magisk detected"
echo "$O" | grep -qi "Activa Hybrid Mount" && bad "Magisk NO debe recibir la advertencia" || ok "Magisk sin advertencia de Hybrid Mount"

echo "== APatch: CLI visible -> sin advertencia =="
O=$(DNSCRYPT_TEST_MANAGER=apatch DNSCRYPT_TEST_DIRECT_CLI=1 DNSCRYPT_TEST_SYSTEMLESS_CLI=1 DNSCRYPT_TEST_SELINUX=enforcing run)
echo "$O" | grep -q "hybrid_mount_required  : no" && ok "APatch: required=no" || bad "apatch required"
echo "$O" | grep -qi "Activa Hybrid Mount" && bad "APatch NO debe advertir" || ok "APatch sin advertencia"

echo "== Campos obligatorios presentes =="
O=$(DNSCRYPT_TEST_MANAGER=kernelsu DNSCRYPT_TEST_DIRECT_CLI=1 DNSCRYPT_TEST_SYSTEMLESS_CLI=1 run)
for f in manager module_path systemless_cli_visible direct_module_cli_visible hybrid_mount_required hybrid_mount_detected selinux execution_context; do
  echo "$O" | grep -q "^$f" && ok "campo $f presente" || bad "falta campo $f"
done

echo ""
echo "Resumen environment: $PASS OK, $FAILN FAIL"
[ "$FAILN" -eq 0 ] && exit 0 || exit 1
