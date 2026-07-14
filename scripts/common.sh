#!/system/bin/sh
##############################################################################
# DNSCrypt Manager - scripts/common.sh
# Creado por Skaymer AR
# Libreria compartida. La sourcean la CLI y los wrappers. NO ejecutable sola.
##############################################################################

# ----------------------------------------------------------------------------
# Rutas de PRODUCCION (valores por defecto; SIEMPRE estos en un telefono real)
# ----------------------------------------------------------------------------
MODULE_ID="dnscrypt_manager"
MODDIR="/data/adb/modules/$MODULE_ID"
DATA_DIR="/data/adb/dnscrypt-manager"

##############################################################################
# MODO DE PRUEBAS — EXCLUSIVO de tests/*.sh. NO es una funcion de producto.
#
# Se activa UNICAMENTE con la variable de entorno DNSCRYPT_TEST_MODE=1,
# seteada por un script de test antes de invocar la CLI. Nunca por la
# WebUI (la WebUI solo dispara cadenas de comando FIJAS via ksu.exec, que
# no permiten inyectar variables de entorno arbitrarias) y nunca por
# argumentos de linea de comandos de dnscrypt-manager.
#
# En este modo son OBLIGATORIAS tres variables:
#   DNSCRYPT_TEST_ROOT      raiz del entorno de prueba (debe existir)
#   DNSCRYPT_TEST_DATA_DIR  debe ser descendiente REAL de TEST_ROOT
#   DNSCRYPT_TEST_MODDIR    debe ser descendiente REAL de TEST_ROOT
#
# Validacion en TRES capas:
#   1. Rechazo de la cadena CRUDA: vacia, no absoluta, cualquier '..'
#      literal, o cualquiera de los destinos peligrosos conocidos
#      (/, /data, /system, /vendor, /root, /etc, /home) como prefijo.
#   2. Canonicalizacion real (resuelve symlinks) via 'readlink -f' (o
#      'cd + pwd -P' como respaldo portable).
#   3. Verificacion de que, ya canonicalizados, DATA_DIR y MODDIR sean
#      descendientes REALES de TEST_ROOT (no solo coincidencia de
#      prefijo de string: se compara componente por componente).
#
# Caso que DEBE fallar explicitamente: DNSCRYPT_TEST_DATA_DIR con
# "/tmp/../data/adb/test" se rechaza en la capa 1 (contiene '..' crudo),
# sin llegar siquiera a canonicalizar.
##############################################################################

