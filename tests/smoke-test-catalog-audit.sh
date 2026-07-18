#!/bin/bash
set -u; cd "$(dirname "$0")/.." || exit 1; . tests/_tp_common.sh; tp_setup
mkdir -p "$TR/mod/config/catalog"; cp config/catalog/*.tsv "$TR/mod/config/catalog/"; trap 'rm -rf "$TR"' EXIT
P=0;F=0; ok(){ P=$((P+1)); printf '  OK   %s\n' "$1"; }; bad(){ F=$((F+1)); printf '  FAIL %s\n' "$1"; }
R=$("$SH" "$M" catalog audit 2>&1)
printf '%s\n' "$R" | grep -qE "total_sources        : [0-9]+" && ok "reporta total_sources" || bad "total"
printf '%s\n' "$R" | grep -q "duplicate_urls       : 0" && ok "sin URLs duplicadas" || bad "dup"
printf '%s\n' "$R" | grep -q "missing_license      : 0" && ok "sin licencias faltantes" || bad "lic"
printf '%s\n' "$R" | grep -qE "broken_sources       : [0-9]+" && ok "cuenta broken" || bad "broken"
printf '%s\n' "$R" | grep -qi "verified.*solo tras descarga runtime" && ok "aclara: verified solo runtime, nunca CI" || bad "verified note"
# gate: audit devuelve 0 (sin dup ni formato desconocido)
"$SH" "$M" catalog audit >/dev/null 2>&1 && ok "gate OK (rc=0 sin dup/formato)" || bad "gate rc"
echo ""; echo "Resumen catalog-audit: $P OK, $F FAIL"; [ "$F" -eq 0 ] && exit 0 || exit 1
