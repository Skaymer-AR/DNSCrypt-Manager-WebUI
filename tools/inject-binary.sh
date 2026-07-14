#!/bin/bash
##############################################################################
# tools/inject-binary.sh
#
# Valida un binario oficial de dnscrypt-proxy y lo incorpora al modulo:
#   bin/arm64/dnscrypt-proxy
#
# Verificaciones, en orden (cualquiera que falle ABORTA sin copiar nada):
#   1. El argumento es un archivo regular, existe y NO esta vacio.
#   2. Es un ELF valido (magic bytes 7F 45 4C 46), verificado por bytes
#      crudos (no depende de que 'file' este instalado) y ademas
#      contrastado con 'file'/'readelf' si estan disponibles.
#   3. Es ELF de 64 bits y su e_machine es EM_AARCH64 (183 / 0xB7). Se lee
#      directamente de la cabecera ELF (offsets 4 y 18-19), no se asume
#      nada de herramientas externas.
#   4. Firma estatica: 'strings' sobre el binario debe contener alguna
#      cadena identificatoria de dnscrypt-proxy (el propio nombre del
#      proyecto, o su import path de Go). Este chequeo NO requiere
#      ejecutar el binario, asi que funciona igual en un host x86_64.
#   5. Mejor esfuerzo: si el host es aarch64, o hay un emulador
#      qemu-aarch64(-static) en el PATH, se intenta ejecutar
#      '<binario> -version' y capturar la salida real. Si no es posible
#      (arquitectura del host no coincide y no hay emulador), se omite
#      SIN abortar y se dejar constancia explicita en BINARY_INFO.md de
#      que la version no fue confirmada por ejecucion.
#   6. SHA-256 real del archivo (siempre, nunca inventado).
#
# Si TODO lo anterior pasa: copia a bin/arm64/dnscrypt-proxy, chmod 0755,
# borra el placeholder bin/arm64/COLOCAR_BINARIO_AQUI.md (ya no hace
# falta), y reescribe la tabla de BINARY_INFO.md con los datos reales.
#
# Uso:
#   ./tools/inject-binary.sh /ruta/al/dnscrypt-proxy
#
# Exit codes: 0 = inyectado OK. 1 = abortado (ver mensaje). 2 = uso incorrecto.
##############################################################################
set -u

MODROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST_DIR="$MODROOT/bin/arm64"
DEST_BIN="$DEST_DIR/dnscrypt-proxy"
PLACEHOLDER="$DEST_DIR/COLOCAR_BINARIO_AQUI.md"
INFO_MD="$MODROOT/BINARY_INFO.md"
VALIDATE_LIB="$MODROOT/scripts/validate-binary.sh"

die() { echo "ABORTADO: $*" >&2; exit 1; }
note() { echo "  - $*"; }

