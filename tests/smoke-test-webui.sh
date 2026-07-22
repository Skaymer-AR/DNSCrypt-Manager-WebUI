#!/bin/bash
##############################################################################
# tests/smoke-test-webui.sh
# Creado por Skaymer AR
#
# Smoke test funcional de la WebUI contra la CLI real, COMPLETAMENTE
# AISLADO. Misma estrategia de gestion de procesos endurecida que
# tests/smoke-test-cli.sh: la invocacion de node corre en su propio grupo
# de procesos (setsid), con timeout+kill-after y limpieza defensiva del
# grupo COMPLETO al terminar (nunca solo el proceso hijo directo), mas un
# watchdog global de emergencia que jamas vuelve a invocar la CLI.
#
# Uso:  bash tests/smoke-test-webui.sh
# Exit: 0 si todo paso, 1 si algo fallo, 99 si el arnes esta roto.
##############################################################################
set -u
cd "$(dirname "$0")/.." || exit 1
SRC_ROOT="$(pwd)"

NODE_BIN="$(command -v node)"
PYTHON_BIN="$(command -v python3)"
SH_BIN="$(command -v sh)"
[ -n "$NODE_BIN" ]   || { echo "FATAL (arnes roto): no se encontro 'node'." >&2; exit 99; }
[ -n "$PYTHON_BIN" ] || { echo "FATAL (arnes roto): no se encontro 'python3'." >&2; exit 99; }
[ -n "$SH_BIN" ]     || { echo "FATAL (arnes roto): no se encontro 'sh'." >&2; exit 99; }

TEST_ROOT="$(mktemp -d /tmp/dnscrypt-manager-webui-test.XXXXXX)" || { echo "FATAL: no se pudo crear mktemp -d" >&2; exit 99; }
export DNSCRYPT_TEST_MODE=1
export DNSCRYPT_TEST_ROOT="$TEST_ROOT"
export DNSCRYPT_TEST_DATA_DIR="$TEST_ROOT/data"
export DNSCRYPT_TEST_MODDIR="$TEST_ROOT/mod"
export DNSCRYPT_TEST_SHELL="$SH_BIN"
export DCM_WEBROOT="$SRC_ROOT/webroot"
SCRATCH="$TEST_ROOT/scratch"
mkdir -p "$SCRATCH"

START_TS=$(date +%s)
OUR_PID=""
HARNESS_GRP=""
MAIN_PID=$$

pid_is_alive_as() {
  _pid="$1"; _needle="$2"
  [ -n "$_pid" ] || return 1
  [ -r "/proc/$_pid/cmdline" ] || return 1
  tr '\0' ' ' < "/proc/$_pid/cmdline" 2>/dev/null | grep -qF -- "$_needle"
}

GLOBAL_TIMEOUT_SECS="${DNSCRYPT_TEST_GLOBAL_TIMEOUT:-120}"
( _wdn=0
  while [ "$_wdn" -lt "$GLOBAL_TIMEOUT_SECS" ] 2>/dev/null; do
    sleep 1
    _wdn=$((_wdn + 1))
  done
  echo "FATAL: watchdog global (${GLOBAL_TIMEOUT_SECS}s) excedido; forzando aborto." >&2
  kill -TERM "$MAIN_PID" 2>/dev/null
  sleep 5
  kill -KILL "$MAIN_PID" 2>/dev/null
) &
WATCHDOG_PID=$!
disown "$WATCHDOG_PID" 2>/dev/null

