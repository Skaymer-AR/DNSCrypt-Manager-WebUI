#!/bin/bash
set -u; cd "$(dirname "$0")/.." || exit 1; . tests/_tp_common.sh; tp_setup; trap 'rm -rf "$TR"' EXIT
P=0;F=0; ok(){ P=$((P+1)); printf '  OK   %s\n' "$1"; }; bad(){ F=$((F+1)); printf '  FAIL %s\n' "$1"; }
"$SH" "$M" anonymized relays 2>&1 | grep -q "anon-cs-fr" && ok "lista relays curados" || bad "relays"
"$SH" "$M" anonymized status 2>&1 | grep -qi "no es una VPN" && ok "status advierte: no es VPN" || bad "warn vpn"
"$SH" "$M" anonymized status 2>&1 | grep -q "enabled  : false" && ok "OFF por defecto" || bad "default off"
# test ok
DCM_TP_TEST_CHECK=ok DCM_TP_TEST_QUERY=ok "$SH" "$M" anonymized test cloudflare anon-cs-fr,anon-cs-nl 2>&1 | grep -q "result=ok" && ok "test multi-relay ok" || bad "test"
# apply activa y persiste
R=$(DCM_TP_TEST_CHECK=ok DCM_TP_TEST_QUERY=ok DCM_TP_TEST_VERIFY=ok "$SH" "$M" anonymized apply cloudflare anon-cs-fr 2>&1)
printf '%s\n' "$R" | grep -q "applied=" && ok "apply aplica" || bad "apply ($R)"
"$SH" "$M" anonymized status 2>&1 | grep -q "enabled  : true" && ok "queda enabled tras apply" || bad "enabled"
grep -q '"resolver":"cloudflare"' "$TR/data/transport/anonymized.json" && ok "persiste resolver" || bad "persist"
# disable
"$SH" "$M" anonymized disable 2>&1 | grep -q "disabled=yes" && ok "disable" || bad "disable"
"$SH" "$M" anonymized status 2>&1 | grep -q "enabled  : false" && ok "OFF tras disable" || bad "off"
# stamp invalido
. scripts/common.sh 2>/dev/null; . scripts/fetch.sh 2>/dev/null; . scripts/transport.sh 2>/dev/null
tp_validate_stamp "sdns://AgcAAAABBBBB" && ok "stamp sdns valido aceptado" || bad "stamp ok"
tp_validate_stamp "http://x" || ok "stamp no-sdns rechazado" || bad "stamp bad"
echo ""; echo "Resumen anonymized: $P OK, $F FAIL"; [ "$F" -eq 0 ] && exit 0 || exit 1