[ $# -eq 1 ] || { echo "Uso: $0 /ruta/al/dnscrypt-proxy" >&2; exit 2; }
SRC="$1"

[ -f "$VALIDATE_LIB" ] || die "falta $VALIDATE_LIB (funcion compartida de validacion)."
# shellcheck source=/dev/null
. "$VALIDATE_LIB"
have() { command -v "$1" >/dev/null 2>&1; }

echo "=== 1-4) Existencia, tamaño, ELF64, EM_AARCH64 y firma estatica ==="
echo "        (funcion compartida validate_dnscrypt_binary, la misma que usa"
echo "         'dnscrypt-manager fetch-binary' en el dispositivo)"
_VB_ERR="$(mktemp)"
if ! validate_dnscrypt_binary "$SRC" >"$_VB_ERR" 2>&1; then
  _msg=$(cat "$_VB_ERR"); rm -f "$_VB_ERR"
  die "$_msg"
fi
rm -f "$_VB_ERR"
SIZE=$(wc -c < "$SRC" 2>/dev/null | tr -d ' ')
note "tamaño: $SIZE bytes"
note "ELF64 EM_AARCH64: OK"
if command -v strings >/dev/null 2>&1; then
  MATCH=$(strings -a "$SRC" 2>/dev/null | grep -e 'dnscrypt-proxy' -e 'DNSCrypt/dnscrypt-proxy' -e 'jedisct1/dnscrypt-proxy' | head -n1)
  note "cadena identificatoria encontrada: \"$MATCH\""
else
  note "firma estatica confirmada via 'grep -a' (fallback: 'strings' no disponible en este host)"
fi
if command -v file >/dev/null 2>&1; then
  note "file(1): $(file -b "$SRC" 2>/dev/null)"
fi
if command -v readelf >/dev/null 2>&1; then
  note "readelf: $(readelf -h "$SRC" 2>/dev/null | grep -E 'Class|Machine' | tr '\n' ' ')"
fi

echo "=== 5) Version por ejecucion (mejor esfuerzo) ==="
VERSION_STR=""
VERSION_METHOD="no verificado por ejecucion"
HOST_ARCH="$(uname -m 2>/dev/null)"
EXEC_CANDIDATE=""
if [ "$HOST_ARCH" = "aarch64" ] || [ "$HOST_ARCH" = "arm64" ]; then
  EXEC_CANDIDATE="$SRC"
  note "host es $HOST_ARCH: se puede ejecutar directo"
elif command -v qemu-aarch64-static >/dev/null 2>&1; then
  EXEC_CANDIDATE="qemu-aarch64-static $SRC"
  note "se encontro qemu-aarch64-static: se intenta emulacion"
elif command -v qemu-aarch64 >/dev/null 2>&1; then
  EXEC_CANDIDATE="qemu-aarch64 $SRC"
  note "se encontro qemu-aarch64: se intenta emulacion"
else
  note "host es $HOST_ARCH y no hay emulador aarch64 disponible: SE OMITE la ejecucion (esto es 'cuando sea posible', no es un aborto)."
fi
if [ -n "$EXEC_CANDIDATE" ]; then
  chmod +x "$SRC" 2>/dev/null
  if OUT=$($EXEC_CANDIDATE -version 2>&1); then
    if printf '%s' "$OUT" | grep -qiE 'dnscrypt'; then
      VERSION_STR=$(printf '%s' "$OUT" | head -n1)
      VERSION_METHOD="ejecucion real (-version)"
      note "salida de -version: $VERSION_STR"
    else
      die "el binario se ejecuto pero '-version' no menciona 'dnscrypt' (salida: $OUT). No parece ser dnscrypt-proxy."
    fi
  else
    note "no se pudo ejecutar (rc=$?); se continua solo con la firma estatica del paso 4."
  fi
fi
# Fallback adicional: intentar extraer un numero de version tipo X.Y.Z
# cercano al nombre del proyecto en las cadenas, aunque no se haya podido
# ejecutar. Es solo informativo, nunca reemplaza la verificacion real.
if [ -z "$VERSION_STR" ]; then
  GUESS=$(strings -a "$SRC" | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' | head -n1)
  [ -n "$GUESS" ] && { VERSION_STR="$GUESS (extraido de strings, sin confirmar por ejecucion)"; note "posible version en strings: $GUESS"; }
fi

echo "=== 6) SHA-256 ==="
if command -v sha256sum >/dev/null 2>&1; then
  SHA256=$(sha256sum "$SRC" | awk '{print $1}')
elif command -v shasum >/dev/null 2>&1; then
  SHA256=$(shasum -a 256 "$SRC" | awk '{print $1}')
else
  die "no hay sha256sum ni shasum disponibles para calcular el hash."
fi
note "SHA-256: $SHA256"

echo "=== 7) Copiando a $DEST_BIN ==="
mkdir -p "$DEST_DIR"
cp -f "$SRC" "$DEST_BIN" || die "no se pudo copiar a $DEST_BIN"
chmod 0755 "$DEST_BIN"
if [ -f "$PLACEHOLDER" ]; then
  rm -f "$PLACEHOLDER"
  note "placeholder $PLACEHOLDER eliminado (ya no hace falta)"
fi
note "copiado y con permiso 0755"

echo "=== 8) Actualizando BINARY_INFO.md ==="
ASSET_NAME="$(basename "$SRC")"
INJECT_DATE="$(date '+%Y-%m-%d %H:%M:%S %Z')"
cat > "$INFO_MD" << EOF_INFO
# Binario dnscrypt-proxy — estado y procedimiento

**DNSCrypt Manager — Creado por Skaymer AR**

## Estado en este arbol

**Binario presente e inyectado por \`tools/inject-binary.sh\`.**

## Registro (generado automaticamente por inject-binary.sh; no editado a mano)

| Campo | Valor |
|---|---|
| Version                      | ${VERSION_STR:-desconocida (ni ejecucion ni strings la revelaron)} |
| Metodo de verificacion       | $VERSION_METHOD + firma estatica de cadenas (paso 4) |
| Arquitectura                 | arm64 (EM_AARCH64, confirmado por cabecera ELF) |
| Archivo de origen (nombre)   | $ASSET_NAME |
| Tamaño                       | $SIZE bytes |
| SHA-256                      | \`$SHA256\` |
| Fecha de inyeccion           | $INJECT_DATE |
| Host que inyecto             | $(uname -a 2>/dev/null) |

## Como reproducir esta verificacion

\`\`\`sh
sha256sum "$ASSET_NAME"
# Debe imprimir: $SHA256
\`\`\`

Compara este hash contra el publicado en la pagina de releases oficial de
dnscrypt-proxy (https://github.com/DNSCrypt/dnscrypt-proxy/releases) antes
de confiar en este binario para un dispositivo real.

## Nota de compatibilidad

La CLI (\`start\`, \`config validate\`) ejecuta
\`dnscrypt-proxy -config X -check\` antes de arrancar: si esta version
cambio alguna clave del TOML por defecto, \`-check\` lo va a señalar con
el nombre exacto de la opcion afectada.
EOF_INFO
note "BINARY_INFO.md reescrito con datos reales (nunca inventados)"

echo
echo "=== OK: binario inyectado correctamente ==="
echo "  Destino  : $DEST_BIN"
echo "  SHA-256  : $SHA256"
echo "  Version  : ${VERSION_STR:-no confirmada}"
exit 0
