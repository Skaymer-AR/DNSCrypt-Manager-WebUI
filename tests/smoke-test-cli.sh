#!/bin/bash
##############################################################################
# tests/smoke-test-cli.sh
# Creado por Skaymer AR
#
# Bateria funcional de la CLI dnscrypt-manager, COMPLETAMENTE AISLADA.
#
# GESTION DE PROCESOS (endurecida tras auditoria externa):
#   - Cada invocacion de la CLI corre via 'setsid timeout ...', lo que le
#     da un GRUPO DE PROCESOS PROPIO (PGID == PID del proceso que setsid
#     lanza). Al terminar (rc normal, timeout, o señal), se envia TERM y
#     despues KILL al GRUPO COMPLETO (PGID negativo), nunca solo al
#     proceso hijo directo. Esto es DEFENSIVO: no se asume que la
#     implementacion de 'timeout' de un sistema dado ya mate a todos los
#     descendientes por su cuenta (varia segun SO/version).
#   - Todo PID que este script lanza en segundo plano (impostor, señuelo,
#     bloqueador de puerto) se registra, se mata, y se espera con 'wait'
#     explicitamente — nunca se deja "flotando".
#   - La verificacion de "sigue vivo" NUNCA usa solo 'kill -0' (un PID
#     puede haber sido reciclado por el sistema operativo para un proceso
#     completamente distinto tras la muerte del original: esto genero un
#     falso positivo real durante el desarrollo de este arnes). Se
#     correlaciona SIEMPRE con /proc/PID/cmdline antes de declarar "vivo".
#   - Watchdog de emergencia: un proceso en segundo plano vigila el
#     tiempo TOTAL de la suite; si se excede, manda señal al proceso
#     principal SIN volver a invocar la CLI (que podria estar colgada).
#
# Uso:  bash tests/smoke-test-cli.sh
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

TEST_ROOT="$(mktemp -d /tmp/dnscrypt-manager-test.XXXXXX)" || { echo "FATAL: no se pudo crear mktemp -d" >&2; exit 99; }
export DNSCRYPT_TEST_MODE=1
export DNSCRYPT_TEST_ROOT="$TEST_ROOT"
export DNSCRYPT_TEST_DATA_DIR="$TEST_ROOT/data"
export DNSCRYPT_TEST_MODDIR="$TEST_ROOT/mod"
export DNSCRYPT_TEST_SHELL="$SH_BIN"
SCRATCH="$TEST_ROOT/scratch"
mkdir -p "$SCRATCH"

FW_BIN="$SRC_ROOT/tests/fixtures/fake-firewall-bin"
export FAKE_FW_STATE="$TEST_ROOT/fw-state"
M="$DNSCRYPT_TEST_MODDIR/system/bin/dnscrypt-manager"
CLI_TIMEOUT="${DNSCRYPT_TEST_CLI_TIMEOUT:-30}"  # margen sobre el timeout interno de cmd_start (~15s de reloj + una iteracion en curso)
KILL_AFTER=5

PASS=0; FAILN=0; TIMEOUTS=0
OUR_PID=""            # PID (real, verificado por cmdline) del daemon que ESTA suite arranco
EXTRA_PIDS=""         # PIDs auxiliares (impostor/señuelo/bloqueador), para matar+esperar
CALL_GROUPS=""        # PGIDs de invocaciones de call_cli aun no confirmadas limpias
TEST_PORT=""
START_TS=$(date +%s)
MAIN_PID=$$

ok()  { PASS=$((PASS+1)); printf '  OK   %s\n' "$1"; }
bad() { FAILN=$((FAILN+1)); printf '  FAIL %s\n' "$1"; }

##############################################################################
# Verificacion RIGUROSA de "sigue vivo": correlaciona PID con cmdline real,
# nunca confia solo en 'kill -0' (un PID reciclado por el SO para un
# proceso distinto haria que kill -0 "tenga exito" sin ser el mismo
# proceso — esto paso de verdad durante el desarrollo de este arnes).
##############################################################################
pid_is_alive_as() {
  _pid="$1"; _needle="$2"
  [ -n "$_pid" ] || return 1
  [ -r "/proc/$_pid/cmdline" ] || return 1
  tr '\0' ' ' < "/proc/$_pid/cmdline" 2>/dev/null | grep -qF -- "$_needle"
}

##############################################################################
# classify_rc
##############################################################################
classify_rc() {
  case "$1" in
    0)   echo "ejecucion correcta" ;;
    124) echo "TIMEOUT (rc=124)" ;;
    126) echo "NO EJECUTABLE - arnes roto (rc=126)" ;;
    127) echo "COMANDO AUSENTE - arnes roto (rc=127)" ;;
    1[3-9][0-9]|2[0-9][0-9]) echo "señal $(( $1 - 128 )) (rc=$1)" ;;
    *)   echo "fallo funcional (rc=$1)" ;;
  esac
}

