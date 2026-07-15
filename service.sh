#!/system/bin/sh
##############################################################################
# DNSCrypt Manager - service.sh  (fase late_start service)
#
# Aca arranca el daemon y (opcionalmente) se aplica la redireccion, PERO
# todo el trabajo pesado corre en un subshell en segundo plano para no
# demorar el arranque del sistema. Nunca bloquea el boot.
#
# Secuencia segura (watchdog):
#   1. Si existe flag 'disable' -> salir, no hacer nada.
#   2. Esperar a que la red este disponible (con timeout).
#   3. Arrancar dnscrypt-proxy (dnscrypt-manager start).
#   4. Esperar a que el puerto local escuche (con timeout).
#   5. Si 'boot_redirect' esta activo -> aplicar redireccion.
#   6. Probar resolucion DNS real a traves del proxy.
#   7. Si la prueba FALLA -> retirar redireccion y restaurar. Nunca deja
#      el telefono con DNS roto por culpa nuestra.
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

# --- Cortocircuito de emergencia -------------------------------------------
if [ -f "$DATA_DIR/disable" ]; then
  echo "$(date '+%Y-%m-%d %H:%M:%S') boot: modulo DESHABILITADO por flag, no arranca" \
    >> "$DATA_DIR/logs/boot.log" 2>/dev/null
  exit 0
fi

# --- Trabajo real en segundo plano -----------------------------------------
# El '&' garantiza que service.sh retorna de inmediato y no demora el boot.
(
  LOG="$DATA_DIR/logs/boot.log"
  log() { echo "$(date '+%Y-%m-%d %H:%M:%S') boot: $*" >> "$LOG" 2>/dev/null; }

  # 1. Esperar boot_completed (mejor esfuerzo, hasta ~60s)
  i=0
  while [ "$i" -lt 60 ]; do
    [ "$(getprop sys.boot_completed 2>/dev/null)" = "1" ] && break
    sleep 1; i=$((i+1))
  done
  log "boot_completed alcanzado tras ${i}s"

  # 2. Esperar que la red este disponible (mejor esfuerzo, hasta ~30s)
  i=0
  while [ "$i" -lt 30 ]; do
    if ip route 2>/dev/null | grep -q default || \
       [ -n "$(getprop dhcp.wlan0.ipaddress 2>/dev/null)" ]; then
      break
    fi
    sleep 1; i=$((i+1))
  done
  log "red disponible tras ${i}s"

  # 2b. Migracion versionada v0.1.0 -> v0.2.0 (idempotente; solo actua una vez).
  if [ ! -f "$DATA_DIR/schema_version" ] || [ "$(cat "$DATA_DIR/schema_version" 2>/dev/null)" != "2" ]; then
    log "ejecutando migracion de esquema"
    run_cli migrate >> "$LOG" 2>&1 || log "migracion reporto error (se continua con cuidado)"
  fi

  # 2c. Barrer excepciones temporales caducas (o de boots anteriores) antes de
  #     regenerar/arrancar. No depende de cron.
  run_cli temporary-allow sweep >> "$LOG" 2>&1

  # 3. Arrancar el daemon (la CLI maneja binario faltante / config invalida)
  log "arrancando dnscrypt-proxy"
  run_cli start >> "$LOG" 2>&1

  # 4. Esperar a que escuche el puerto local (hasta ~15s)
  i=0
  while [ "$i" -lt 15 ]; do
    run_cli is-listening >/dev/null 2>&1 && break
    sleep 1; i=$((i+1))
  done

  if ! run_cli is-listening >/dev/null 2>&1; then
    log "dnscrypt-proxy NO escucha tras 15s. Se aborta redireccion por seguridad."
    # Si el usuario activo fail-closed, aplicarlo ahora (bloquea DNS externo).
    # Es un no-op si el flag esta en 0 (valor por defecto).
    run_cli failclosed engage-if-set >> "$LOG" 2>&1
    exit 0
  fi
  log "dnscrypt-proxy escuchando"

  # 5. Aplicar redireccion SOLO si el usuario la dejo activada para el boot
  #    Y la migracion no quedo en estado fallido (recuperacion segura).
  if [ -f "$DATA_DIR/migration-failed" ]; then
    log "migracion fallida pendiente: se OMITE la redireccion este boot (recuperacion segura)"
  elif [ "$(run_cli get-flag boot_redirect 2>/dev/null)" = "1" ] && \
     [ ! -f "$DATA_DIR/no-redirect" ]; then
    log "aplicando redireccion DNS"
    run_cli redirect apply >> "$LOG" 2>&1

    # 6. Probar DNS real a traves del proxy
    if run_cli test-dns --quiet >> "$LOG" 2>&1; then
      log "prueba DNS OK, redireccion activa"
    else
      # 7. Rollback: sacar redireccion y restaurar DNS del sistema
      log "prueba DNS FALLO tras redirigir. Retirando reglas y restaurando."
      run_cli redirect remove >> "$LOG" 2>&1
      run_cli restore-network >> "$LOG" 2>&1
      log "red restaurada. Redireccion desactivada esta sesion."
    fi
  else
    log "boot_redirect desactivado: solo corre el proxy, sin redireccion global"
  fi

  log "secuencia de arranque finalizada"
) &

exit 0
