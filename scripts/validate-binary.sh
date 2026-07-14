#!/system/bin/sh
##############################################################################
# DNSCrypt Manager - scripts/validate-binary.sh
# Creado por Skaymer AR
#
# Funciones COMPARTIDAS de validacion de un binario dnscrypt-proxy. Este
# archivo NO tiene efectos secundarios al ser sourceado (no crea
# directorios, no valida modo test, no hace nada mas que definir
# funciones) para que pueda usarse tanto desde:
#   - system/bin/dnscrypt-manager (cmd_fetch_binary, en el dispositivo)
#   - tools/inject-binary.sh (en la maquina de desarrollo/CI)
# sin arrastrar los efectos secundarios de scripts/common.sh.
#
# Portabilidad: usa unicamente 'od', 'wc', 'grep' (sin -P/-E), y 'strings'
# SI esta disponible (con fallback a 'grep -a' si no lo esta, ya que
# Android stock no siempre trae 'strings').
##############################################################################

# validate_dnscrypt_binary <archivo>
# Verifica: existe, tamaño razonable, ELF64, EM_AARCH64, firma estatica de
# dnscrypt-proxy. Devuelve 0 si TODO pasa, 1 si algo falla (mensaje en stderr
# indicando cual). No ejecuta el binario (eso es un chequeo aparte, best-effort).
validate_dnscrypt_binary() {
  _vdb_f="$1"

  if [ ! -f "$_vdb_f" ]; then
    echo "no existe: $_vdb_f" >&2
    return 1
  fi

  _vdb_size=$(wc -c < "$_vdb_f" 2>/dev/null | tr -d ' ')
  if [ -z "$_vdb_size" ] || [ "$_vdb_size" -le 1000 ] 2>/dev/null; then
    echo "tamaño no razonable para dnscrypt-proxy: ${_vdb_size:-0} bytes" >&2
    return 1
  fi

  _vdb_magic=$(od -An -tx1 -N4 "$_vdb_f" 2>/dev/null | tr -d ' \n')
  if [ "$_vdb_magic" != "7f454c46" ]; then
    echo "no es un ELF valido (magic bytes: ${_vdb_magic:-ilegible})" >&2
    return 1
  fi

  _vdb_class=$(od -An -tu1 -j4 -N1 "$_vdb_f" 2>/dev/null | tr -d ' ')
  if [ "$_vdb_class" != "2" ]; then
    echo "no es un ELF de 64 bits (EI_CLASS=$_vdb_class, se esperaba 2)" >&2
    return 1
  fi

  _vdb_b0=$(od -An -tu1 -j18 -N1 "$_vdb_f" 2>/dev/null | tr -d ' ')
  _vdb_b1=$(od -An -tu1 -j19 -N1 "$_vdb_f" 2>/dev/null | tr -d ' ')
  _vdb_emach=$((_vdb_b0 + _vdb_b1 * 256))
  if [ "$_vdb_emach" != "183" ]; then
    echo "arquitectura incorrecta: e_machine=$_vdb_emach (se esperaba 183 = EM_AARCH64)" >&2
    return 1
  fi

  if command -v strings >/dev/null 2>&1; then
    if ! strings -a "$_vdb_f" 2>/dev/null | grep -q -e 'dnscrypt-proxy' -e 'DNSCrypt/dnscrypt-proxy' -e 'jedisct1/dnscrypt-proxy'; then
      echo "no se encontro ninguna cadena identificatoria de dnscrypt-proxy (via strings)" >&2
      return 1
    fi
  else
    # Fallback portable sin 'strings' (no siempre presente en Android
    # stock): grep -a trata el binario como texto; para una subcadena
    # ASCII simple sin bytes de salto de linea (como "dnscrypt-proxy"),
    # encuentra la coincidencia igual, este donde este en el archivo.
    if ! grep -aq -e 'dnscrypt-proxy' "$_vdb_f" 2>/dev/null; then
      echo "no se encontro la cadena 'dnscrypt-proxy' (fallback grep -a, sin 'strings')" >&2
      return 1
    fi
  fi

  return 0
}

# safe_list_archive_entries <archivo> <tipo:zip|targz>
# Imprime, una por linea, las entradas del archivo SIN extraerlo. Uso
# interno de safe_extract_archive para el chequeo de path traversal.
_vdb_list_archive_entries() {
  _f="$1"; _kind="$2"
  case "$_kind" in
    zip)
      if have unzip; then unzip -Z1 "$_f" 2>/dev/null
      elif [ -n "$BUSYBOX" ]; then $BUSYBOX unzip -l "$_f" 2>/dev/null | awk 'NR>3 {print $4}'
      fi ;;
    targz)
      have tar && tar -tzf "$_f" 2>/dev/null ;;
  esac
}

# safe_extract_archive <archivo> <tipo:zip|targz> <destino>
# Lista las entradas ANTES de extraer y rechaza el archivo completo si
# alguna entrada es una ruta absoluta o contiene '..' (path traversal).
# Solo si TODAS las entradas son seguras, extrae. Devuelve 0 si extrajo,
# 1 si rechazo o fallo.
safe_extract_archive() {
  _sea_f="$1"; _sea_kind="$2"; _sea_dest="$3"

  _sea_entries=$(_vdb_list_archive_entries "$_sea_f" "$_sea_kind")
  if [ -z "$_sea_entries" ]; then
    echo "no se pudieron listar las entradas del archivo (o esta vacio)" >&2
    return 1
  fi

  _sea_bad=0
  printf '%s\n' "$_sea_entries" | while IFS= read -r _entry; do
    [ -z "$_entry" ] && continue
    case "$_entry" in
      /*) echo "entrada con ruta absoluta rechazada: $_entry" >&2; exit 91 ;;
      ../*|*/../*|..) echo "entrada con path traversal ('..') rechazada: $_entry" >&2; exit 91 ;;
    esac
  done
  _sea_rc=$?
  if [ "$_sea_rc" -eq 91 ]; then
    return 1
  fi

  mkdir -p "$_sea_dest" 2>/dev/null
  case "$_sea_kind" in
    zip)
      if have unzip; then unzip -oq "$_sea_f" -d "$_sea_dest" 2>/dev/null
      elif [ -n "$BUSYBOX" ]; then $BUSYBOX unzip -oq "$_sea_f" -d "$_sea_dest" 2>/dev/null
      else echo "no hay unzip disponible para extraer" >&2; return 1; fi ;;
    targz)
      tar -xzf "$_sea_f" -C "$_sea_dest" 2>/dev/null ;;
  esac
}