_dcm_reject_dangerous_path() {
  # Capa 1: rechazo por CADENA CRUDA, antes de canonicalizar.
  case "$1" in
    "") return 1 ;;
    /) return 1 ;;
    *..*) return 1 ;;
  esac
  case "$1" in
    /*) : ;;                        # debe ser absoluta
    *)  return 1 ;;
  esac
  case "$1" in
    /data|/data/*)     return 1 ;;
    /system|/system/*) return 1 ;;
    /vendor|/vendor/*) return 1 ;;
    /root|/root/*)     return 1 ;;
    /etc|/etc/*)        return 1 ;;
    /home|/home/*)      return 1 ;;
  esac
  return 0
}

_dcm_canon() {
  # Canonicaliza (resuelve symlinks) de forma portable. Requiere que la
  # ruta YA EXISTA (los tests crean sus directorios ANTES de invocar la
  # CLI). 'readlink -f' esta en coreutils/busybox/toybox; si no esta
  # disponible, cae a 'cd + pwd -P' (POSIX puro).
  _p="$1"
  if command -v readlink >/dev/null 2>&1; then
    _r=$(readlink -f "$_p" 2>/dev/null)
    if [ -n "$_r" ]; then printf '%s\n' "$_r"; return 0; fi
  fi
  if [ -d "$_p" ]; then
    ( cd "$_p" 2>/dev/null && pwd -P )
    return 0
  fi
  return 1
}

_dcm_is_descendant() {
  # $1 = ruta candidata (ya canonicalizada), $2 = raiz (ya canonicalizada).
  # Compara con limite de componente real (no solo prefijo de string):
  # "/tmp/foo2" NO es descendiente de "/tmp/foo" aunque comparta prefijo.
  [ "$1" = "$2" ] && return 0
  _rest="${1#"$2"/}"
  [ "$_rest" != "$1" ] && [ -n "$_rest" ] && return 0
  return 1
}

if [ "${DNSCRYPT_TEST_MODE:-0}" = "1" ]; then
  _raw_root="${DNSCRYPT_TEST_ROOT:-}"
  _raw_data="${DNSCRYPT_TEST_DATA_DIR:-}"
  _raw_mod="${DNSCRYPT_TEST_MODDIR:-}"

  for _pair in "DNSCRYPT_TEST_ROOT:$_raw_root" "DNSCRYPT_TEST_DATA_DIR:$_raw_data" "DNSCRYPT_TEST_MODDIR:$_raw_mod"; do
    _name="${_pair%%:*}"; _val="${_pair#*:}"
    if ! _dcm_reject_dangerous_path "$_val"; then
      echo "FATAL: $_name invalido o peligroso (crudo): '$_val'" >&2
      exit 90
    fi
  done

  _c_root=$(_dcm_canon "$_raw_root") || { echo "FATAL: DNSCRYPT_TEST_ROOT no existe o no se pudo canonicalizar: '$_raw_root'" >&2; exit 90; }
  _c_data=$(_dcm_canon "$_raw_data") || { echo "FATAL: DNSCRYPT_TEST_DATA_DIR no existe o no se pudo canonicalizar: '$_raw_data'" >&2; exit 90; }
  _c_mod=$(_dcm_canon "$_raw_mod")   || { echo "FATAL: DNSCRYPT_TEST_MODDIR no existe o no se pudo canonicalizar: '$_raw_mod'" >&2; exit 90; }

  if ! _dcm_reject_dangerous_path "$_c_root"; then
    echo "FATAL: DNSCRYPT_TEST_ROOT resuelve (via symlink) a una ruta peligrosa: '$_c_root'" >&2
    exit 90
  fi
  if ! _dcm_is_descendant "$_c_data" "$_c_root"; then
    echo "FATAL: DNSCRYPT_TEST_DATA_DIR ('$_c_data') no es descendiente real de DNSCRYPT_TEST_ROOT ('$_c_root')" >&2
    exit 90
  fi
  if ! _dcm_is_descendant "$_c_mod" "$_c_root"; then
    echo "FATAL: DNSCRYPT_TEST_MODDIR ('$_c_mod') no es descendiente real de DNSCRYPT_TEST_ROOT ('$_c_root')" >&2
    exit 90
  fi

  DATA_DIR="$_c_data"
  MODDIR="$_c_mod"
fi

CONF_DIR="$DATA_DIR/config"
LOG_DIR="$DATA_DIR/logs"
BACKUP_DIR="$DATA_DIR/backups"
RUN_DIR="$DATA_DIR/run"
PERSIST_BIN_DIR="$DATA_DIR/bin"

TOML="$CONF_DIR/dnscrypt-proxy.toml"
PIDFILE="$RUN_DIR/dnscrypt-proxy.pid"
STATE_FILE="$RUN_DIR/state.env"
DISABLE_FLAG="$DATA_DIR/disable"
NOREDIR_FLAG="$DATA_DIR/no-redirect"
RULES_TAG_FILE="$RUN_DIR/rules.applied"

DAEMON_LOG="$LOG_DIR/dnscrypt-proxy.log"
CLI_LOG="$LOG_DIR/manager.log"
LOG_MAX_BYTES=524288

# Cadenas/tabla PROPIAS. Jamas tocamos cadenas del sistema.
CHAIN_OUTPUT="DNSCRYPT_OUTPUT"      # iptables/ip6tables, tabla nat
CHAIN_REDIRECT="DNSCRYPT_REDIRECT"  # iptables, tabla nat (PREROUTING opt-in)
CHAIN_FILTER6="DNSCRYPT_FILTER6"    # ip6tables, tabla FILTER (modo block v6)
NFT_TABLE="dnscrypt_manager"        # nftables: tabla inet propia

mkdir -p "$CONF_DIR" "$LOG_DIR" "$BACKUP_DIR" "$RUN_DIR" "$PERSIST_BIN_DIR" 2>/dev/null

# ----------------------------------------------------------------------------
# Deteccion de herramientas
# ----------------------------------------------------------------------------
have() { command -v "$1" >/dev/null 2>&1; }

BUSYBOX=""
have busybox && BUSYBOX="busybox"

# Backend de firewall:
#  - Si hay iptables, se usa iptables/ip6tables (en Android moderno suele ser
#    iptables-nft por debajo; usarlo evita mezclar dos frontends).
#  - Si NO hay iptables pero si nft, se usan reglas nftables nativas.
#  - Si no hay ninguno: "none" (redirect debe FALLAR con error claro).
detect_firewall() {
  if have iptables; then echo "iptables"
  elif have nft;    then echo "nft"
  else echo "none"; fi
}

b64d() {
  if have base64; then base64 -d 2>/dev/null
  elif [ -n "$BUSYBOX" ]; then $BUSYBOX base64 -d 2>/dev/null
  else return 127; fi
}
b64e() {
  if have base64; then base64 2>/dev/null | tr -d '\n'
  elif [ -n "$BUSYBOX" ]; then $BUSYBOX base64 2>/dev/null | tr -d '\n'
  else return 127; fi
}

# ----------------------------------------------------------------------------
# Resolucion del binario dnscrypt-proxy
# Prioridad: persistente (actualizable por el usuario) > binario del modulo.
# ----------------------------------------------------------------------------
resolve_bin() {
  if [ -x "$PERSIST_BIN_DIR/dnscrypt-proxy" ]; then
    echo "$PERSIST_BIN_DIR/dnscrypt-proxy"; return 0
  fi
  _abi="arm64"
  case "$(uname -m 2>/dev/null)" in
    armv7*|armv8l|arm) _abi="arm" ;;
  esac
  if [ -x "$MODDIR/bin/$_abi/dnscrypt-proxy" ]; then
    echo "$MODDIR/bin/$_abi/dnscrypt-proxy"; return 0
  fi
  for _c in "$MODDIR/bin/arm64/dnscrypt-proxy" "$MODDIR/bin/arm/dnscrypt-proxy"; do
    [ -f "$_c" ] && { echo "$_c"; return 0; }
  done
  return 1
}

# ----------------------------------------------------------------------------
# Logging con rotacion simple
# ----------------------------------------------------------------------------
rotate_if_big() {
  _f="$1"
  [ -f "$_f" ] || return 0
  _sz=$(wc -c < "$_f" 2>/dev/null || echo 0)
  if [ "$_sz" -gt "$LOG_MAX_BYTES" ] 2>/dev/null; then
    mv -f "$_f" "$_f.1" 2>/dev/null
    : > "$_f" 2>/dev/null
  fi
}

log_msg() {
  rotate_if_big "$CLI_LOG"
  echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$CLI_LOG" 2>/dev/null
}

# ----------------------------------------------------------------------------
# Flags de estado (clave=valor)
# ----------------------------------------------------------------------------
get_flag() {
  [ -f "$STATE_FILE" ] || { echo ""; return 0; }
  grep "^$1=" "$STATE_FILE" 2>/dev/null | tail -n1 | cut -d= -f2-
}

set_flag() {
  _k=$(printf '%s' "$1" | tr -cd 'a-zA-Z0-9_')
  _v=$(printf '%s' "$2" | tr -cd 'a-zA-Z0-9_.:-')
  [ -f "$STATE_FILE" ] || : > "$STATE_FILE"
  if grep -q "^$_k=" "$STATE_FILE" 2>/dev/null; then
    _tmp="$STATE_FILE.tmp.$$"
    grep -v "^$_k=" "$STATE_FILE" > "$_tmp" 2>/dev/null
    echo "$_k=$_v" >> "$_tmp"
    mv -f "$_tmp" "$STATE_FILE"
  else
    echo "$_k=$_v" >> "$STATE_FILE"
  fi
  chmod 0600 "$STATE_FILE" 2>/dev/null
}

# ----------------------------------------------------------------------------
# listen_addresses del TOML
# ----------------------------------------------------------------------------
# Primera direccion (la principal). FIX: sed anclado al inicio para no caer
# en el greedy match cuando hay varias direcciones en la misma linea.
get_listen() {
  _l=$(grep -E '^[[:space:]]*listen_addresses[[:space:]]*=' "$TOML" 2>/dev/null | head -n1)
  _addr=$(printf '%s' "$_l" | sed -n "s/^[^'\"]*['\"]\([^'\"]*\)['\"].*/\1/p")
  [ -n "$_addr" ] && echo "$_addr" || echo "127.0.0.1:5354"
}

