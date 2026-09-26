#!/bin/bash
set -u
cd "$(dirname "$0")/.." || exit 1
. tests/_tp_common.sh
tp_setup
trap 'rm -rf "$TR"' EXIT
P=0; F=0
ok(){ P=$((P+1)); printf '  OK   %s\n' "$1"; }
bad(){ F=$((F+1)); printf '  FAIL %s\n' "$1"; }

FW_SOURCE="$PWD/tests/fixtures/fake-firewall-bin/iptables"
FW_DIR="$TR/fakefw"
mkdir -p "$FW_DIR"
cp "$FW_SOURCE" "$FW_DIR/iptables"
ln -s iptables "$FW_DIR/ip6tables"
export PATH="$FW_DIR:$PATH" FAKE_FW_STATE="$TR/firewall-state"
mkdir -p "$FAKE_FW_STATE"

# Without owner-match support the module must refuse to apply anything.
R=$(DCM_AP_TEST_OWNER=no DCM_AP_TEST_IPV6_OWNER=no "$SH" "$M" app-policy support 2>&1)
printf '%s\n' "$R" | grep -q 'per_uid_network     : false' && ok 'sin soporte en ambas familias -> unsupported' || bad 'support-unavailable'
R=$(DCM_AP_TEST_OWNER=no DCM_AP_TEST_IPV6_OWNER=no "$SH" "$M" app-policy set com.foo.bar block-internet 2>&1)
printf '%s\n' "$R" | grep -q 'result=unsupported' && ok 'sin soporte -> no aplica reglas' || bad 'set-unsupported'
[ ! -f "$FAKE_FW_STATE/iptables.filter.DCM_APP_OUT.exists" ] && ok 'unsupported no crea la cadena IPv4' || bad 'unsupported-v4-chain'
[ ! -f "$FAKE_FW_STATE/ip6tables.filter.DCM_APP_OUT.exists" ] && ok 'unsupported no crea la cadena IPv6' || bad 'unsupported-v6-chain'

# Invalid package/policy and unresolved UID are rejected before enforcement.
DCM_AP_TEST_OWNER=yes DCM_AP_TEST_IPV6_OWNER=yes DCM_AP_TEST_UID='' "$SH" "$M" app-policy set com.foo.bar block-internet 2>&1 | grep -q 'result=uid_unresolved' && ok 'UID irresoluble -> no aplica' || bad 'uid-unresolved'
DCM_AP_TEST_OWNER=yes DCM_AP_TEST_IPV6_OWNER=yes DCM_AP_TEST_UID=10123 "$SH" "$M" app-policy set 'evil;rm' block-internet 2>&1 | grep -qi 'package invalido' && ok 'package inseguro rechazado' || bad 'bad-package'
DCM_AP_TEST_OWNER=yes DCM_AP_TEST_IPV6_OWNER=yes DCM_AP_TEST_UID=10123 "$SH" "$M" app-policy set com.foo.bar allow-direct 2>&1 | grep -qi 'politica invalida' && ok 'politica no soportada rechazada' || bad 'bad-policy'

# A valid choice creates only our own OUTPUT chains, in both IPv4 and IPv6.
R=$(DCM_AP_TEST_OWNER=yes DCM_AP_TEST_IPV6_OWNER=yes DCM_AP_TEST_UID=10123 "$SH" "$M" app-policy set com.foo.bar block-internet 2>&1)
printf '%s\n' "$R" | grep -q 'result=applied package=com.foo.bar uid=10123' && ok 'bloqueo aplicado a UID válido' || { bad 'set-applied'; printf '    salida: %s\n' "$R"; }
grep -qxF -- '-m owner --uid-owner 10123 -j REJECT' "$FAKE_FW_STATE/iptables.filter.DCM_APP_OUT.rules" && ok 'regla IPv4 limitada al UID' || bad 'rule-v4'
grep -qxF -- '-m owner --uid-owner 10123 -j REJECT' "$FAKE_FW_STATE/ip6tables.filter.DCM_APP_OUT.rules" && ok 'regla IPv6 limitada al UID' || bad 'rule-v6'
grep -qxF -- '-j DCM_APP_OUT' "$FAKE_FW_STATE/iptables.filter.OUTPUT.rules" && ok 'hook IPv4 en OUTPUT' || { bad 'hook-v4'; cat "$FAKE_FW_STATE/iptables.filter.OUTPUT.rules" 2>/dev/null; }
grep -qxF -- '-j DCM_APP_OUT' "$FAKE_FW_STATE/ip6tables.filter.OUTPUT.rules" && ok 'hook IPv6 en OUTPUT' || { bad 'hook-v6'; cat "$FAKE_FW_STATE/ip6tables.filter.OUTPUT.rules" 2>/dev/null; }

R=$(DCM_AP_TEST_OWNER=yes DCM_AP_TEST_IPV6_OWNER=yes DCM_AP_TEST_UID=10123 "$SH" "$M" app-policy support --json 2>&1)
printf '%s\n' "$R" | grep -q '"supported":true' && ok 'estado JSON informa soporte comprobado' || bad 'support-json'
R=$(DCM_AP_TEST_OWNER=yes DCM_AP_TEST_IPV6_OWNER=yes DCM_AP_TEST_UID=10123 "$SH" "$M" app-policy list --json 2>&1)
printf '%s\n' "$R" | grep -q '"package":"com.foo.bar","policy":"block-internet","uid":10123' && ok 'lista JSON devuelve política y UID' || bad 'list-json'

