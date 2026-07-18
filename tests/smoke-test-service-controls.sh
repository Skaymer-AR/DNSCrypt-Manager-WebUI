#!/bin/bash
set -u; cd "$(dirname "$0")/.." || exit 1; . tests/_tp_common.sh
# service-controls necesita los JSON en el mod
tp_setup; mkdir -p "$TR/mod/config/service-controls"; cp config/service-controls/*.json "$TR/mod/config/service-controls/"; trap 'rm -rf "$TR"' EXIT
P=0;F=0; ok(){ P=$((P+1)); printf '  OK   %s\n' "$1"; }; bad(){ F=$((F+1)); printf '  FAIL %s\n' "$1"; }
N=$("$SH" "$M" service-control list 2>&1 | wc -l)
[ "$N" -ge 9 ] && ok "lista >=9 controles declarativos" || bad "list ($N)"
"$SH" "$M" service-control list 2>&1 | grep -q "mode=off" && ok "OFF por defecto" || bad "default off"
# nombres honestos (telemetry/tracking, no 'ad blocker')
"$SH" "$M" service-control info spotify_telemetry 2>&1 | grep -qi "reduce telemetry" && ok "nombre honesto (reduce telemetry)" || bad "honest"
"$SH" "$M" service-control info meta_tracking 2>&1 | grep -qi "Login with Facebook" && ok "info advierte limitacion (FB login)" || bad "warn"
# set con modo valido + expiry
R=$("$SH" "$M" service-control set xiaomi_telemetry 15m 2>&1); printf '%s\n' "$R" | grep -q "mode=15m" && ok "set 15m con expiry" || bad "set"
"$SH" "$M" service-control list 2>&1 | grep "xiaomi_telemetry" | grep -q "mode=15m" && ok "estado persiste" || bad "persist"
# modo invalido rechazado
"$SH" "$M" service-control set xiaomi_telemetry foo 2>&1 | grep -qi "modo invalido" && ok "modo invalido rechazado" || bad "badmode"
# id invalido
"$SH" "$M" service-control set 'evil;rm' off 2>&1 | grep -qi "id invalido\|desconocido" && ok "id invalido rechazado" || bad "badid"
# conflicto con allowlist
mkdir -p "$TR/data/security"; echo "doubleclick.net" > "$TR/data/security/allowlist.txt"
"$SH" "$M" service-control set google_ads_measurement permanent 2>&1 | grep -qi "CONFLICTO" && ok "detecta conflicto con allowlist" || bad "conflict"
# apagar
"$SH" "$M" service-control set xiaomi_telemetry off 2>&1 | grep -q "mode=off" && ok "apagar control" || bad "off"
echo ""; echo "Resumen service-controls: $P OK, $F FAIL"; [ "$F" -eq 0 ] && exit 0 || exit 1
