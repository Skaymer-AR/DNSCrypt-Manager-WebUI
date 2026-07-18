#!/bin/bash
set -u; cd "$(dirname "$0")/.." || exit 1; . tests/_tp_common.sh; tp_setup; trap 'rm -rf "$TR"' EXIT
P=0;F=0; ok(){ P=$((P+1)); printf '  OK   %s\n' "$1"; }; bad(){ F=$((F+1)); printf '  FAIL %s\n' "$1"; }
"$SH" "$M" transport status 2>&1 | grep -q "mode " && ok "transport status" || bad "status"
"$SH" "$M" transport status 2>&1 | grep -q "last_known_good     : no" && ok "sin last-known-good inicial" || bad "lkg"
# apply exitoso (check+query ok) -> applied=verified + LKG creado
R=$(DCM_TP_TEST_CHECK=ok DCM_TP_TEST_QUERY=ok DCM_TP_TEST_VERIFY=ok "$SH" "$M" transport apply cloudflare anon-cs-fr 2>&1)
printf '%s\n' "$R" | grep -q "applied=verified" && ok "apply verificado -> applied=verified" || bad "apply ($R)"
"$SH" "$M" transport status 2>&1 | grep -q "last_known_good     : yes" && ok "se creo last-known-good tras apply" || bad "lkg post"
# apply que falla la prueba -> no rompe, rollback
R=$(DCM_TP_TEST_CHECK=ok DCM_TP_TEST_QUERY=fail "$SH" "$M" transport apply cloudflare anon-cs-nl 2>&1)
printf '%s\n' "$R" | grep -q "failure=probe_failed" && ok "prueba aislada falla -> no aplica" || bad "probe fail ($R)"
# sintaxis invalida -> failure=syntax
R=$(DCM_TP_TEST_CHECK=fail "$SH" "$M" transport apply cloudflare anon-cs-fr 2>&1)
printf '%s\n' "$R" | grep -q "failure=syntax" && ok "sintaxis invalida -> failure=syntax" || bad "syntax ($R)"
# rollback y disable
"$SH" "$M" transport rollback 2>&1 | grep -q "rolled_back=yes" && ok "rollback al last-known-good" || bad "rollback"
"$SH" "$M" transport disable 2>&1 | grep -q "disabled=yes" && ok "disable -> directo" || bad "disable"
# resolver invalido rechazado
DCM_TP_TEST_CHECK=ok "$SH" "$M" anonymized apply 'evil;rm' anon-cs-fr 2>&1 | grep -qi "invalido" && ok "resolver con metacaracteres rechazado" || bad "meta"
# lock: no residual
[ -d "$TR/data/transport/run/transport.lock" ] && bad "lock residual" || ok "sin lock residual"
echo ""; echo "Resumen transport: $P OK, $F FAIL"; [ "$F" -eq 0 ] && exit 0 || exit 1
