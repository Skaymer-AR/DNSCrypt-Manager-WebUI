#!/bin/bash
set -u; cd "$(dirname "$0")/.." || exit 1; . tests/_tp_common.sh; tp_setup; trap 'rm -rf "$TR"' EXIT
P=0;F=0; ok(){ P=$((P+1)); printf '  OK   %s\n' "$1"; }; bad(){ F=$((F+1)); printf '  FAIL %s\n' "$1"; }
# soporte code_path_present -> status lo refleja, NO activo
R=$(DCM_ODOH_TEST_SUPPORT=code_path_present "$SH" "$M" odoh status 2>&1)
printf '%s\n' "$R" | grep -q "supported        : code_path_present" && ok "detecta code path ODoH" || bad "support"
printf '%s\n' "$R" | grep -q "enabled          : false" && ok "OFF por defecto" || bad "off"
printf '%s\n' "$R" | grep -qi "pendiente de prueba real" && ok "runtime Android marcado pendiente" || bad "pending"
# test en x86 -> not_verifiable (no finge)
DCM_ODOH_TEST_SUPPORT=code_path_present "$SH" "$M" odoh test sdns://AgcAAAABBBBB anon-cs-fr 2>&1 | grep -q "result=not_verifiable" && ok "test -> not_verifiable (no finge exito)" || bad "nv"
# sin soporte -> unsupported
DCM_ODOH_TEST_SUPPORT=no "$SH" "$M" odoh test 2>&1 | grep -q "result=unsupported" && ok "sin soporte -> unsupported" || bad "unsup"
# apply sin prueba verificable -> NO marca activo
R=$(DCM_ODOH_TEST_SUPPORT=code_path_present "$SH" "$M" odoh apply sdns://AgcAAAABBBBB anon-cs-fr 2>&1)
printf '%s\n' "$R" | grep -q "applied=not_verifiable" && ok "apply sin prueba -> not_verifiable, no activo" || bad "apply nv ($R)"
grep -q '"enabled":false' "$TR/data/transport/odoh.json" && ok "odoh.json NO queda enabled sin prueba" || bad "json enabled"
# stamp invalido
DCM_ODOH_TEST_SUPPORT=code_path_present "$SH" "$M" odoh apply 'notastamp' anon-cs-fr 2>&1 | grep -q "result=invalid_stamp" && ok "stamp invalido rechazado" || bad "stamp"
# disable
DCM_ODOH_TEST_SUPPORT=code_path_present "$SH" "$M" odoh disable 2>&1 | grep -q "disabled=yes" && ok "disable" || bad "disable"
echo ""; echo "Resumen odoh: $P OK, $F FAIL"; [ "$F" -eq 0 ] && exit 0 || exit 1
