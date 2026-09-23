#!/bin/bash
# Creado por Skaymer AR. Regresión: instalación actualizada, schema 3 y sin índice.
# No red, no daemon, nunca toca /data/adb. Puede probar el ZIP FINAL con
# DCM_TEST_MODULE_ZIP=/ruta/paquete.zip bash tests/smoke-test-catalog-bootstrap.sh
set -eu
cd "$(dirname "$0")/.."
SRC_ROOT="$PWD"
TR="$(mktemp -d /tmp/dcm-catalog-bootstrap.XXXXXX)"
trap 'rm -rf "$TR"' EXIT
export DNSCRYPT_TEST_MODE=1 DNSCRYPT_TEST_ROOT="$TR"
export DNSCRYPT_TEST_DATA_DIR="$TR/data" DNSCRYPT_TEST_MODDIR="$TR/mod"
mkdir -p "$TR/mod" "$TR/data/config" "$TR/data/security" "$TR/data/catalog/cache"
if [ -n "${DCM_TEST_MODULE_ZIP:-}" ]; then
  unzip -q "$DCM_TEST_MODULE_ZIP" -d "$TR/mod"
else
  mkdir -p "$TR/mod/scripts" "$TR/mod/system/bin" "$TR/mod/config/catalog"
  cp scripts/*.sh "$TR/mod/scripts/"
  cp system/bin/dnscrypt-manager "$TR/mod/system/bin/"
  cp config/catalog/*.tsv "$TR/mod/config/catalog/"
fi
SH_BIN="$(command -v sh)"
M="$TR/mod/system/bin/dnscrypt-manager"
INDEX="$TR/data/catalog/blocklists.index.tsv"
SOURCE="$TR/mod/config/catalog/blocklists.index.tsv"
cli() { "$SH_BIN" "$M" "$@"; }
inlib() { "$SH_BIN" -c '. "$DNSCRYPT_TEST_MODDIR/scripts/common.sh"; . "$DNSCRYPT_TEST_MODDIR/scripts/security.sh"; . "$DNSCRYPT_TEST_MODDIR/scripts/catalog.sh"; '"$1"; }
PASS=0; FAIL=0
ok() { PASS=$((PASS+1)); printf '  OK   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; }
groups_valid() {
  node -e 'const fs=require("fs");const g=JSON.parse(fs.readFileSync(process.argv[1])).groups;
    for (const [key,count] of [["Security",44],["Privacy",85],["ParentalControl",67],["dcm",55],["rethink_unassigned",1]])
      if (!g.some(e=>e.key===key && e.count===count)) process.exit(1);' "$1"
}

printf '3\n' > "$TR/data/schema_version"
cp config/dnscrypt-proxy.toml "$TR/data/config/dnscrypt-proxy.toml"
printf 'keep.allowed.example\n' > "$TR/data/security/allowlist.txt"
printf 'keep.blocked.example\n' > "$TR/data/security/blocked-names.txt"
printf 'hagezi_multi_light\n' > "$TR/data/catalog/enabled.txt"
printf 'keep.cached.example\n' > "$TR/data/catalog/cache/hagezi_multi_light.list"
printf 'hagezi_multi_light\tverified\n' > "$TR/data/catalog/source-status.tsv"
printf 'sentinel-custom-source\n' > "$TR/data/catalog/custom.tsv"
# No custom row in the count test; keep custom preservation tested separately.
mv "$TR/data/catalog/custom.tsv" "$TR/custom.saved"
for f in schema_version config/dnscrypt-proxy.toml security/allowlist.txt security/blocked-names.txt catalog/enabled.txt catalog/cache/hagezi_multi_light.list catalog/source-status.tsv; do
  (cd "$TR/data" && sha256sum "$f")
done > "$TR/user-state.sha256"

echo '== Apertura de Listas sin migrate, con schema 3 y sin índice =='
if cli catalog groups --json > "$TR/groups.json" 2> "$TR/groups.err" && groups_valid "$TR/groups.json"; then
  ok 'groups recupera el índice ausente y muestra las cinco categorías'
else bad 'groups no recuperó el índice (el fallo de la captura)'; fi
if [ -s "$INDEX" ] && cmp -s "$SOURCE" "$INDEX"; then ok 'índice recuperado idéntico al incluido en el módulo'; else bad 'índice no recuperado'; fi
if [ ! -s "$TR/groups.err" ]; then ok 'JSON limpio, sin errores awk'; else bad 'stderr contiene error'; fi
if cli catalog list --json --source-group Security > "$TR/security.json" 2> "$TR/security.err" &&
  node -e 'const d=JSON.parse(require("fs").readFileSync(process.argv[1])); if(d.entries.length!==44 || d.entries.some(e=>e.source_group!=="Security")) process.exit(1)' "$TR/security.json"; then
  ok 'Seguridad carga 44 fichas reales sin búsqueda'
else bad 'no se cargaron las fichas de Seguridad'; fi

echo '== migrate debe sincronizar metadatos aunque el esquema ya sea 3 =='
[ ! -f "$INDEX" ] || mv "$INDEX" "$TR/index.before-migrate"
if cli migrate > "$TR/migrate.log" 2>&1 && cmp -s "$SOURCE" "$INDEX"; then ok 'migrate schema 3 repara el índice ausente'; else bad 'migrate omitió la reparación con schema 3'; fi
if (cd "$TR/data" && sha256sum -c "$TR/user-state.sha256" >/dev/null 2>&1); then ok 'config, allowlist, bloqueo activo, caché y selecciones intactos'; else bad 'estado del usuario modificado'; fi
# Índice válido pero anterior: migrate debe actualizar los metadatos, no las preferencias.
head -n 2 "$SOURCE" > "$INDEX"
if cli migrate > "$TR/migrate-update.log" 2>&1 && cmp -s "$SOURCE" "$INDEX"; then ok 'migrate schema 3 actualiza un catálogo antiguo'; else bad 'catálogo viejo no actualizado'; fi

echo '== Archivo vacío y fallos de sincronización seguros =='
: > "$INDEX"
if cli catalog list --json --source-group Privacy > "$TR/privacy.json" 2> "$TR/privacy.err" &&
  node -e 'const d=JSON.parse(require("fs").readFileSync(process.argv[1]));if(d.entries.length!==85)process.exit(1)' "$TR/privacy.json"; then
  ok 'consulta directa recupera índice vacío sin depender de groups ni migrate'
else bad 'índice vacío no recuperado'; fi
cp "$SOURCE" "$INDEX"
cp "$INDEX" "$TR/index.valid"
printf '# simulated new local module revision\n' >> "$SOURCE"
if inlib 'cp() { return 1; }; cat_sync_index' > "$TR/copy-failed.log" 2>&1; then bad 'fallo de copia se informó como éxito';
elif cmp -s "$INDEX" "$TR/index.valid"; then ok 'fallo de copia devuelve error y conserva índice anterior'; else bad 'fallo de copia destruyó índice'; fi
if inlib 'mv() { return 1; }; cat_sync_index' > "$TR/rename-failed.log" 2>&1; then bad 'fallo de rename se informó como éxito';
elif cmp -s "$INDEX" "$TR/index.valid"; then ok 'fallo de rename devuelve error y conserva índice anterior'; else bad 'fallo de rename destruyó índice'; fi
if cli catalog sync > "$TR/sync.log" 2>&1 && cmp -s "$SOURCE" "$INDEX"; then ok 'sync explícito actualiza correctamente'; else bad 'sync explícito'; fi
mv "$SOURCE" "$TR/module-index.saved"
if cli catalog sync > "$TR/missing.log" 2>&1; then bad 'sync informó éxito sin fuente en el módulo';
elif [ -s "$INDEX" ] && ! grep -q '^OK:' "$TR/missing.log"; then ok 'fuente ausente produce error honesto sin borrar el índice'; else bad 'error ausente o índice perdido'; fi
if cli catalog groups --json > "$TR/cached.json" 2> "$TR/cached.err" && groups_valid "$TR/cached.json"; then
  ok 'índice persistente válido sigue legible aunque no esté el del módulo'
else bad 'consulta de índice persistente'; fi
mv "$INDEX" "$TR/index.saved"
if cli catalog groups --json > "$TR/both-missing.json" 2> "$TR/both-missing.err"; then bad 'ambos índices ausentes devolvieron éxito';
elif [ ! -s "$TR/both-missing.json" ] && grep -q 'ERROR:' "$TR/both-missing.err"; then ok 'sin índices: error explícito y sin JSON falso/vacío'; else bad 'salida confusa sin índices'; fi
mv "$TR/module-index.saved" "$SOURCE"
mv "$TR/custom.saved" "$TR/data/catalog/custom.tsv"
if cli catalog sync > "$TR/final-sync.log" 2>&1 && grep -qx 'sentinel-custom-source' "$TR/data/catalog/custom.tsv" &&
  (cd "$TR/data" && sha256sum -c "$TR/user-state.sha256" >/dev/null 2>&1); then
  ok 'reparación nunca borra fuentes personales ni estado del usuario'
else bad 'fuentes personales o estado alterados'; fi
echo "Resumen catalog-bootstrap: $PASS OK, $FAIL FAIL"
[ "$FAIL" -eq 0 ]
