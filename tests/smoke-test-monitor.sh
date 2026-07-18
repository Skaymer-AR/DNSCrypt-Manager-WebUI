#!/bin/bash
set -u; cd "$(dirname "$0")/.." || exit 1; . tests/_tp_common.sh; tp_setup; trap 'rm -rf "$TR"' EXIT
P=0;F=0; ok(){ P=$((P+1)); printf '  OK   %s\n' "$1"; }; bad(){ F=$((F+1)); printf '  FAIL %s\n' "$1"; }
"$SH" "$M" monitor status 2>&1 | grep -q "mode           : audit" && ok "audit-only por defecto" || bad "mode"
"$SH" "$M" monitor status 2>&1 | grep -qi "NUNCA afirma malware confirmado" && ok "no afirma malware" || bad "malware note"
# clasificación heurística via scan
printf 'google.com\nfacebook.com\nx7f9q2w8e3r4t5y6u1i0.evilcdn.com\nz3k9x2m7q1w8e4r6t5y0.example\n' | "$SH" "$M" monitor scan >/dev/null 2>&1
R=$("$SH" "$M" monitor alerts 2>&1)
printf '%s\n' "$R" | grep -q "google.com" && bad "no debia alertar google.com" || ok "dominio normal no alertado"
printf '%s\n' "$R" | grep -Eq "suspicious|high-risk" && ok "dominio de alta entropia -> suspicious/high-risk" || bad "entropia"
# export json/csv
"$SH" "$M" monitor export json 2>&1 | grep -q '^\[' && ok "export json" || bad "json"
"$SH" "$M" monitor export csv 2>&1 | grep -q "^level,domain" && ok "export csv" || bad "csv"
# clear
"$SH" "$M" monitor clear 2>&1 | grep -q "cleared=yes" && ok "clear" || bad "clear"
"$SH" "$M" monitor status 2>&1 | grep -q "alerts_total   : 0" && ok "sin alertas tras clear" || bad "cleared"
# clasificador directo
. scripts/common.sh 2>/dev/null; . scripts/monitor.sh 2>/dev/null
echo "$(monitor_classify_domain aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.x)" | grep -q "suspicious" && ok "subdominio muy largo -> suspicious" || bad "long"
echo ""; echo "Resumen monitor: $P OK, $F FAIL"; [ "$F" -eq 0 ] && exit 0 || exit 1