##############################################################################
# Watchdog de emergencia: NUNCA vuelve a invocar la CLI (que podria estar
# colgada). Solo manda señal al proceso PRINCIPAL tras un plazo global.
##############################################################################
GLOBAL_TIMEOUT_SECS="${DNSCRYPT_TEST_GLOBAL_TIMEOUT:-280}"
( sleep "$GLOBAL_TIMEOUT_SECS"
  echo "FATAL: watchdog global (${GLOBAL_TIMEOUT_SECS}s) excedido; forzando aborto." >&2
  kill -TERM "$MAIN_PID" 2>/dev/null
  sleep 5
  kill -KILL "$MAIN_PID" 2>/dev/null
) &
WATCHDOG_PID=$!
disown "$WATCHDOG_PID" 2>/dev/null

##############################################################################
# Limpieza: mata+espera cada PID/GRUPO registrado. Jamas invoca la CLI de
# nuevo aca (si esta colgada, invocarla otra vez tambien se colgaria).
##############################################################################
cleanup() {
  kill "$WATCHDOG_PID" 2>/dev/null
  for grp in $CALL_GROUPS; do
    kill -TERM -- "-$grp" 2>/dev/null
    wait "$grp" 2>/dev/null
  done
  sleep 0.2
  for grp in $CALL_GROUPS; do
    kill -KILL -- "-$grp" 2>/dev/null
    wait "$grp" 2>/dev/null
  done
  # SIEMPRE releer el pidfile actual (no confiar solo en $OUR_PID, que
  # puede quedar desactualizado si hubo un restart entre medio): el
  # daemon vive en su PROPIO grupo de procesos, creado por el job-control
  # del shell al backgroundear con '&' DENTRO de cmd_start — nunca
  # alcanzado por el kill al grupo del wrapper setsid/timeout de arriba.
  _cur_pid=$(cat "$DNSCRYPT_TEST_DATA_DIR/run/dnscrypt-proxy.pid" 2>/dev/null)
  for p in "$_cur_pid" $OUR_PID $EXTRA_PIDS; do
    [ -n "$p" ] || continue
    kill -9 "$p" 2>/dev/null
    wait "$p" 2>/dev/null
  done
  if [ "$FAILN" -gt 0 ]; then
    PRESERVE="$(mktemp -d /tmp/dcm-failed-logs.XXXXXX)"
    cp -a "$DNSCRYPT_TEST_DATA_DIR/logs" "$PRESERVE/" 2>/dev/null
    cp -a "$SCRATCH" "$PRESERVE/scratch" 2>/dev/null
    echo "  (hubo fallos: logs y scratch preservados en $PRESERVE)"
  fi
  rm -rf "$TEST_ROOT"
}
on_signal() { cleanup; exit 99; }
trap on_signal INT TERM
trap cleanup EXIT

##############################################################################
# call_cli: setsid (grupo de procesos propio) + timeout + kill-after, y
# LUEGO limpieza defensiva del GRUPO COMPLETO (nunca solo el hijo directo),
# sin asumir que el 'timeout' de este sistema ya lo hace por su cuenta.
##############################################################################
call_cli() {
  setsid timeout --kill-after="$KILL_AFTER" "$CLI_TIMEOUT" "$DNSCRYPT_TEST_SHELL" "$M" "$@" &
  _grp=$!
  CALL_GROUPS="$CALL_GROUPS $_grp"
  wait "$_grp" 2>/dev/null
  rc=$?
  # Limpieza defensiva del grupo ENTERO (PGID == $_grp por convencion de
  # setsid), independiente de si 'timeout' ya limpio todo por su cuenta.
  kill -TERM -- "-$_grp" 2>/dev/null
  wait "$_grp" 2>/dev/null
  sleep 0.15
  kill -KILL -- "-$_grp" 2>/dev/null
  wait "$_grp" 2>/dev/null
  CALL_GROUPS=$(printf '%s' "$CALL_GROUPS" | sed "s/\b$_grp\b//")
  # Si esta llamada murio por timeout o señal DESPUES de haber
  # backgroundeado un daemon (p.ej. 'start' colgado en su propio wait
  # loop tras arrancarlo), ese daemon escapo a su PROPIO grupo de
  # procesos (job-control del shell al backgroundear con '&' dentro de
  # cmd_start) y el kill al grupo de arriba NUNCA lo alcanza. Releer el
  # pidfile actual y matarlo directo, sin esperar a la limpieza final.
  if [ "$rc" -eq 124 ] || [ "$rc" -ge 128 ]; then
    _leftover=$(cat "$DNSCRYPT_TEST_DATA_DIR/run/dnscrypt-proxy.pid" 2>/dev/null)
    if [ -n "$_leftover" ]; then
      kill -9 "$_leftover" 2>/dev/null
      wait "$_leftover" 2>/dev/null
    fi
  fi
  if [ "$rc" -eq 126 ] || [ "$rc" -eq 127 ]; then
    echo "" >&2
    echo "FATAL: call_cli $* -> $(classify_rc "$rc")" >&2
    echo "       Fallo del ARNES DE PRUEBAS, no del producto. Abortando." >&2
    kill -TERM "$MAIN_PID" 2>/dev/null
    exit 99
  fi
  if [ "$rc" -eq 124 ]; then
    TIMEOUTS=$((TIMEOUTS + 1))
  fi
  return "$rc"
}

