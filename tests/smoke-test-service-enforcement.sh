#!/bin/bash
# tests/smoke-test-service-enforcement.sh — Skaymer AR.
# Enforcement REAL: los dominios de un control declarativo activo DEBEN aparecer en
# la lista compilada blocked-names.txt (el merge corre de verdad, sin hooks).
set -u; cd "$(dirname "$0")/.." || exit 1; . tests/_tp_common.sh
tp_setup; mkdir -p "$TR/mod/config/service-controls"; cp config/service-controls/*.json "$TR/mod/config/service-controls/"; trap 'rm -rf "$TR"' EXIT
P=0;F=0; ok(){ P=$((P+1)); printf '  OK   %s\n' "$1"; }; bad(){ F=$((F+1)); printf '  FAIL %s\n' "$1"; }
BL="$TR/data/security/active/blocked-names.txt"

# 1) estado inicial: spotify NO en la lista
"$SH" "$M" service-control set spotify_telemetry off >/dev/null 2>&1
grep -q "log.spotify.com" "$BL" 2>/dev/null && bad "spotify no debia estar bloqueado (off)" || ok "off: dominios NO en blocked-names"

# 2) activar 1h -> los dominios REALMENTE aparecen en blocked-names
R=$("$SH" "$M" service-control set spotify_telemetry 1h 2>&1)
printf '%s\n' "$R" | grep -q "applied=yes" && ok "set reporta applied=yes (recompilo)" || bad "no aplico ($R)"
grep -qx "log.spotify.com" "$BL" 2>/dev/null && ok "ENFORCEMENT REAL: log.spotify.com esta en blocked-names.txt" || bad "dominio NO llego a la lista"
grep -qx "analytics.spotify.com" "$BL" 2>/dev/null && ok "ENFORCEMENT REAL: analytics.spotify.com en la lista" || bad "segundo dominio ausente"

# 3) desactivar -> los dominios se van de la lista
"$SH" "$M" service-control set spotify_telemetry off >/dev/null 2>&1
grep -q "log.spotify.com" "$BL" 2>/dev/null && bad "off no removio el dominio" || ok "off: dominio removido de blocked-names"

# 4) allowlist NEUTRALIZA en runtime: dnscrypt-proxy aplica allowed_names_file por
#    encima de blocked_names_file. El dominio queda en blocked-names PERO tambien en
#    allowed-names, y el proxy honra allowed -> no se bloquea en la practica.
mkdir -p "$TR/data/security"; echo "doubleclick.net" > "$TR/data/security/allowlist.txt"
"$SH" "$M" service-control set google_ads_measurement permanent >/dev/null 2>&1
AL="$TR/data/security/active/allowed-names.txt"
if grep -qx "doubleclick.net" "$AL" 2>/dev/null; then ok "allowlist neutraliza: doubleclick.net esta en allowed-names (gana en runtime)"; else bad "doubleclick.net no llego a allowed-names ($AL)"; fi
# otro dominio del control (no allowlisteado) SÍ queda bloqueado y NO en allowed
grep -qx "googleadservices.com" "$BL" 2>/dev/null && ! grep -qx "googleadservices.com" "$AL" 2>/dev/null && ok "otros dominios del control siguen bloqueados (no neutralizados)" || bad "googleadservices mal manejado"

# 5) expiracion: un modo 15m con expiry ya vencido -> sc_effective_mode = off (no bloquea)
. scripts/common.sh 2>/dev/null; . scripts/fetch.sh 2>/dev/null; . scripts/catalog.sh 2>/dev/null; . scripts/servicectl.sh 2>/dev/null
mkdir -p "$TR/data/service-controls"; printf 'reddit_tracking\t15m\t1\n' > "$TR/data/service-controls/state.tsv"  # expiry=1 (epoch viejo)
[ "$(sc_effective_mode reddit_tracking)" = off ] && ok "modo expirado -> effective_mode=off" || bad "expiracion no respetada"

echo ""; echo "Resumen service-enforcement: $P OK, $F FAIL"; [ "$F" -eq 0 ] && exit 0 || exit 1
