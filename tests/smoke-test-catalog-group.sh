#!/bin/bash
set -u
cd "$(dirname "$0")/.." || exit 1
. tests/_tp_common.sh
tp_setup
trap 'rm -rf "$TR"' EXIT

ok() { printf '  OK   %s\n' "$1"; }
bad() { printf '  FAIL %s\n' "$1"; exit 1; }
cli() { "$SH" "$M" "$@"; }

# El fixture usa el índice real y dos entradas aisladas en el catálogo del usuario.
mkdir -p "$TR/mod/config/catalog"
cp config/catalog/blocklists.index.tsv "$TR/mod/config/catalog/blocklists.index.tsv"
cli catalog sync >/dev/null 2>&1 || bad 'no se pudo sincronizar índice de prueba'
python3 - "$TR/data/catalog/custom.tsv" <<'PY'
import csv, sys
path=sys.argv[1]
rows=[]
for source_id, name in [('test_privacy_cached','Caché preparada'),('test_privacy_empty','Sin caché')]:
    row=['']*27
    row[0]=source_id; row[1]=source_id; row[2]=name; row[3]='Fixture'
    row[4]='privacy'; row[5]='balanced'; row[6]='domains'
    row[7]='https://example.invalid/list.txt'; row[8]='MIT'; row[9]='verified'
    row[10]='0'; row[11]='good'; row[12]='0'; row[17]='2026-09-28'
    row[18]='Entrada de prueba'; row[19]='Lista de prueba'; row[20]='Privacy'
    row[22]=''; row[23]='domains'; row[24]='https://example.invalid/list.txt'
    row[25]='1'; row[26]='0'; rows.append(row)
with open(path,'a',encoding='utf-8',newline='') as f:
    csv.writer(f, delimiter='\t', lineterminator='\n').writerows(rows)
PY
mkdir -p "$TR/data/catalog/cache"
printf 'ads.test.example\n' > "$TR/data/catalog/cache/test_privacy_cached.list"

R=$(cli catalog group enable Privacy 2>&1) || bad "activar categoría: $R"
[[ "$R" == *'1 fuentes modificadas,'*'omitidas por no estar preparadas o ser incompatibles'* ]] && ok 'activa solo la fuente compatible con caché y deja las demás apagadas' || bad "resumen de activación incorrecto: $R"
grep -qxF test_privacy_cached "$TR/data/catalog/enabled.txt" && ok 'la lista preparada quedó activa' || bad 'no se activó la lista preparada'
! grep -qxF test_privacy_empty "$TR/data/catalog/enabled.txt" && ok 'una lista sin caché no se activa ni descarga' || bad 'se activó una lista sin caché'

R=$(DNSCRYPT_TEST_COMPILE_FAIL=1 cli catalog group disable Privacy 2>&1) && bad "compilación simulada debía fallar: $R"
grep -qxF test_privacy_cached "$TR/data/catalog/enabled.txt" && ok 'el fallo de compilación conserva la selección previa' || bad 'el rollback no restauró la selección previa'

R=$(cli catalog group disable Privacy 2>&1) || bad "desactivar categoría: $R"
! grep -qxF test_privacy_cached "$TR/data/catalog/enabled.txt" && ok 'desactiva la categoría sin alterar otras listas' || bad 'la lista siguió activa'

if cli catalog group enable NotAGroup >/dev/null 2>&1; then bad 'aceptó una categoría desconocida'; else ok 'rechaza una categoría desconocida'; fi