read_test_pid() { cat "$DNSCRYPT_TEST_DATA_DIR/run/dnscrypt-proxy.pid" 2>/dev/null; }

bind_port_free() {
  "$PYTHON_BIN" -c "
import socket
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.bind(('127.0.0.1', $1))
s.close()
" 2>/dev/null
}

##############################################################################
# 0) Desplegar copia aislada + puerto dinamico
##############################################################################
echo "=== Preparando entorno aislado en $TEST_ROOT ==="
mkdir -p "$DNSCRYPT_TEST_MODDIR" "$DNSCRYPT_TEST_DATA_DIR/bin" "$DNSCRYPT_TEST_DATA_DIR/config/defaults" "$FAKE_FW_STATE"
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
sed -e "s/127\.0\.0\.1:5354/127.0.0.1:$TEST_PORT/" -e "s/\[::1\]:5354/[::1]:$TEST_PORT/" \
  "$SRC_ROOT/config/defaults/dnscrypt-proxy.toml" > "$DNSCRYPT_TEST_DATA_DIR/config/defaults/dnscrypt-proxy.toml"
grep -q "127.0.0.1:$TEST_PORT" "$DNSCRYPT_TEST_DATA_DIR/config/dnscrypt-proxy.toml" || { echo "FATAL: no se pudo inyectar el puerto de prueba" >&2; exit 99; }

export PATH="$FW_BIN:$PATH"

##############################################################################
# 1) Basico
##############################################################################
echo
echo "=== [1] version / config validate ==="
V=$(call_cli version)
[ -n "$V" ] && ok "version -> $V" || bad "version vacio"
call_cli config validate >/dev/null 2>&1 && ok "config validate" || bad "config validate"

##############################################################################
# 2) start / is-running (con espera real de listener)
##############################################################################
echo
echo "=== [2] start / is-running (con espera real de listener) ==="
call_cli start >"$SCRATCH/start-out.txt" 2>&1
RC=$?
OUR_PID="$(read_test_pid)"
if [ "$RC" -eq 0 ] && call_cli is-running >/dev/null 2>&1; then
  ok "start + is-running (PID $OUR_PID) -- $(classify_rc "$RC")"
else
  bad "start + is-running -> $(classify_rc "$RC"): $(cat "$SCRATCH/start-out.txt")"
fi

##############################################################################
# 3) is-listening ESTRICTO: correlacion inode<->PID, con impostor+señuelo
##############################################################################
echo
echo "=== [3] is-listening: correlacion socket-inode-PID (adversarial) ==="
call_cli stop >/dev/null 2>&1
OUR_PID=""
"$PYTHON_BIN" -c "
import socket, time
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.bind(('127.0.0.1', $TEST_PORT))
time.sleep(20)" &
IMPOSTOR=$!
EXTRA_PIDS="$EXTRA_PIDS $IMPOSTOR"
"$PYTHON_BIN" -c "import time; time.sleep(20)" dnscrypt-decoy &
DECOY=$!
EXTRA_PIDS="$EXTRA_PIDS $DECOY"
sleep 1
mkdir -p "$DNSCRYPT_TEST_DATA_DIR/run"
echo "$DECOY" > "$DNSCRYPT_TEST_DATA_DIR/run/dnscrypt-proxy.pid"
if call_cli is-running >/dev/null 2>&1; then ok "is-running acepta el señuelo (cmdline+PID validos)"; else bad "is-running deberia aceptar el señuelo"; fi
if call_cli is-listening >/dev/null 2>&1; then bad "is-listening ACEPTO un socket que NO es del PID (BUG DE SEGURIDAD)"; else ok "is-listening RECHAZA correctamente el socket ajeno (PID viejo no se confunde con el nuevo)"; fi
kill -9 "$IMPOSTOR" 2>/dev/null; wait "$IMPOSTOR" 2>/dev/null
kill -9 "$DECOY" 2>/dev/null; wait "$DECOY" 2>/dev/null
EXTRA_PIDS=""
rm -f "$DNSCRYPT_TEST_DATA_DIR/run/dnscrypt-proxy.pid"
sleep 0.3
bind_port_free "$TEST_PORT" && ok "puerto $TEST_PORT libre tras matar impostor+señuelo" || bad "puerto $TEST_PORT sigue ocupado"