# Losing verified support must remove our old hooks while keeping preferences available for recovery.
R=$(DCM_AP_TEST_OWNER=no DCM_AP_TEST_IPV6_OWNER=no "$SH" "$M" app-policy restore 2>&1)
printf '%s\n' "$R" | grep -q 'result=unsupported' && ok 'sin soporte posterior -> restore informa estado inactivo' || bad 'restore-unsupported'
[ ! -f "$FAKE_FW_STATE/iptables.filter.DCM_APP_OUT.exists" ] && [ ! -f "$FAKE_FW_STATE/ip6tables.filter.DCM_APP_OUT.exists" ] && ok 'sin soporte posterior retira ambas cadenas propias' || bad 'restore-removes-own-chains'
grep -q '^com.foo.bar[[:space:]]block-internet[[:space:]]10123$' "$TR/data/apppolicy/policies.tsv" && ok 'al perder soporte conserva preferencia para recuperación' || bad 'restore-keeps-state'
DCM_AP_TEST_OWNER=yes DCM_AP_TEST_IPV6_OWNER=yes DCM_AP_TEST_UID=10123 "$SH" "$M" app-policy restore >/dev/null 2>&1
grep -qxF -- '-m owner --uid-owner 10123 -j REJECT' "$FAKE_FW_STATE/iptables.filter.DCM_APP_OUT.rules" && ok 'al volver soporte restaura reglas guardadas' || bad 'restore-recovers-state'

# Shared UIDs create a single reject rule; clearing one package preserves the other.
DCM_AP_TEST_OWNER=yes DCM_AP_TEST_IPV6_OWNER=yes DCM_AP_TEST_UID=10123 "$SH" "$M" app-policy set com.foo.second block-internet >/dev/null 2>&1
[ "$(grep -c -- '--uid-owner 10123 -j REJECT' "$FAKE_FW_STATE/iptables.filter.DCM_APP_OUT.rules")" = 1 ] && ok 'UID compartido no duplica reglas' || bad 'shared-uid'
DCM_AP_TEST_OWNER=yes DCM_AP_TEST_IPV6_OWNER=yes DCM_AP_TEST_UID=10123 "$SH" "$M" app-policy clear com.foo.bar >/dev/null 2>&1
grep -qxF -- '-m owner --uid-owner 10123 -j REJECT' "$FAKE_FW_STATE/iptables.filter.DCM_APP_OUT.rules" && ok 'limpiar un package conserva UID compartido' || bad 'shared-uid-clear'

DCM_AP_TEST_OWNER=yes DCM_AP_TEST_IPV6_OWNER=yes DCM_AP_TEST_UID=10123 "$SH" "$M" app-policy clear-all >/dev/null 2>&1
[ ! -f "$FAKE_FW_STATE/iptables.filter.DCM_APP_OUT.exists" ] && ok 'clear-all retira solo la cadena IPv4 propia' || bad 'clear-all-v4'
[ ! -f "$FAKE_FW_STATE/ip6tables.filter.DCM_APP_OUT.exists" ] && ok 'clear-all retira solo la cadena IPv6 propia' || bad 'clear-all-v6'

# User policies survive module disable and are restored on enable; PANIC removes them.
DCM_AP_TEST_OWNER=yes DCM_AP_TEST_IPV6_OWNER=yes DCM_AP_TEST_UID=10123 "$SH" "$M" app-policy set com.foo.bar block-internet >/dev/null 2>&1
DCM_AP_TEST_OWNER=yes DCM_AP_TEST_IPV6_OWNER=yes "$SH" "$M" disable >/dev/null 2>&1
[ ! -f "$FAKE_FW_STATE/iptables.filter.DCM_APP_OUT.exists" ] && ok 'disable retira las reglas activas' || bad 'disable-cleanup'
DCM_AP_TEST_OWNER=yes DCM_AP_TEST_IPV6_OWNER=yes DCM_AP_TEST_UID=10123 "$SH" "$M" enable >/dev/null 2>&1
grep -qxF -- '-m owner --uid-owner 10123 -j REJECT' "$FAKE_FW_STATE/iptables.filter.DCM_APP_OUT.rules" && ok 'enable restaura políticas guardadas' || bad 'enable-restore'
DCM_AP_TEST_OWNER=yes DCM_AP_TEST_IPV6_OWNER=yes DCM_AP_TEST_UID=10123 "$SH" "$M" panic >/dev/null 2>&1
[ ! -s "$TR/data/apppolicy/policies.tsv" ] && ok 'PANIC borra políticas persistentes' || bad 'panic-state'
[ ! -f "$FAKE_FW_STATE/ip6tables.filter.DCM_APP_OUT.exists" ] && ok 'PANIC retira la cadena IPv6 propia' || bad 'panic-cleanup'

echo
echo "Resumen app-policy firewall: $P OK, $F FAIL"
[ "$F" -eq 0 ]
