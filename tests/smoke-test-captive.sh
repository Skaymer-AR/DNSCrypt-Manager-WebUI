#!/bin/bash
set -u; cd "$(dirname "$0")/.." || exit 1; . tests/_tp_common.sh; tp_setup; trap 'rm -rf "$TR"' EXIT
P=0;F=0; ok(){ P=$((P+1)); printf '  OK   %s\n' "$1"; }; bad(){ F=$((F+1)); printf '  FAIL %s\n' "$1"; }
"$SH" "$M" captive status 2>&1 | grep -q "captive_pause     : inactive" && ok "OFF por defecto (inactive)" || bad "default"
"$SH" "$M" captive status 2>&1 | grep -qi "PANIC siempre disponible" && ok "status recuerda PANIC disponible" || bad "panic note"
# enter con ventana
R=$("$SH" "$M" captive enter 120 2>&1)
printf '%s\n' "$R" | grep -q "window_seconds=120" && ok "enter respeta ventana" || bad "enter ($R)"
"$SH" "$M" captive status 2>&1 | grep -q "captive_pause     : active" && ok "queda active tras enter" || bad "active"
# techo duro de 30 min
R=$("$SH" "$M" captive enter 999999 2>&1); printf '%s\n' "$R" | grep -q "window_seconds=1800" && ok "techo duro 1800s" || bad "cap ($R)"
# restore vuelve a inactive
"$SH" "$M" captive restore 2>&1 | grep -q "captive=restored" && ok "restore" || bad "restore"
"$SH" "$M" captive status 2>&1 | grep -q "captive_pause     : inactive" && ok "inactive tras restore" || bad "inactive"
# detección con override
DCM_CAP_TEST_PORTAL=no_network "$SH" "$M" captive status 2>&1 | grep -q "network_detect    : no_network" && ok "detección override" || bad "detect"
echo ""; echo "Resumen captive: $P OK, $F FAIL"; [ "$F" -eq 0 ] && exit 0 || exit 1