cleanup() {
  kill "$WATCHDOG_PID" 2>/dev/null
  wait "$WATCHDOG_PID" 2>/dev/null
  if [ -n "$HARNESS_GRP" ]; then
    kill -TERM -- "-$HARNESS_GRP" 2>/dev/null
    wait "$HARNESS_GRP" 2>/dev/null
    sleep 0.15
    kill -KILL -- "-$HARNESS_GRP" 2>/dev/null
    wait "$HARNESS_GRP" 2>/dev/null
  fi
  # SIEMPRE releer el pidfile actual: el daemon vive en su PROPIO grupo
  # de procesos (job-control del shell al backgroundear con '&' dentro de
  # cmd_start), nunca alcanzado por el kill al grupo de arriba.
  _cur_pid=$(cat "$DNSCRYPT_TEST_DATA_DIR/run/dnscrypt-proxy.pid" 2>/dev/null)
  for p in "$_cur_pid" $OUR_PID; do
    [ -n "$p" ] || continue
    kill -9 "$p" 2>/dev/null
    wait "$p" 2>/dev/null
  done
  rm -rf "$TEST_ROOT"
}
on_signal() { cleanup; exit 99; }
trap on_signal INT TERM
trap cleanup EXIT

echo "=== Preparando entorno aislado en $TEST_ROOT ==="
mkdir -p "$DNSCRYPT_TEST_MODDIR" "$DNSCRYPT_TEST_DATA_DIR/bin" "$DNSCRYPT_TEST_DATA_DIR/config/defaults"
cp -a "$SRC_ROOT/." "$DNSCRYPT_TEST_MODDIR/"
rm -rf "$DNSCRYPT_TEST_MODDIR/tests" "$DNSCRYPT_TEST_MODDIR/tools"
cp "$SRC_ROOT/tests/fixtures/fake-dnscrypt-proxy" "$DNSCRYPT_TEST_DATA_DIR/bin/dnscrypt-proxy"
chmod 0755 "$DNSCRYPT_TEST_DATA_DIR/bin/dnscrypt-proxy"

TEST_PORT=$("$PYTHON_BIN" -c "
import socket
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.bind(('127.0.0.1', 0))
print(s.getsockname()[1])
s.close()
" 2>/dev/null)
case "$TEST_PORT" in ''|*[!0-9]*) echo "FATAL: no se pudo asignar un puerto de prueba" >&2; exit 99 ;; esac
echo "  puerto de prueba asignado dinamicamente: $TEST_PORT"

sed -e "s/127\.0\.0\.1:5354/127.0.0.1:$TEST_PORT/" -e "s/\[::1\]:5354/[::1]:$TEST_PORT/" \
  "$SRC_ROOT/config/dnscrypt-proxy.toml" > "$DNSCRYPT_TEST_DATA_DIR/config/dnscrypt-proxy.toml"
cp "$DNSCRYPT_TEST_DATA_DIR/config/dnscrypt-proxy.toml" "$DNSCRYPT_TEST_DATA_DIR/config/defaults/dnscrypt-proxy.toml"

echo
echo "=== Corriendo el harness DOM (grupo de procesos propio + timeout defensivo) ==="
setsid timeout --kill-after=5 90 "$NODE_BIN" "$SRC_ROOT/tests/fixtures/webui-harness.cjs" >"$SCRATCH/harness-out.txt" 2>&1 &
HARNESS_GRP=$!
wait "$HARNESS_GRP" 2>/dev/null
RC=$?
kill -TERM -- "-$HARNESS_GRP" 2>/dev/null; wait "$HARNESS_GRP" 2>/dev/null
sleep 0.15
kill -KILL -- "-$HARNESS_GRP" 2>/dev/null; wait "$HARNESS_GRP" 2>/dev/null
HARNESS_GRP=""
cat "$SCRATCH/harness-out.txt"

OUR_PID="$(cat "$DNSCRYPT_TEST_DATA_DIR/run/dnscrypt-proxy.pid" 2>/dev/null)"

END_TS=$(date +%s)
DUR=$((END_TS - START_TS))
echo
echo "=== duracion: ${DUR}s, TEST_ROOT=$TEST_ROOT, puerto=$TEST_PORT, exit=$RC ==="
kill "$WATCHDOG_PID" 2>/dev/null
exit "$RC"
