#!/system/bin/sh
##############################################################################
# DNSCrypt Manager - uninstall.sh
# Se ejecuta cuando desinstalas el modulo desde el gestor.
#
# Objetivo: dejar el telefono EXACTAMENTE como estaba. Limpia:
#   - Reglas de redireccion (cadenas propias DNSCRYPT_*).
#   - El proceso dnscrypt-proxy.
#   - Runtime (pid, flags).
# Preserva la carpeta backups/ (tus exportaciones), borra el resto de datos.
##############################################################################

MODDIR=${0%/*}
DATA_DIR=/data/adb/dnscrypt-manager
# Modo test (exclusivo de tests/*.sh, ver scripts/common.sh): permite
# invocar este script aislado, sin tocar /data/adb real.
[ "${DNSCRYPT_TEST_MODE:-0}" = "1" ] && [ -n "${DNSCRYPT_TEST_DATA_DIR:-}" ] && DATA_DIR="$DNSCRYPT_TEST_DATA_DIR"
CLI="/system/bin/dnscrypt-manager"
[ -x "$CLI" ] || CLI="$MODDIR/system/bin/dnscrypt-manager"

# run_cli: UNICA abstraccion de invocacion de la CLI en todo el modulo.
#   - Produccion (DNSCRYPT_TEST_MODE distinto de 1): ejecuta "$CLI" DIRECTO,
#     respetando su shebang real '#!/system/bin/sh' (correcto en Android).
#   - Modo test (exclusivo de tests/*.sh): permite forzar un interprete
#     explicito via DNSCRYPT_TEST_SHELL, porque el sandbox de desarrollo no
#     tiene /system/bin/sh y esta prohibido crearlo alli. Nunca se usa
#     'eval' ni se concatenan argumentos: "$@" preserva cada argumento tal
#     cual. La WebUI no puede setear estas variables: solo dispara cadenas
#     de comando FIJAS via ksu.exec, sin control sobre el entorno.
run_cli() {
  if [ "${DNSCRYPT_TEST_MODE:-0}" = "1" ]; then
    "${DNSCRYPT_TEST_SHELL:-sh}" "$CLI" "$@"
  else
    "$CLI" "$@"
  fi
}

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') uninstall: $*" >> "$DATA_DIR/logs/boot.log" 2>/dev/null; }
log "iniciando desinstalacion"

# 1. Retirar reglas de redireccion (idempotente; no falla si no habia)
if [ -x "$CLI" ]; then
  run_cli redirect remove 2>/dev/null
  run_cli restore-network 2>/dev/null
  run_cli stop 2>/dev/null
else
  # Fallback directo si la CLI no esta disponible por algun motivo.
  for T in iptables ip6tables; do
    command -v "$T" >/dev/null 2>&1 || continue
    "$T" -t nat -D OUTPUT -j DNSCRYPT_OUTPUT 2>/dev/null
    "$T" -t nat -D PREROUTING -j DNSCRYPT_REDIRECT 2>/dev/null
    "$T" -t nat -F DNSCRYPT_OUTPUT 2>/dev/null
    "$T" -t nat -F DNSCRYPT_REDIRECT 2>/dev/null
    "$T" -t nat -X DNSCRYPT_OUTPUT 2>/dev/null
    "$T" -t nat -X DNSCRYPT_REDIRECT 2>/dev/null
  done
  # Matar el proceso SOLO si el pidfile apunta a un PID cuyo ejecutable
  # real (via /proc/PID/exe) coincide EXACTAMENTE con nuestro binario
  # persistente. Comparacion estricta de ruta resuelta, nunca pgrep/pkill
  # por patron (una busqueda por patron puede coincidir con procesos no
  # relacionados, o con el propio shell que la ejecuta).
  _pf="$DATA_DIR/run/dnscrypt-proxy.pid"
  if [ -f "$_pf" ]; then
    _pid=$(cat "$_pf" 2>/dev/null)
    case "$_pid" in
      ''|*[!0-9]*) : ;;
      *)
        _exe_link="/proc/$_pid/exe"
        if [ -e "$_exe_link" ]; then
          _target=$(readlink "$_exe_link" 2>/dev/null)
          _expected="$DATA_DIR/bin/dnscrypt-proxy"
          if [ "$_target" = "$_expected" ]; then
            kill "$_pid" 2>/dev/null
          fi
        fi
        ;;
    esac
  fi
fi

# 2. Limpiar runtime y flags
rm -f "$DATA_DIR/run/"* 2>/dev/null
rm -f "$DATA_DIR/disable" "$DATA_DIR/no-redirect" 2>/dev/null

# 3. Borrar datos, PRESERVANDO backups del usuario
if [ -d "$DATA_DIR" ]; then
  find "$DATA_DIR" -mindepth 1 -maxdepth 1 ! -name 'backups' -exec rm -rf {} + 2>/dev/null
  # Si backups quedo vacio, remover todo el arbol.
  if [ -z "$(ls -A "$DATA_DIR/backups" 2>/dev/null)" ]; then
    rm -rf "$DATA_DIR" 2>/dev/null
  fi
fi

log "desinstalacion completada"
exit 0