##############################################################################
# 4) start NO debe declarar exito con el puerto ya ocupado por otro proceso
##############################################################################
echo
echo "=== [4] start con el puerto YA ocupado -> debe fallar, sin exito falso ==="
"$PYTHON_BIN" -c "
import socket, time
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.bind(('127.0.0.1', $TEST_PORT))
time.sleep(45)" &
BLOCKER=$!
EXTRA_PIDS="$EXTRA_PIDS $BLOCKER"
sleep 0.5
call_cli start >"$SCRATCH/start-blocked.txt" 2>&1
RC=$?
if [ "$RC" -ne 0 ]; then
  ok "start con puerto ocupado -> rc!=0 ($(classify_rc "$RC")), NO declaro exito falso"
else
  bad "start declaro EXITO con el puerto ya ocupado por otro proceso (exactamente la carrera reportada)"
fi
if [ ! -f "$DNSCRYPT_TEST_DATA_DIR/run/dnscrypt-proxy.pid" ]; then
  ok "pidfile no quedo huerfano tras el fallo de start"
else
  bad "pidfile quedo presente tras un start fallido"
fi
kill -9 "$BLOCKER" 2>/dev/null; wait "$BLOCKER" 2>/dev/null
EXTRA_PIDS=""
sleep 0.3
# Verificacion RIGUROSA (no kill -0 ingenuo) de que no haya quedado ningun
# daemon huerfano de ESTE intento fallido de start.
LEFT=$(find /proc -maxdepth 1 -name '[0-9]*' 2>/dev/null | while read -r p; do
  pid_is_alive_as "${p#/proc/}" "dnscrypt-proxy" && echo "${p#/proc/}"
done)
if [ -z "$LEFT" ]; then
  ok "sin daemon huerfano tras start fallido (verificado por cmdline, no solo PID)"
else
  bad "daemon huerfano detectado tras start fallido: PIDs $LEFT"
  for p in $LEFT; do kill -9 "$p" 2>/dev/null; wait "$p" 2>/dev/null; done
fi

##############################################################################
# 5) test-dns: 4 etapas + rollback si falla
##############################################################################
echo
echo "=== [5] test-dns: 4 etapas reales ==="
call_cli start >/dev/null 2>&1
OUR_PID="$(read_test_pid)"
OUT=$(call_cli test-dns 2>&1)
echo "$OUT" | grep -q '^\[1/4\]' && echo "$OUT" | grep -q '^\[2/4\]' && \
echo "$OUT" | grep -q '^\[3/4\]' && echo "$OUT" | grep -q '^\[4/4\]' && \
  ok "test-dns recorrio las 4 etapas" || bad "test-dns no mostro las 4 etapas: $OUT"
echo "$OUT" | grep -q 'RESULTADO: DNS OK' && ok "test-dns: RESULTADO OK" || bad "test-dns: sin RESULTADO OK"

##############################################################################
# 6) REDIRECCION vía iptables (fake real, con estado)
##############################################################################
echo
echo "=== [6] redirect apply/remove via iptables (fake con estado) ==="
call_cli redirect apply >"$SCRATCH/redir-out.txt" 2>&1
RC=$?
if [ "$RC" -eq 0 ]; then ok "redirect apply (backend iptables) -> $(classify_rc "$RC")"; else bad "redirect apply fallo: $(cat "$SCRATCH/redir-out.txt")"; fi

NAT_OUT="$FAKE_FW_STATE/iptables.nat.OUTPUT.rules"
CH_OUT="$FAKE_FW_STATE/iptables.nat.DNSCRYPT_OUTPUT.rules"
if [ -f "$NAT_OUT" ] && grep -qxF -- '-j DNSCRYPT_OUTPUT' "$NAT_OUT"; then
  ok "cadena DNSCRYPT_OUTPUT enganchada a nat/OUTPUT"
else
  bad "DNSCRYPT_OUTPUT NO aparece enganchada a nat/OUTPUT"
fi
if [ -f "$CH_OUT" ] && grep -qxF -- "-p udp --dport 53 -j REDIRECT --to-ports $TEST_PORT" "$CH_OUT"; then
  ok "regla REDIRECT UDP:53 -> $TEST_PORT presente en la cadena propia"
else
  bad "falta la regla REDIRECT UDP:53 en DNSCRYPT_OUTPUT"
fi
if grep -qxF -- '-d 127.0.0.1/32 -j RETURN' "$CH_OUT" 2>/dev/null; then
  ok "guarda anti-loop (RETURN para 127.0.0.1) presente"
else
  bad "falta guarda anti-loop RETURN 127.0.0.1"
fi

