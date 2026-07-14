#!/system/bin/sh
##############################################################################
# DNSCrypt Manager - boot-completed.sh
#
# Soportado por KernelSU / KernelSU Next / APatch (y Magisk reciente).
# Se ejecuta cuando el sistema ya termino de arrancar y la red suele estar
# arriba. Sirve de RED DE SEGURIDAD por si service.sh corrio demasiado
# temprano: reengancha la redireccion si quedo pendiente.
#
# Es idempotente: si el proxy ya corre y la redireccion ya esta, no hace nada.
##############################################################################

MODDIR=${0%/*}
DATA_DIR=/data/adb/dnscrypt-manager
# Modo test (exclusivo de tests/*.sh, ver scripts/common.sh).
[ "${DNSCRYPT_TEST_MODE:-0}" = "1" ] && [ -n "${DNSCRYPT_TEST_DATA_DIR:-}" ] && DATA_DIR="$DNSCRYPT_TEST_DATA_DIR"
CLI="/system/bin/dnscrypt-manager"
[ -x "$CLI" ] || CLI="$MODDIR/system/bin/dnscrypt-manager"

# run_cli: ver definicion y justificacion completa en uninstall.sh.
run_cli() {
  if [ "${DNSCRYPT_TEST_MODE:-0}" = "1" ]; then
    "${DNSCRYPT_TEST_SHELL:-sh}" "$CLI" "$@"
  else
    "$CLI" "$@"
  fi
}

[ -f "$DATA_DIR/disable" ] && exit 0

(
  LOG="$DATA_DIR/logs/boot.log"
  log() { echo "$(date '+%Y-%m-%d %H:%M:%S') boot-completed: $*" >> "$LOG" 2>/dev/null; }

  # Dar un margen a la red movil/wifi.
  sleep 5

  # Si el proxy no esta corriendo, intentar levantarlo una vez.
  if ! run_cli is-running >/dev/null 2>&1; then
    log "proxy caido en boot-completed, reintentando start"
    run_cli start >> "$LOG" 2>&1
    sleep 3
  fi

  # Reenganchar redireccion si corresponde y todavia no esta aplicada.
  if run_cli is-listening >/dev/null 2>&1 && \
     [ "$(run_cli get-flag boot_redirect 2>/dev/null)" = "1" ] && \
     [ ! -f "$DATA_DIR/no-redirect" ]; then
    if ! run_cli redirect status --quiet >/dev/null 2>&1; then
      log "reenganchando redireccion"
      run_cli redirect apply >> "$LOG" 2>&1
      if ! run_cli test-dns --quiet >> "$LOG" 2>&1; then
        log "prueba DNS fallo, retirando redireccion"
        run_cli redirect remove >> "$LOG" 2>&1
        run_cli restore-network >> "$LOG" 2>&1
      fi
    fi
  fi
) &

exit 0