# Todas las direcciones, una por linea (para chequear cada listener).
get_listen_all() {
  _l=$(grep -E '^[[:space:]]*listen_addresses[[:space:]]*=' "$TOML" 2>/dev/null | head -n1)
  if [ -n "$_l" ]; then
    # Extraer todos los tokens entre comillas simples o dobles.
    printf '%s\n' "$_l" | grep -o "'[^']*'" 2>/dev/null | tr -d "'"
    printf '%s\n' "$_l" | grep -o '"[^"]*"' 2>/dev/null | tr -d '"'
  else
    echo "127.0.0.1:5354"
  fi
}

get_listen_port() { _a=$(get_listen); echo "${_a##*:}"; }
get_listen_host() { _a=$(get_listen); echo "${_a%:*}"; }

# ----------------------------------------------------------------------------
# Sockets: correlacion puerto -> inodes -> PID (para is-listening estricto)
# ----------------------------------------------------------------------------
# Imprime los inodes de sockets locales en el puerto dado (hex), en cualquiera
# de las 4 tablas. Campo 2 = local_address (IPHEX:PORTHEX), campo 10 = inode.
port_inodes() {
  _port="$1"
  case "$_port" in ''|*[!0-9]*) return 1 ;; esac
  _hex=$(printf '%04X' "$_port" 2>/dev/null) || return 1
  for _f in /proc/net/udp /proc/net/udp6 /proc/net/tcp /proc/net/tcp6; do
    [ -r "$_f" ] || continue
    awk -v p=":$_hex" '$2 ~ p"$" { print $10 }' "$_f" 2>/dev/null
  done | sort -u | grep -v '^0$'
}