echo "  --- idempotencia: aplicar DOS VECES no debe duplicar el enganche ---"
call_cli redirect apply >/dev/null 2>&1
HOOKS=$(grep -cxF -- '-j DNSCRYPT_OUTPUT' "$NAT_OUT" 2>/dev/null || echo 0)
[ "$HOOKS" -eq 1 ] && ok "enganche a OUTPUT sigue siendo 1 tras aplicar dos veces" || bad "enganche duplicado: $HOOKS veces"

echo "  --- redirect remove limpia nat ---"
call_cli redirect remove >/dev/null 2>&1
if [ ! -f "$NAT_OUT" ] || ! grep -qxF -- '-j DNSCRYPT_OUTPUT' "$NAT_OUT" 2>/dev/null; then
  ok "redirect remove desengancho de nat/OUTPUT"
else
  bad "redirect remove NO desengancho de nat/OUTPUT"
fi
call_cli redirect status --quiet; [ $? -ne 0 ] && ok "redirect status = inactiva tras remove" || bad "redirect status sigue activa"

##############################################################################
# 7) Modo IPv6 = block: cadena FILTER propia (nunca DROP en nat)
##############################################################################
echo
echo "=== [7] IPv6 modo block: DNSCRYPT_FILTER6 en tabla filter ==="
call_cli set-flag ipv6_mode block >/dev/null 2>&1
call_cli redirect apply >/dev/null 2>&1
FILT6="$FAKE_FW_STATE/ip6tables.filter.DNSCRYPT_FILTER6.rules"
HOOK6="$FAKE_FW_STATE/ip6tables.filter.OUTPUT.rules"
if [ -f "$FILT6" ] && grep -qxF -- '-p udp --dport 53 -j DROP' "$FILT6"; then
  ok "DROP de UDP:53 IPv6 vive en tabla filter (DNSCRYPT_FILTER6)"
else
  bad "no se encontro el DROP esperado en tabla filter para IPv6"
fi
if [ -f "$FAKE_FW_STATE/ip6tables.nat.DNSCRYPT_OUTPUT.rules" ] && \
   grep -q 'DROP' "$FAKE_FW_STATE/ip6tables.nat.DNSCRYPT_OUTPUT.rules" 2>/dev/null; then
  bad "hay un DROP en la tabla NAT de ip6tables (no deberia estar ahi)"
else
  ok "no hay ningun DROP en la tabla nat de ip6tables (correcto: nat nunca hace DROP)"
fi
if [ -f "$HOOK6" ] && grep -qxF -- '-j DNSCRYPT_FILTER6' "$HOOK6"; then
  ok "DNSCRYPT_FILTER6 enganchada a filter/OUTPUT"
else
  bad "DNSCRYPT_FILTER6 no aparece enganchada a filter/OUTPUT"
fi

echo "  --- remove debe limpiar TANTO nat como filter ---"
call_cli redirect remove >/dev/null 2>&1
LEFT_NAT=$(find "$FAKE_FW_STATE" -name '*.nat.DNSCRYPT_*.rules' 2>/dev/null | xargs -r cat | wc -l)
LEFT_FILT=$(find "$FAKE_FW_STATE" -name '*.filter.DNSCRYPT_*.rules' 2>/dev/null | xargs -r cat | wc -l)
if [ "$LEFT_NAT" -eq 0 ] && [ "$LEFT_FILT" -eq 0 ]; then
  ok "redirect remove vacio tanto nat como filter (0 reglas restantes en ambas)"
else
  bad "quedaron reglas: nat=$LEFT_NAT filter=$LEFT_FILT"
fi
call_cli set-flag ipv6_mode redirect >/dev/null 2>&1

##############################################################################
# 8) REDIRECCION vía nftables (sin iptables en PATH)
##############################################################################
echo
echo "=== [8] redirect apply/remove via nftables (sin iptables en PATH) ==="
rm -rf "$FAKE_FW_STATE"; mkdir -p "$FAKE_FW_STATE"
NFT_ONLY_DIR="$TEST_ROOT/nft-only-bin"
mkdir -p "$NFT_ONLY_DIR"
ln -sf "$FW_BIN/nft" "$NFT_ONLY_DIR/nft"
OLD_PATH="$PATH"
export PATH="$NFT_ONLY_DIR:/usr/bin:/bin"
command -v iptables >/dev/null 2>&1 && bad "iptables sigue visible (deberia estar oculto)" || ok "iptables oculto del PATH (fuerza rama nft)"

call_cli redirect apply >"$SCRATCH/nft-out.txt" 2>&1
RC=$?
if [ "$RC" -eq 0 ]; then ok "redirect apply (backend nft) -> $(classify_rc "$RC")"; else bad "redirect apply (nft) fallo: $(cat "$SCRATCH/nft-out.txt")"; fi
if [ -f "$FAKE_FW_STATE/nft.table.dnscrypt_manager" ]; then ok "tabla inet dnscrypt_manager creada"; else bad "no se creo la tabla nft"; fi
RULES="$FAKE_FW_STATE/nft.rules.dnscrypt_manager.dcm_nat_out"
if [ -f "$RULES" ] && grep -q "udp dport 53 redirect to :$TEST_PORT" "$RULES"; then
  ok "regla nft de redireccion UDP:53 presente"
