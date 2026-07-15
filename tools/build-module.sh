#!/bin/bash
##############################################################################
# tools/build-module.sh
#
# Empaqueta el modulo instalable en:
#   /home/claude/DNSCrypt-Manager-release.zip
#
# Rechaza el empaquetado (exit != 0, SIN generar el ZIP) si:
#   1. Falta el binario bin/arm64/dnscrypt-proxy, o esta vacio.
#   2. El binario no es ELF arm64 (EM_AARCH64).
#   3. Falta o esta vacio algun archivo obligatorio del modulo.
#   4. Falta la autoria "Skaymer AR" en module.prop / README.md /
#      webroot/index.html / AUDIT_REPORT.md.
#   5. Los tests (sintaxis + funcionales CLI + funcionales WebUI) no pasan
#      TODOS. Un test fallido bloquea el release; no hay "release parcial".
#   6. Algun fixture de tests/ aparece entre los archivos instalables.
#
# Si todo pasa: limpia temporales, fija permisos, y genera el ZIP con los
# archivos en la RAIZ del archivo (sin carpeta contenedora), excluyendo
# tests/ y tools/ (herramientas de desarrollo, no runtime del modulo).
#
# Uso:  bash tools/build-module.sh
# Exit: 0 si genero el ZIP. Cualquier otro valor: abortado, ver mensaje.
##############################################################################
set -u
cd "$(dirname "$0")/.." || exit 1
ROOT="$(pwd)"
OUTPUT="${DCM_OUTPUT:-/home/claude/DNSCrypt-Manager-release.zip}"

fail() { echo "" >&2; echo "ABORTADO: $*" >&2; exit 1; }
step() { echo ""; echo "=== $* ==="; }

##############################################################################
step "1) Binario arm64: presente y no vacio"
##############################################################################
BIN="$ROOT/bin/arm64/dnscrypt-proxy"
[ -f "$BIN" ] || fail "falta $BIN. Corre primero: tools/inject-binary.sh /ruta/al/dnscrypt-proxy"
SIZE=$(wc -c < "$BIN" 2>/dev/null | tr -d ' ')
[ -n "$SIZE" ] && [ "$SIZE" -gt 0 ] 2>/dev/null || fail "$BIN esta vacio (0 bytes)"
echo "  OK: $SIZE bytes"

##############################################################################
step "2) Arquitectura arm64 (EM_AARCH64) del binario"
##############################################################################
MAGIC=$(od -An -tx1 -N4 "$BIN" 2>/dev/null | tr -d ' \n')
[ "$MAGIC" = "7f454c46" ] || fail "$BIN no es un ELF valido (magic=$MAGIC)"
CLASS=$(od -An -tu1 -j4 -N1 "$BIN" 2>/dev/null | tr -d ' ')
[ "$CLASS" = "2" ] || fail "$BIN no es ELF de 64 bits (EI_CLASS=$CLASS)"
B0=$(od -An -tu1 -j18 -N1 "$BIN" | tr -d ' '); B1=$(od -An -tu1 -j19 -N1 "$BIN" | tr -d ' ')
EMACH=$((B0 + B1 * 256))
[ "$EMACH" = "183" ] || fail "arquitectura incorrecta: e_machine=$EMACH (se esperaba 183=EM_AARCH64)"
echo "  OK: ELF64 EM_AARCH64 confirmado"

##############################################################################
step "3) Archivos obligatorios: presentes y no vacios"
##############################################################################
REQUIRED_FILES="
module.prop
customize.sh
service.sh
post-fs-data.sh
boot-completed.sh
uninstall.sh
action.sh
META-INF/com/google/android/update-binary
META-INF/com/google/android/updater-script
system/bin/dnscrypt-manager
scripts/common.sh
scripts/security.sh
scripts/start.sh
scripts/stop.sh
webroot/index.html
webroot/js/app.js
webroot/js/api.js
webroot/js/validation.js
webroot/css/style.css
config/dnscrypt-proxy.toml
config/defaults/dnscrypt-proxy.toml
README.md
BINARY_INFO.md
"
MISSING=0
for f in $REQUIRED_FILES; do
  if [ ! -s "$ROOT/$f" ]; then
    echo "  FALTA o VACIO: $f" >&2
    MISSING=1
  fi
done
[ "$MISSING" -eq 0 ] || fail "faltan archivos obligatorios (ver arriba)"
echo "  OK: todos los archivos obligatorios presentes y no vacios"

##############################################################################
step "4) Autoria 'Skaymer AR' presente en los archivos requeridos"
##############################################################################
AUTHOR_FILES="module.prop README.md webroot/index.html AUDIT_REPORT.md"
MISSING_AUTHOR=0
for f in $AUTHOR_FILES; do
  if [ ! -f "$ROOT/$f" ] || ! grep -q "Skaymer AR" "$ROOT/$f"; then
    echo "  FALTA autoria 'Skaymer AR' en: $f" >&2
    MISSING_AUTHOR=1
  fi
done
[ "$MISSING_AUTHOR" -eq 0 ] || fail "falta la autoria 'Skaymer AR' en uno o mas archivos (ver arriba)"
echo "  OK: autoria presente en los 4 archivos requeridos"

