#!/bin/bash
set -u; cd "$(dirname "$0")/.." || exit 1; . tests/_tp_common.sh; tp_setup; trap 'rm -rf "$TR"' EXIT
P=0;F=0; ok(){ P=$((P+1)); printf '  OK   %s\n' "$1"; }; bad(){ F=$((F+1)); printf '  FAIL %s\n' "$1"; }
"$SH" "$M" bypass status 2>&1 | grep -q "mode              : audit" && ok "modo audit por defecto" || bad "mode"
"$SH" "$M" bypass status 2>&1 | grep -q "strict_default    : off" && ok "strict OFF por defecto" || bad "strict"
"$SH" "$M" bypass status 2>&1 | grep -qi "no se asume DoH" && ok "no clasifica 443 como DoH" || bad "443 note"
# audit con overrides
R=$(DCM_BP_TEST_PRIVATE_DNS=hostname DCM_BP_TEST_VPN=yes DCM_BP_TEST_PORT53=directo "$SH" "$M" bypass audit 2>&1)
printf '%s\n' "$R" | grep -q "private_dns	dot_configurado	warning" && ok "Private DNS hostname -> warning" || bad "pdns"
printf '%s\n' "$R" | grep -q "vpn	activa	warning" && ok "VPN activa -> warning" || bad "vpn"
printf '%s\n' "$R" | grep -q "udp_tcp_53	directo	warning" && ok "53 directo -> warning" || bad "53"
# sin señal -> no_verificable (no falso positivo)
R=$("$SH" "$M" bypass audit 2>&1); printf '%s\n' "$R" | grep -q "dot_853	no_verificable" && ok "853 sin señal -> no_verificable" || bad "853"
# cambiar modo
"$SH" "$M" bypass mode strict 2>&1 | grep -q "mode=strict" && ok "set mode strict" || bad "setmode"
"$SH" "$M" bypass mode nope 2>&1 | grep -qi "Uso" && ok "modo invalido rechazado" || bad "badmode"
echo ""; echo "Resumen bypass: $P OK, $F FAIL"; [ "$F" -eq 0 ] && exit 0 || exit 1