# ¿El PID posee un fd apuntando a socket:[inode]? 0 = si.
pid_has_inode() {
  _pid="$1"; _ino="$2"
  [ -d "/proc/$_pid/fd" ] || return 1
  for _fd in /proc/"$_pid"/fd/*; do
    [ -e "$_fd" ] || continue
    _t=$(readlink "$_fd" 2>/dev/null)
    [ "$_t" = "socket:[$_ino]" ] && return 0
  done
  return 1
}

# ----------------------------------------------------------------------------
# JSON helpers
# ----------------------------------------------------------------------------
json_escape() {
  sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/\t/\\t/g' -e 's/\r//g' \
    | awk 'BEGIN{ORS="\\n"} {print}' | sed 's/\\n$//'
}
json_kv() { printf '"%s":"%s"' "$1" "$(printf '%s' "$2" | json_escape)"; }

# ----------------------------------------------------------------------------
# VALIDADORES (todo input del usuario pasa por aca)
# ----------------------------------------------------------------------------
valid_port() {
  case "$1" in ''|*[!0-9]*) return 1 ;; esac
  [ "$1" -ge 1 ] 2>/dev/null && [ "$1" -le 65535 ] 2>/dev/null
}

valid_ipv4() {
  echo "$1" | grep -Eq '^([0-9]{1,3}\.){3}[0-9]{1,3}$' || return 1
  _IFS_OLD=$IFS; IFS='.'
  set -- $1
  IFS=$_IFS_OLD
  for _o in "$@"; do [ "$_o" -le 255 ] 2>/dev/null || return 1; done
  return 0
}

valid_ipv6() {
  echo "$1" | grep -Eq '^[0-9a-fA-F:]+$' && echo "$1" | grep -q ':' && [ "${#1}" -le 45 ]
}

valid_ip() { valid_ipv4 "$1" || valid_ipv6 "$1"; }

valid_host() {
  [ "${#1}" -le 253 ] || return 1
  echo "$1" | grep -Eq '^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?)*$'
}

valid_doh_url() {
  case "$1" in https://*) : ;; *) return 1 ;; esac
  case "$1" in
    *' '*|*';'*|*'|'*|*'&'*|*'$'*|*'`'*|*'<'*|*'>'*|*'('*|*')'*|*'"'*|*"'"*|*'\'*) return 1 ;;
  esac
  [ "${#1}" -le 512 ]
}

valid_stamp() {
  case "$1" in sdns://*) : ;; *) return 1 ;; esac
  echo "$1" | grep -Eq '^sdns://[A-Za-z0-9_-]+=*$' && [ "${#1}" -le 1024 ]
}

valid_nextdns_id() { echo "$1" | grep -Eq '^[0-9a-fA-F]{4,12}$'; }

valid_server_name() { echo "$1" | grep -Eq '^[A-Za-z0-9._-]{1,64}$'; }

# ----------------------------------------------------------------------------
# Proceso
# ----------------------------------------------------------------------------
read_pid() {
  [ -f "$PIDFILE" ] || return 1
  _p=$(cat "$PIDFILE" 2>/dev/null)
  case "$_p" in ''|*[!0-9]*) return 1 ;; esac
  if kill -0 "$_p" 2>/dev/null; then
    if grep -aq dnscrypt "/proc/$_p/cmdline" 2>/dev/null; then
      echo "$_p"; return 0
    fi
  fi
  return 1
}

fix_selinux_bin() {
  _b="$1"
  [ -f "$_b" ] || return 0
  have chcon && chcon u:object_r:system_file:s0 "$_b" 2>/dev/null
  return 0
}