##############################################################################
step "5) Tests: sintaxis + funcionales CLI + funcionales WebUI (deben pasar TODOS)"
##############################################################################
echo "  --- tests/run-syntax-checks.sh ---"
bash "$ROOT/tests/run-syntax-checks.sh" || fail "tests/run-syntax-checks.sh fallo. No hay release con tests rotos."
echo "  --- tests/smoke-test-cli.sh ---"
bash "$ROOT/tests/smoke-test-cli.sh" || fail "tests/smoke-test-cli.sh fallo. No hay release con tests rotos."
echo "  --- tests/smoke-test-security.sh ---"
bash "$ROOT/tests/smoke-test-security.sh" || fail "tests/smoke-test-security.sh fallo. No hay release con tests rotos."
echo "  --- tests/smoke-test-webui.sh ---"
bash "$ROOT/tests/smoke-test-webui.sh" || fail "tests/smoke-test-webui.sh fallo. No hay release con tests rotos."
echo "  OK: las 3 suites pasaron"

##############################################################################
step "6) Ningun fixture debe colarse en el instalable"
##############################################################################
FIXTURE_LEAK=$(python3 -c "
import os
EXCLUDE = {'tests', 'tools', '.git'}
MARK = b'ARCHIVO DE PRUEBA'
bad = []
for root, dirs, files in os.walk('$ROOT'):
    dirs[:] = [d for d in dirs if d not in EXCLUDE]
    rel = os.path.relpath(root, '$ROOT')
    if rel != '.' and rel.split(os.sep)[0] in EXCLUDE:
        continue
    for f in files:
        p = os.path.join(root, f)
        try:
            with open(p, 'rb') as fh:
                if MARK in fh.read(4096):
                    bad.append(p)
        except Exception:
            pass
print(len(bad))
for b in bad: print(b)
")
LEAK_COUNT=$(echo "$FIXTURE_LEAK" | head -n1)
if [ "$LEAK_COUNT" != "0" ]; then
  echo "$FIXTURE_LEAK" | tail -n +2 >&2
  fail "$LEAK_COUNT fixture(s) colarian en el instalable (ver arriba)"
fi
echo "  OK: ningun fixture en el arbol instalable"

##############################################################################
step "7) Limpiar temporales antes de empaquetar"
##############################################################################
find "$ROOT" -name '__pycache__' -type d -exec rm -rf {} + 2>/dev/null
find "$ROOT" -name '*.pyc' -delete 2>/dev/null
find "$ROOT" -name '.DS_Store' -delete 2>/dev/null
find "$ROOT" -name '*.tmp' -delete 2>/dev/null
find "$ROOT" -name '*.bak' -delete 2>/dev/null
find "$ROOT" \( -name '*.toml.tmp.*' -o -name 'import.toml.*' \) -delete 2>/dev/null
echo "  OK: temporales limpiados"

##############################################################################
step "8) Permisos"
##############################################################################
chmod 0755 "$ROOT"/customize.sh "$ROOT"/service.sh "$ROOT"/post-fs-data.sh \
           "$ROOT"/boot-completed.sh "$ROOT"/uninstall.sh "$ROOT"/action.sh
chmod 0755 "$ROOT"/system/bin/dnscrypt-manager
chmod 0755 "$ROOT"/scripts/*.sh
chmod 0755 "$BIN"
[ -f "$ROOT/bin/arm/dnscrypt-proxy" ] && chmod 0755 "$ROOT/bin/arm/dnscrypt-proxy"
chmod 0755 "$ROOT/META-INF/com/google/android/update-binary"
echo "  OK: permisos fijados"

##############################################################################
step "9) Empaquetar ZIP (raiz correcta, sin tests/ ni tools/)"
##############################################################################
STAGE="$(mktemp -d /tmp/dcm-build-stage.XXXXXX)"
ZIP_LOG="$STAGE/.ziplog"
cp -a "$ROOT/." "$STAGE/"
rm -rf "$STAGE/tests" "$STAGE/tools"
find "$STAGE" -name '__pycache__' -type d -exec rm -rf {} + 2>/dev/null

rm -f "$OUTPUT"
( cd "$STAGE" && zip -r -X "$OUTPUT" . -x '.*' -x '.ziplog' >"$ZIP_LOG" 2>&1 )
ZRC=$?
[ "$ZRC" -eq 0 ] && [ -f "$OUTPUT" ] || { cat "$ZIP_LOG" >&2; rm -rf "$STAGE"; fail "zip fallo (rc=$ZRC)"; }
rm -rf "$STAGE"

# Verificar que la raiz del ZIP es correcta (module.prop en la raiz, SIN
# carpeta contenedora, y SIN tests/ ni tools/ dentro).
TOPLEVEL_OK=$(unzip -l "$OUTPUT" | awk 'NR>3 {print $4}' | grep -c '^module.prop$')
LEAKED_DIRS=$(unzip -l "$OUTPUT" | awk 'NR>3 {print $4}' | grep -cE '^(tests|tools)/')
[ "$TOPLEVEL_OK" -ge 1 ] || fail "module.prop no quedo en la raiz del ZIP (carpeta contenedora incorrecta)"
[ "$LEAKED_DIRS" -eq 0 ] || fail "el ZIP contiene tests/ o tools/ ($LEAKED_DIRS entradas) -- no deberia"

echo "  OK: ZIP generado en $OUTPUT"
echo "  OK: module.prop en la raiz (sin carpeta contenedora)"
echo "  OK: sin tests/ ni tools/ dentro del ZIP"

echo ""
echo "=== RELEASE OK: $OUTPUT ==="
sha256sum "$OUTPUT"
exit 0