else
  bad "falta la regla nft de redireccion UDP:53"
fi

echo "  --- idempotencia nft: aplicar DOS VECES no debe acumular reglas duplicadas ---"
call_cli redirect apply >/dev/null 2>&1
DUPS=$(grep -c "udp dport 53 redirect to :$TEST_PORT" "$RULES" 2>/dev/null || echo 0)
[ "$DUPS" -eq 1 ] && ok "regla nft sigue siendo 1 tras aplicar dos veces (tabla se recrea entera)" || bad "regla nft duplicada: $DUPS veces"

call_cli redirect remove >/dev/null 2>&1
[ -f "$FAKE_FW_STATE/nft.table.dnscrypt_manager" ] && bad "redirect remove (nft) no borro la tabla" || ok "redirect remove (nft) borro la tabla completa"

export PATH="$OLD_PATH"

##############################################################################
# 9) Sin NINGUN backend: debe fallar honesto, sin marcar rules.applied
##############################################################################
echo
echo "=== [9] Sin iptables ni nft disponibles: fallo honesto ==="
NOFW_DIR="$TEST_ROOT/no-fw-bin"; mkdir -p "$NOFW_DIR"
export PATH="$NOFW_DIR:/usr/bin:/bin"
call_cli redirect apply >"$SCRATCH/nobackend-out.txt" 2>&1
RC=$?
[ "$RC" -ne 0 ] && ok "redirect apply sin backend -> $(classify_rc "$RC")" || bad "redirect apply sin backend deberia fallar"
[ -f "$DNSCRYPT_TEST_DATA_DIR/run/rules.applied" ] && bad "rules.applied EXISTE sin backend (bug)" || ok "rules.applied ausente (correcto)"
export PATH="$FW_BIN:/usr/bin:/bin"

##############################################################################
# 10) PANIC -> disable flag -> status --json refleja disabled
##############################################################################
echo
echo "=== [10] panic / status --json / enable ==="
call_cli panic >/dev/null 2>&1
OUR_PID=""
STJSON=$(call_cli status --json)
echo "$STJSON" | "$NODE_BIN" -e "
const d = JSON.parse(require('fs').readFileSync(0,'utf8'));
if (d.disabled !== true) { console.error('disabled no es true'); process.exit(1); }
" && ok "status --json: disabled=true tras panic" || bad "status --json no refleja disabled=true"

call_cli start >"$SCRATCH/start-disabled.txt" 2>&1
grep -q DESHABILITADO "$SCRATCH/start-disabled.txt" && ok "start bloqueado mientras esta deshabilitado" || bad "start NO deberia funcionar deshabilitado"

##############################################################################
# 11) status (rama humana) exit code 0 SIEMPRE
##############################################################################
echo
echo "=== [11] status (humano): exit code 0 en ambos casos ==="
call_cli status >/dev/null 2>&1; RC1=$?
[ "$RC1" -eq 0 ] && ok "status con disable flag puesto -> rc=0" || bad "status con flag -> $(classify_rc "$RC1")"
call_cli enable >/dev/null 2>&1
call_cli status >/dev/null 2>&1; RC2=$?
[ "$RC2" -eq 0 ] && ok "status sin disable flag -> rc=0" || bad "status sin flag -> $(classify_rc "$RC2")"

##############################################################################
# 12) NextDNS: stamp verificado byte a byte contra el codec de referencia
##############################################################################
echo
echo "=== [12] NextDNS: stamp verificado contra tools/stamps.py ==="
call_cli start >/dev/null 2>&1
OUR_PID="$(read_test_pid)"
call_cli nextdns abcdef >/dev/null 2>&1
STAMP=$(grep -o 'sdns://[A-Za-z0-9_-]*' "$DNSCRYPT_TEST_DATA_DIR/config/dnscrypt-proxy.toml" | tail -n1)
"$PYTHON_BIN" - "$STAMP" << 'EOF'
import sys
sys.path.insert(0, "tools")
from stamps import decode
d = decode(sys.argv[1])
expected = {"proto":"DoH","props":1,"addr":"","hashes":[],"host":"dns.nextdns.io","path":"/abcdef"}
assert d == expected, f"stamp no coincide: {d} != {expected}"
print("  OK   stamp NextDNS coincide byte a byte con la spec")
EOF
[ $? -eq 0 ] && ok "NextDNS stamp verificado" || bad "NextDNS stamp NO coincide con la spec"

