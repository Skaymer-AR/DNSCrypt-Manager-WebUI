#!/bin/bash
set -u; cd "$(dirname "$0")/.." || exit 1; . tests/_tp_common.sh
TR="$(mktemp -d /tmp/dcm-mig.XXXXXX)"; export DNSCRYPT_TEST_MODE=1 DNSCRYPT_TEST_ROOT="$TR" DNSCRYPT_TEST_DATA_DIR="$TR/data" DNSCRYPT_TEST_MODDIR="$TR/mod"
mkdir -p "$TR/data/config" "$TR/mod/system/bin" "$TR/mod/scripts" "$TR/mod/config/catalog" "$TR/mod/config/service-controls" "$TR/mod/config/transport"
cp system/bin/dnscrypt-manager "$TR/mod/system/bin/"; cp scripts/*.sh "$TR/mod/scripts/"; cp config/catalog/*.tsv "$TR/mod/config/catalog/"; cp config/service-controls/*.json "$TR/mod/config/service-controls/"; cp config/transport/*.json "$TR/mod/config/transport/"; cp config/dnscrypt-proxy.toml "$TR/data/config/"
M="$TR/mod/system/bin/dnscrypt-manager"; SH="$(command -v sh)"; trap 'rm -rf "$TR"' EXIT
P=0;F=0; ok(){ P=$((P+1)); printf '  OK   %s\n' "$1"; }; bad(){ F=$((F+1)); printf '  FAIL %s\n' "$1"; }
# desde limpio -> schema 3
"$SH" "$M" migrate >/dev/null 2>&1
[ "$(cat "$TR/data/schema_version")" = 3 ] && ok "migra a schema 3" || bad "schema ($(cat "$TR/data/schema_version" 2>/dev/null))"
# idempotente
"$SH" "$M" migrate 2>&1 | grep -qi "ya en 3" && ok "idempotente (2da corrida no hace nada)" || bad "idem"
# nuevos dirs OFF
for d in transport captive bypass monitor service-controls apppolicy; do [ -d "$TR/data/$d" ] && ok "dir $d creado" || bad "dir $d"; done
grep -q '"enabled":false' "$TR/data/transport/anonymized.json" && ok "anonymized OFF por defecto" || bad "anon off"
grep -q '"enabled":false' "$TR/data/transport/odoh.json" && ok "odoh OFF por defecto" || bad "odoh off"
grep -q "mode	audit" "$TR/data/bypass/config.tsv" && ok "bypass en audit (no strict)" || bad "bypass"
grep -q "mode	audit" "$TR/data/monitor/config.tsv" && ok "monitor en audit" || bad "monitor"
# conserva config previa: simular un flag existente y re-migrar desde schema 2
echo 2 > "$TR/data/schema_version"; echo "example.com" > "$TR/data/security/allowlist.txt" 2>/dev/null || { mkdir -p "$TR/data/security"; echo "example.com" > "$TR/data/security/allowlist.txt"; }
"$SH" "$M" migrate >/dev/null 2>&1
[ "$(cat "$TR/data/schema_version")" = 3 ] && grep -qx "example.com" "$TR/data/security/allowlist.txt" && ok "2->3 conserva allowlist del usuario" || bad "preserva config"
# no queda backup de schema
[ -f "$TR/data/schema_version.bak" ] && bad "quedo schema_version.bak" || ok "sin backup residual de schema"
echo ""; echo "Resumen migration-v3: $P OK, $F FAIL"; [ "$F" -eq 0 ] && exit 0 || exit 1
