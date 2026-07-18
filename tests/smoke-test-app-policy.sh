#!/bin/bash
set -u; cd "$(dirname "$0")/.." || exit 1; . tests/_tp_common.sh; tp_setup; trap 'rm -rf "$TR"' EXIT
P=0;F=0; ok(){ P=$((P+1)); printf '  OK   %s\n' "$1"; }; bad(){ F=$((F+1)); printf '  FAIL %s\n' "$1"; }
# support: en x86 sin owner/skuid -> unsupported, honesto
R=$(DCM_AP_TEST_OWNER=no DCM_AP_TEST_SKUID=no "$SH" "$M" app-policy support 2>&1)
printf '%s\n' "$R" | grep -q "per_uid_network      : unsupported" && ok "sin capacidades -> unsupported" || bad "unsup"
printf '%s\n' "$R" | grep -qi "per_app_domain_filter: unsupported" && ok "filtrado por dominio por app: unsupported (honesto)" || bad "domfilter"
printf '%s\n' "$R" | grep -qi "experimental" && ok "marcado experimental" || bad "exp"
# set sin soporte -> NO aplica, no rompe red
R=$(DCM_AP_TEST_OWNER=no DCM_AP_TEST_SKUID=no "$SH" "$M" app-policy set com.foo.bar block-external-dns 2>&1)
printf '%s\n' "$R" | grep -q "result=unsupported" && ok "set sin soporte -> unsupported (no aplica)" || bad "setunsup"
printf '%s\n' "$R" | grep -qi "no se rompe la red" && ok "aclara que no rompe la red" || bad "safe"
# set con soporte pero UID irresoluble -> no aplica
R=$(DCM_AP_TEST_OWNER=yes DCM_AP_TEST_UID="" "$SH" "$M" app-policy set com.foo.bar allow-direct 2>&1)
printf '%s\n' "$R" | grep -q "result=uid_unresolved" && ok "UID irresoluble -> no aplica (no confia en el package)" || bad "uid"
# set con soporte + UID valido -> aplica a cadena propia
R=$(DCM_AP_TEST_OWNER=yes DCM_AP_TEST_UID=10123 "$SH" "$M" app-policy set com.foo.bar allow-direct 2>&1)
printf '%s\n' "$R" | grep -q "result=set" && ok "con soporte + UID valido -> set" || bad "set"
printf '%s\n' "$R" | grep -qi "solo cadenas propias" && ok "usa solo cadenas propias" || bad "ownchains"
"$SH" "$M" app-policy list 2>&1 | grep -q "com.foo.bar" && ok "politica listada" || bad "list"
# politica invalida / package invalido
DCM_AP_TEST_OWNER=yes "$SH" "$M" app-policy set com.foo.bar nope 2>&1 | grep -qi "politica invalida" && ok "politica invalida rechazada" || bad "badpol"
"$SH" "$M" app-policy set 'evil;rm' allow-direct 2>&1 | grep -qi "package invalido" && ok "package invalido rechazado" || bad "badpkg"
# clear
DCM_AP_TEST_OWNER=yes DCM_AP_TEST_UID=10123 "$SH" "$M" app-policy set com.foo.bar allow-direct >/dev/null 2>&1
"$SH" "$M" app-policy clear com.foo.bar 2>&1 | grep -q "cleared=com.foo.bar" && ok "clear" || bad "clear"
echo ""; echo "Resumen app-policy: $P OK, $F FAIL"; [ "$F" -eq 0 ] && exit 0 || exit 1