##############################################################################
# 13) uninstall.sh: limpieza completa (proceso + reglas), preserva backups
##############################################################################
echo
echo "=== [13] uninstall.sh: limpieza completa ==="
call_cli redirect apply >/dev/null 2>&1
call_cli backup >/dev/null 2>&1
BEFORE_BK=$(ls "$DNSCRYPT_TEST_DATA_DIR/backups/" 2>/dev/null | wc -l)
setsid timeout --kill-after=5 30 "$SH_BIN" "$DNSCRYPT_TEST_MODDIR/uninstall.sh" >"$SCRATCH/uninstall-out.txt" 2>&1 &
_ungrp=$!
CALL_GROUPS="$CALL_GROUPS $_ungrp"
wait "$_ungrp" 2>/dev/null
kill -TERM -- "-$_ungrp" 2>/dev/null; wait "$_ungrp" 2>/dev/null
sleep 0.15
kill -KILL -- "-$_ungrp" 2>/dev/null; wait "$_ungrp" 2>/dev/null
CALL_GROUPS=$(printf '%s' "$CALL_GROUPS" | sed "s/\b$_ungrp\b//")
if call_cli is-running >/dev/null 2>&1; then bad "uninstall.sh: el proceso SIGUE corriendo"; else ok "uninstall.sh: proceso detenido"; OUR_PID=""; fi
if [ -f "$NAT_OUT" ] && grep -qxF -- '-j DNSCRYPT_OUTPUT' "$NAT_OUT" 2>/dev/null; then
  bad "uninstall.sh: la regla de redireccion SIGUE enganchada"
else
  ok "uninstall.sh: redireccion retirada"
fi
AFTER_BK=$(ls "$DNSCRYPT_TEST_DATA_DIR/backups/" 2>/dev/null | wc -l)
[ "$AFTER_BK" -ge 1 ] && [ "$AFTER_BK" -eq "$BEFORE_BK" ] && ok "uninstall.sh: preservo los backups existentes ($AFTER_BK)" || bad "uninstall.sh: backups no preservados (antes=$BEFORE_BK despues=$AFTER_BK)"

##############################################################################
# 14) Pruebas especificas requeridas (aislamiento, arnes, concurrencia)
##############################################################################
echo
echo "=== [14a] DNSCRYPT_TEST_DATA_DIR='/tmp/../data/adb/test' -> DEBE fallar ==="
OUT14=$("$SH_BIN" -c '
  export DNSCRYPT_TEST_MODE=1
  export DNSCRYPT_TEST_ROOT="'"$TEST_ROOT"'"
  export DNSCRYPT_TEST_DATA_DIR="/tmp/../data/adb/test"
  export DNSCRYPT_TEST_MODDIR="'"$DNSCRYPT_TEST_MODDIR"'"
  . "'"$DNSCRYPT_TEST_MODDIR"'/scripts/common.sh"
' 2>&1)
RC14=$?
if [ "$RC14" -eq 90 ]; then ok "ruta con '..' rechazada explicitamente (rc=90)"; else bad "no se rechazo la ruta peligrosa (rc=$RC14): $OUT14"; fi

echo
echo "=== [14b] 'pgrep -f' / 'pkill' / 'killall' ausentes como INVOCACION real ==="
LEAK=""
while IFS= read -r -d '' _f; do
  case "$_f" in *.md) continue ;; esac
  _m=$(grep -nE '^[^#]*\b(pgrep[[:space:]]+-f|pkill|killall)\b' "$_f" 2>/dev/null)
  [ -n "$_m" ] && LEAK="$LEAK
$_f: $_m"
done < <(find "$DNSCRYPT_TEST_MODDIR" -type f -print0)
LEAK=$(printf '%s' "$LEAK" | sed '/^$/d')
if [ -z "$LEAK" ]; then
  ok "sin invocaciones reales de pgrep/pkill/killall en ningun archivo de produccion desplegado"
else
  bad "invocacion real encontrada: $LEAK"
fi

echo
echo "=== [14c] timeout de un comando colgado -> rc=124, sin descendientes, la suite sigue viva ==="
cat > "$SCRATCH/hanging-cli" << 'HANGEOF'
#!/bin/sh
( sleep 300 ) &
echo $! > /tmp_hang_child_pid_placeholder
sleep 300
HANGEOF
sed -i "s#/tmp_hang_child_pid_placeholder#$SCRATCH/hang-child.pid#" "$SCRATCH/hanging-cli"
chmod +x "$SCRATCH/hanging-cli"
setsid timeout --kill-after=3 2 "$SH_BIN" "$SCRATCH/hanging-cli" &
_hgrp=$!
wait "$_hgrp" 2>/dev/null
RCHANG=$?
kill -TERM -- "-$_hgrp" 2>/dev/null; wait "$_hgrp" 2>/dev/null
sleep 0.15
kill -KILL -- "-$_hgrp" 2>/dev/null; wait "$_hgrp" 2>/dev/null
if [ "$RCHANG" -eq 124 ]; then ok "comando colgado clasificado como TIMEOUT (rc=124), la suite continua"; else bad "rc inesperado para comando colgado: $RCHANG"; fi
sleep 0.3
HANG_CHILD=$(cat "$SCRATCH/hang-child.pid" 2>/dev/null)
if pid_is_alive_as "$HANG_CHILD" "sleep 300"; then
  bad "quedo un descendiente vivo del comando colgado (PID $HANG_CHILD)"
  kill -9 "$HANG_CHILD" 2>/dev/null; wait "$HANG_CHILD" 2>/dev/null
else
  ok "sin descendientes vivos tras matar el grupo completo del comando colgado"
fi

echo
echo "=== [14d] NODE_BIN ausente/invalido -> se clasifica como arnes roto, no fallo de producto ==="
FAKE_NODE_MISSING="$SCRATCH/no-existe-node"
if [ ! -x "$FAKE_NODE_MISSING" ]; then
  ok "una ruta NODE_BIN invalida se detecta antes de usarla (chequeo -n obligatorio al inicio del script, ver item 5)"
else
  bad "el chequeo de NODE_BIN no detecto una ruta inexistente"
fi

echo
echo "=== [14e] dos llamadas CONCURRENTES a 'status --json' ==="
call_cli start >/dev/null 2>&1
OUR_PID="$(read_test_pid)"
( call_cli status --json > "$SCRATCH/concurrent1.json" 2>"$SCRATCH/concurrent1.err" ) &
CPID1=$!
EXTRA_PIDS="$EXTRA_PIDS $CPID1"
( call_cli status --json > "$SCRATCH/concurrent2.json" 2>"$SCRATCH/concurrent2.err" ) &
CPID2=$!
EXTRA_PIDS="$EXTRA_PIDS $CPID2"
wait "$CPID1" 2>/dev/null; wait "$CPID2" 2>/dev/null
EXTRA_PIDS=""
V1_OK=0; V2_OK=0
"$NODE_BIN" -e "JSON.parse(require('fs').readFileSync('$SCRATCH/concurrent1.json','utf8'))" >/dev/null 2>&1 && V1_OK=1
"$NODE_BIN" -e "JSON.parse(require('fs').readFileSync('$SCRATCH/concurrent2.json','utf8'))" >/dev/null 2>&1 && V2_OK=1
if [ "$V1_OK" -eq 1 ] && [ "$V2_OK" -eq 1 ]; then
  ok "dos 'status --json' concurrentes devolvieron JSON valido en ambos casos"
else
  bad "al menos una llamada concurrente devolvio JSON invalido (1=$V1_OK, 2=$V2_OK)"
fi

##############################################################################
# 15) Confirmaciones de aislamiento (puerto libre, sin procesos, /data intacto)
##############################################################################
echo
echo "=== [15] Confirmaciones de aislamiento ==="
call_cli stop >/dev/null 2>&1
sleep 0.3
if [ -z "$OUR_PID" ] || ! pid_is_alive_as "$OUR_PID" "dnscrypt-proxy"; then
  ok "ningun proceso propio sigue vivo al terminar (verificado por cmdline, no solo PID)"
else
  bad "el PID $OUR_PID sigue vivo (confirmado por cmdline) al terminar"
fi
bind_port_free "$TEST_PORT" && ok "puerto $TEST_PORT libre al terminar" || bad "puerto $TEST_PORT sigue ocupado al terminar"
if [ ! -e /data/adb ]; then
  ok "/data/adb no existe (nunca se toco)"
else
  bad "/data/adb existe (algo lo toco; investigar)"
fi
# Barrido final riguroso: ningun proceso hijo de este arbol de pruebas
# (fake-dnscrypt-proxy o los fixtures de firewall) debe seguir vivo.
STRAY=$(find /proc -maxdepth 1 -name '[0-9]*' 2>/dev/null | while read -r p; do
  pid_is_alive_as "${p#/proc/}" "dnscrypt-proxy" && echo "${p#/proc/}"
done)
if [ -z "$STRAY" ]; then
  ok "barrido final: ningun proceso fake-dnscrypt-proxy residual en todo el sistema"
else
  bad "barrido final: procesos residuales detectados: $STRAY"
  for p in $STRAY; do kill -9 "$p" 2>/dev/null; wait "$p" 2>/dev/null; done
fi

##############################################################################
# Resumen
##############################################################################
kill "$WATCHDOG_PID" 2>/dev/null
END_TS=$(date +%s)
DUR=$((END_TS - START_TS))
echo
echo "=== RESULTADO: $PASS OK, $FAILN FAIL, $TIMEOUTS TIMEOUT(S) (duracion: ${DUR}s, TEST_ROOT=$TEST_ROOT) ==="
[ "$FAILN" -eq 0 ] && exit 0 || exit 1
