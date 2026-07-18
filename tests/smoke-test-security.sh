#!/bin/bash
##############################################################################
# tests/smoke-test-security.sh
# Creado por Skaymer AR
#
# Bateria funcional de la CAPA DE SEGURIDAD (v0.2.0), COMPLETAMENTE AISLADA.
# Reutiliza el mismo arnes endurecido que smoke-test-cli.sh (grupos de
# procesos propios via setsid+timeout, verificacion de "vivo" por cmdline,
# watchdog global, limpieza defensiva). Cubre los casos B-H del contrato:
#   B blocklists (valida/hosts/corrupta/binaria/enorme/lineas largas/
#     duplicados/invalidos/CRLF/hash incorrecto/rollback)
#   C allowlist (add/remove/dup/mayusculas/shell-injection/path-traversal/
#     import invalido)
#   D excepciones (crear/expirar via sweep/revocar/duracion invalida/reloj
#     cambiado/duplicados)
#   E perfiles (estado/cambio/atomico/rollback/fail-closed OFF por defecto)
#   F fugas (JSON valido, estados presentes)
#   G procesos (sin huerfanos/sin sockets/sin TEST_ROOT residual)
#   H salida JSON de eventos/allowlist/status valida
#
# Las descargas usan URLs file:// (permitidas SOLO bajo DNSCRYPT_TEST_MODE=1)
# apuntando a tests/fixtures/blocklists/*. El binario real no existe en el
# sandbox: se usa el doble fake-dnscrypt-proxy (su -check solo parsea el TOML,
# que es todo lo que el pipeline necesita para validar la config candidata).
#
# Uso:  bash tests/smoke-test-security.sh
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

TEST_ROOT="$(mktemp -d /tmp/dnscrypt-sec-test.XXXXXX)" || { echo "FATAL: mktemp -d" >&2; exit 99; }
export DNSCRYPT_TEST_MODE=1
export DNSCRYPT_TEST_ROOT="$TEST_ROOT"
export DNSCRYPT_TEST_DATA_DIR="$TEST_ROOT/data"
export DNSCRYPT_TEST_MODDIR="$TEST_ROOT/mod"
export DNSCRYPT_TEST_SHELL="$SH_BIN"
SCRATCH="$TEST_ROOT/scratch"; mkdir -p "$SCRATCH"

FW_BIN="$SRC_ROOT/tests/fixtures/fake-firewall-bin"
export FAKE_FW_STATE="$TEST_ROOT/fw-state"
M="$DNSCRYPT_TEST_MODDIR/system/bin/dnscrypt-manager"
FIX="$SRC_ROOT/tests/fixtures/blocklists"
SRCD="$DNSCRYPT_TEST_DATA_DIR/security/blocklists/sources.d"
CACHE="$DNSCRYPT_TEST_DATA_DIR/security/blocklists/cache"
CLI_TIMEOUT="${DNSCRYPT_TEST_CLI_TIMEOUT:-30}"
KILL_AFTER=5

PASS=0; FAILN=0; TIMEOUTS=0
OUR_PID=""; EXTRA_PIDS=""; CALL_GROUPS=""; TEST_PORT=""
START_TS=$(date +%s); MAIN_PID=$$

ok()  { PASS=$((PASS+1)); printf '  OK   %s\n' "$1"; }
bad() { FAILN=$((FAILN+1)); printf '  FAIL %s\n' "$1"; }

pid_is_alive_as() {
  _pid="$1"; _needle="$2"
  [ -n "$_pid" ] || return 1
  [ -r "/proc/$_pid/cmdline" ] || return 1
  tr '\0' ' ' < "/proc/$_pid/cmdline" 2>/dev/null | grep -qF -- "$_needle"
}

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

GLOBAL_TIMEOUT_SECS="${DNSCRYPT_TEST_GLOBAL_TIMEOUT:-280}"
( sleep "$GLOBAL_TIMEOUT_SECS"
  echo "FATAL: watchdog global (${GLOBAL_TIMEOUT_SECS}s) excedido; forzando aborto." >&2
  kill -TERM "$MAIN_PID" 2>/dev/null; sleep 5; kill -KILL "$MAIN_PID" 2>/dev/null
) &
WATCHDOG_PID=$!
disown "$WATCHDOG_PID" 2>/dev/null

cleanup() {
  kill "$WATCHDOG_PID" 2>/dev/null
  for grp in $CALL_GROUPS; do kill -TERM -- "-$grp" 2>/dev/null; wait "$grp" 2>/dev/null; done
  sleep 0.2
  for grp in $CALL_GROUPS; do kill -KILL -- "-$grp" 2>/dev/null; wait "$grp" 2>/dev/null; done
  _cur_pid=$(cat "$DNSCRYPT_TEST_DATA_DIR/run/dnscrypt-proxy.pid" 2>/dev/null)
  for p in "$_cur_pid" $OUR_PID $EXTRA_PIDS; do
    [ -n "$p" ] || continue
    kill -9 "$p" 2>/dev/null; wait "$p" 2>/dev/null
  done
  if [ "$FAILN" -gt 0 ]; then
    PRESERVE="$(mktemp -d /tmp/dcm-sec-failed.XXXXXX)"
    cp -a "$DNSCRYPT_TEST_DATA_DIR/logs" "$PRESERVE/" 2>/dev/null
    cp -a "$SCRATCH" "$PRESERVE/scratch" 2>/dev/null
    echo "  (hubo fallos: logs y scratch preservados en $PRESERVE)"
  fi
  rm -rf "$TEST_ROOT"
}
on_signal() { cleanup; exit 99; }
trap on_signal INT TERM
trap cleanup EXIT

call_cli() {
  setsid timeout --kill-after="$KILL_AFTER" "$CLI_TIMEOUT" "$DNSCRYPT_TEST_SHELL" "$M" "$@" &
  _grp=$!
  CALL_GROUPS="$CALL_GROUPS $_grp"
  wait "$_grp" 2>/dev/null
  rc=$?
  kill -TERM -- "-$_grp" 2>/dev/null; wait "$_grp" 2>/dev/null
  sleep 0.15
  kill -KILL -- "-$_grp" 2>/dev/null; wait "$_grp" 2>/dev/null
  CALL_GROUPS=$(printf '%s' "$CALL_GROUPS" | sed "s/\b$_grp\b//")
  if [ "$rc" -eq 124 ] || [ "$rc" -ge 128 ]; then
    _leftover=$(cat "$DNSCRYPT_TEST_DATA_DIR/run/dnscrypt-proxy.pid" 2>/dev/null)
    if [ -n "$_leftover" ]; then kill -9 "$_leftover" 2>/dev/null; wait "$_leftover" 2>/dev/null; fi
  fi
  if [ "$rc" -eq 126 ] || [ "$rc" -eq 127 ]; then
    echo "" >&2
    echo "FATAL: call_cli $* -> $(classify_rc "$rc")" >&2
    echo "       Fallo del ARNES DE PRUEBAS, no del producto. Abortando." >&2
    kill -TERM "$MAIN_PID" 2>/dev/null; exit 99
  fi
  [ "$rc" -eq 124 ] && TIMEOUTS=$((TIMEOUTS + 1))
  return "$rc"
}

# call_cli capturando stdout a un archivo (rc preservado).
call_cap() { _out="$1"; shift; call_cli "$@" > "$_out" 2>"$_out.err"; return $?; }

read_test_pid() { cat "$DNSCRYPT_TEST_DATA_DIR/run/dnscrypt-proxy.pid" 2>/dev/null; }
bind_port_free() {
  "$PYTHON_BIN" -c "
import socket
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.bind(('127.0.0.1', $1)); s.close()
" 2>/dev/null
}
json_ok() { "$NODE_BIN" -e "JSON.parse(require('fs').readFileSync('$1','utf8'))" >/dev/null 2>&1; }

# Escribe un .src de prueba apuntando a una fixture via file://
write_src() {
  # $1 categoria  $2 fixture  $3 formato  $4 min_domains
  mkdir -p "$SRCD"
  cat > "$SRCD/$1.src" << EOF
name=fixture-$1
category=$1
url=file://$FIX/$2
format=$3
license=TEST
min_bytes=1
max_bytes=26214400
min_domains=$4
EOF
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
s.bind(('127.0.0.1', 0)); print(s.getsockname()[1]); s.close()
" 2>/dev/null)
case "$TEST_PORT" in ''|*[!0-9]*) echo "FATAL: no se pudo asignar puerto" >&2; exit 99 ;; esac
echo "  puerto de prueba: $TEST_PORT"

sed -e "s/127\.0\.0\.1:5354/127.0.0.1:$TEST_PORT/" -e "s/\[::1\]:5354/[::1]:$TEST_PORT/" \
  "$SRC_ROOT/config/dnscrypt-proxy.toml" > "$DNSCRYPT_TEST_DATA_DIR/config/dnscrypt-proxy.toml"
sed -e "s/127\.0\.0\.1:5354/127.0.0.1:$TEST_PORT/" -e "s/\[::1\]:5354/[::1]:$TEST_PORT/" \
  "$SRC_ROOT/config/defaults/dnscrypt-proxy.toml" > "$DNSCRYPT_TEST_DATA_DIR/config/defaults/dnscrypt-proxy.toml"

export PATH="$FW_BIN:$PATH"

##############################################################################
# A) Migracion inicial
##############################################################################
echo
echo "=== [A] Migracion v1 -> v2 ==="
call_cli migrate >/dev/null 2>&1 && ok "migrate rc=0" || bad "migrate fallo"
[ "$(cat "$DNSCRYPT_TEST_DATA_DIR/schema_version" 2>/dev/null)" = "3" ] && ok "schema_version = 3 (migra 1->2->3)" || bad "schema_version != 3"
[ -d "$DNSCRYPT_TEST_DATA_DIR/security" ] && ok "directorio security/ creado" || bad "falta security/"
call_cli migrate >/dev/null 2>&1 && ok "migrate idempotente (2da vez rc=0)" || bad "migrate 2da vez fallo"

##############################################################################
# B) Blocklists
##############################################################################
echo
echo "=== [B] Blocklists: pipeline de actualizacion verificada ==="

# B1 lista valida (formato domains)
write_src malware valid-domains.txt domains 2
if call_cap "$SCRATCH/b1.out" blocklists update malware; then
  _n=$(grep -c '' "$CACHE/malware.list" 2>/dev/null)
  [ "${_n:-0}" -ge 3 ] && ok "B1 lista valida aplicada ($_n dominios, dedupe+minusculas)" || bad "B1 conteo inesperado: $_n"
  grep -qx 'evilcaps.example' "$CACHE/malware.list" && ok "B1 normalizacion a minusculas OK" || bad "B1 sin normalizar a minusculas"
  [ "$(grep -c 'duplicated.example' "$CACHE/malware.list")" = "1" ] && ok "B1 duplicados colapsados" || bad "B1 duplicados no colapsados"
else
  bad "B1 update de lista valida fallo (rc=$?)"
fi

# B2 formato hosts
write_src phishing valid-hosts.txt hosts 2
if call_cap "$SCRATCH/b2.out" blocklists update phishing; then
  grep -qx 'adone.example' "$CACHE/phishing.list" && ! grep -q 'localhost' "$CACHE/phishing.list" \
    && ok "B2 formato hosts parseado (localhost descartado)" || bad "B2 hosts mal parseado"
else bad "B2 update hosts fallo"; fi

# B3 CRLF + invalidos mezclados -> solo validos
write_src scams mixed-invalid.txt domains 2
if call_cap "$SCRATCH/b3.out" blocklists update scams; then
  _n=$(grep -c '' "$CACHE/scams.list" 2>/dev/null)
  [ "${_n:-0}" = "2" ] && ! grep -q '1.2.3.4' "$CACHE/scams.list" \
    && ok "B3 CRLF normalizado + IPs/URLs/comodines rechazados (solo 2 validos)" || bad "B3 filtrado incorrecto ($_n)"
else bad "B3 update mixto fallo"; fi

# B4 lista binaria -> rechazo, NO se activa
write_src trackers binary.bin domains 1
call_cap "$SCRATCH/b4.out" blocklists update trackers; rc=$?
if [ "$rc" -ne 0 ] && [ ! -f "$CACHE/trackers.list" ]; then
  ok "B4 lista binaria rechazada (paso 5), no se activo"
else bad "B4 lista binaria no fue rechazada (rc=$rc)"; fi

# B5 solo invalidos -> rechazo por 0 dominios
write_src ads all-invalid.txt domains 1
call_cap "$SCRATCH/b5.out" blocklists update ads; rc=$?
[ "$rc" -ne 0 ] && ok "B5 lista sin dominios validos rechazada (nunca lista vacia activa)" || bad "B5 acepto lista vacia"

# B6 lineas absurdamente largas -> se descartan, resto OK
write_src cryptomining long-lines.txt domains 2
if call_cap "$SCRATCH/b6.out" blocklists update cryptomining; then
  _n=$(grep -c '' "$CACHE/cryptomining.list" 2>/dev/null)
  _maxlen=$(awk '{ if (length > m) m = length } END { print m+0 }' "$CACHE/cryptomining.list")
  [ "${_n:-0}" = "2" ] && [ "${_maxlen:-999}" -le 253 ] && ok "B6 lineas >512 descartadas (quedaron $_n, max len $_maxlen)" || bad "B6 linea larga no filtrada ($_n, max $_maxlen)"
else bad "B6 update lineas largas fallo"; fi

# B7 tamaño maximo -> rechazo (max_bytes=10)
mkdir -p "$SRCD"
cat > "$SRCD/malware.src" << EOF
name=fixture-huge
category=malware
url=file://$FIX/valid-domains.txt
format=domains
license=TEST
min_bytes=1
max_bytes=10
min_domains=1
EOF
call_cap "$SCRATCH/b7.out" blocklists update malware; rc=$?
[ "$rc" -ne 0 ] && grep -qi 'tama' "$SCRATCH/b7.out.err" "$SCRATCH/b7.out" 2>/dev/null && ok "B7 archivo por encima de max_bytes rechazado (paso 3)" || bad "B7 no rechazo por tamaño (rc=$rc)"

# B8 hash incorrecto -> rechazo (paso 4)
write_src malware valid-domains.txt domains 2
call_cap "$SCRATCH/b8.out" blocklists update malware --sha256 0000000000000000000000000000000000000000000000000000000000000000; rc=$?
[ "$rc" -ne 0 ] && grep -qi 'SHA-256 NO coincide' "$SCRATCH/b8.out.err" 2>/dev/null && ok "B8 SHA-256 esperado que no coincide -> rechazo" || bad "B8 no valido el hash (rc=$rc)"

# B9 rollback: primero re-aplicar valida (deja backup .prev), luego rollback
write_src malware valid-hosts.txt hosts 2
call_cli blocklists update malware >/dev/null 2>&1
write_src malware valid-domains.txt domains 2
call_cli blocklists update malware >/dev/null 2>&1   # ahora hay .prev (la de hosts)
if call_cap "$SCRATCH/b9.out" blocklists rollback malware; then
  grep -qx 'adone.example' "$CACHE/malware.list" && ok "B9 rollback restauro la version anterior" || bad "B9 rollback no restauro"
else bad "B9 rollback fallo (rc=$?)"; fi

# B10 validate detecta integridad
call_cap "$SCRATCH/b10.out" blocklists validate malware
grep -qi 'OK' "$SCRATCH/b10.out" && ok "B10 validate reporta OK sobre lista sana" || bad "B10 validate no reporto OK"
# Corromper y revalidar
echo "renglon_invalido con espacios" >> "$CACHE/malware.list"
call_cap "$SCRATCH/b10b.out" blocklists validate malware; rc=$?
[ "$rc" -ne 0 ] && ok "B10 validate detecta lista corrupta (sha/sintaxis)" || bad "B10 validate no detecto corrupcion"

##############################################################################
# C) Allowlist
##############################################################################
echo
echo "=== [C] Allowlist ==="
call_cli allowlist add example.com >/dev/null 2>&1 && ok "C add example.com" || bad "C add fallo"
call_cap "$SCRATCH/c_dup.out" allowlist add EXAMPLE.COM
grep -qi 'Ya estaba' "$SCRATCH/c_dup.out" && ok "C mayusculas normalizadas + duplicado detectado" || bad "C no detecto duplicado por mayusculas"
call_cli allowlist add "https://evil.com" >/dev/null 2>&1; [ $? -ne 0 ] && ok "C rechaza URL con esquema" || bad "C acepto URL"
call_cli allowlist add "a.com/path" >/dev/null 2>&1; [ $? -ne 0 ] && ok "C rechaza path" || bad "C acepto path"
call_cli allowlist add "*.wild.com;reboot" >/dev/null 2>&1; [ $? -ne 0 ] && ok "C rechaza shell-injection/comodin" || bad "C acepto inyeccion"
call_cli allowlist add "127.0.0.1" >/dev/null 2>&1; [ $? -ne 0 ] && ok "C rechaza IP" || bad "C acepto IP"
# Path traversal en import
call_cli allowlist import "../../../etc/passwd" >/dev/null 2>&1; [ $? -ne 0 ] && ok "C import rechaza path traversal (..)" || bad "C import acepto traversal"
call_cli allowlist import "/etc/hostname_inexistente_xyz" >/dev/null 2>&1; [ $? -ne 0 ] && ok "C import rechaza archivo inexistente" || bad "C import acepto inexistente"
# Import valido desde una fixture de dominios
cp "$FIX/valid-domains.txt" "$SCRATCH/import-ok.txt"
call_cap "$SCRATCH/c_imp.out" allowlist import "$SCRATCH/import-ok.txt"
grep -qi 'Agregados' "$SCRATCH/c_imp.out" && ok "C import valido agrega dominios" || bad "C import valido fallo"
call_cli allowlist remove example.com >/dev/null 2>&1 && ok "C remove example.com" || bad "C remove fallo"
# JSON valido
call_cap "$SCRATCH/c_json.out" allowlist list --json
json_ok "$SCRATCH/c_json.out" && ok "C allowlist list --json es JSON valido" || bad "C JSON invalido"

##############################################################################
# D) Excepciones temporales
##############################################################################
echo
echo "=== [D] Excepciones temporales ==="
call_cli temporary-allow add tmp.example 15m --reason prueba >/dev/null 2>&1 && ok "D crear 15m" || bad "D crear fallo"
call_cap "$SCRATCH/d_list.out" temporary-allow list
grep -q 'tmp.example' "$SCRATCH/d_list.out" && ok "D excepcion vigente listada" || bad "D no listo la excepcion"
call_cli temporary-allow add tmp.example 1h >/dev/null 2>&1
_cnt=$(grep -c '^tmp.example	' "$DNSCRYPT_TEST_DATA_DIR/security/exceptions.tsv" 2>/dev/null)
[ "${_cnt:-0}" = "1" ] && ok "D duplicado reemplaza (no acumula)" || bad "D duplicado acumulo ($_cnt)"
call_cli temporary-allow add bad.example 99z >/dev/null 2>&1; [ $? -ne 0 ] && ok "D duracion invalida rechazada" || bad "D acepto duracion invalida"
# Reloj cambiado: inyectar una excepcion "creada en el futuro" -> sweep la descarta
EXC="$DNSCRYPT_TEST_DATA_DIR/security/exceptions.tsv"
_future=$(( $(date +%s) + 999999 ))
printf 'futuro.example\t%s\t%s\tcli\t%s\treloj\n' "$(( _future + 3600 ))" "$_future" "$(cat /proc/sys/kernel/random/boot_id 2>/dev/null)" >> "$EXC"
call_cli temporary-allow sweep >/dev/null 2>&1
grep -q 'futuro.example' "$EXC" && bad "D sweep no descarto excepcion con reloj futuro" || ok "D sweep descarta excepcion creada 'en el futuro' (reloj cambiado)"
# Expiracion: excepcion ya vencida -> sweep la elimina
printf 'vencida.example\t%s\t%s\tcli\t%s\tvieja\n' "$(( $(date +%s) - 10 ))" "$(( $(date +%s) - 20 ))" "$(cat /proc/sys/kernel/random/boot_id 2>/dev/null)" >> "$EXC"
call_cli temporary-allow sweep >/dev/null 2>&1
grep -q 'vencida.example' "$EXC" && bad "D sweep no elimino excepcion vencida" || ok "D sweep elimina excepcion expirada (sin reiniciar)"
# Revocar
call_cli temporary-allow remove tmp.example >/dev/null 2>&1 && ! grep -q 'tmp.example' "$EXC" && ok "D revocar elimina la excepcion" || bad "D revocar fallo"
# boot exception: bootid distinto -> sweep la quita
printf 'boota.example\tboot\t%s\tcli\tBOOTVIEJO-0000\tboot\n' "$(date +%s)" >> "$EXC"
call_cli temporary-allow sweep >/dev/null 2>&1
grep -q 'boota.example' "$EXC" && bad "D sweep no quito excepcion de boot anterior" || ok "D excepcion 'hasta reiniciar' de un boot anterior se descarta"

##############################################################################
# E) Perfiles de seguridad
##############################################################################
echo
echo "=== [E] Perfiles de seguridad ==="
call_cap "$SCRATCH/e_bal.out" security-profile balanced
grep -qi 'aplicado' "$SCRATCH/e_bal.out" && ok "E balanced aplicado" || bad "E balanced fallo"
[ "$(call_cli get-flag failclosed 2>/dev/null; true)" ]  # no-op para claridad
_fc=$(grep '^failclosed=' "$DNSCRYPT_TEST_DATA_DIR/run/state.env" 2>/dev/null | cut -d= -f2)
[ "${_fc:-0}" = "0" ] && ok "E fail-closed DESACTIVADO por defecto tras balanced" || bad "E fail-closed quedo en $_fc tras balanced"
# strict SIN --confirmed -> no aplica (rc 3)
call_cap "$SCRATCH/e_str_noconf.out" security-profile strict; rc=$?
[ "$rc" -eq 3 ] && ok "E strict sin --confirmed NO aplica (pide confirmacion)" || bad "E strict aplico sin confirmar (rc=$rc)"
_fc=$(grep '^failclosed=' "$DNSCRYPT_TEST_DATA_DIR/run/state.env" 2>/dev/null | cut -d= -f2)
[ "${_fc:-0}" = "0" ] && ok "E fail-closed sigue en 0 tras strict no confirmado" || bad "E fail-closed cambio sin confirmar"
# strict CON --confirmed
call_cap "$SCRATCH/e_str.out" security-profile strict --confirmed
grep -qi 'aplicado' "$SCRATCH/e_str.out" && ok "E strict --confirmed aplicado" || bad "E strict confirmado fallo"
_fc=$(grep '^failclosed=' "$DNSCRYPT_TEST_DATA_DIR/run/state.env" 2>/dev/null | cut -d= -f2)
[ "${_fc:-0}" = "1" ] && ok "E strict activa fail-closed (flag=1)" || bad "E strict no activo fail-closed"
# volver a privacy -> fail-closed a 0
call_cli security-profile privacy >/dev/null 2>&1
_fc=$(grep '^failclosed=' "$DNSCRYPT_TEST_DATA_DIR/run/state.env" 2>/dev/null | cut -d= -f2)
[ "${_fc:-0}" = "0" ] && ok "E privacy desactiva fail-closed" || bad "E privacy no desactivo fail-closed"
call_cap "$SCRATCH/e_json.out" security-profile status --json
json_ok "$SCRATCH/e_json.out" && ok "E security-profile status --json valido" || bad "E JSON perfil invalido"

##############################################################################
# F) Fugas
##############################################################################
echo
echo "=== [F] Detector de fugas DNS ==="
call_cap "$SCRATCH/f.json" leak-test --json; rc=$?
json_ok "$SCRATCH/f.json" && ok "F leak-test --json es JSON valido" || bad "F JSON de fugas invalido"
"$NODE_BIN" -e "
const d=JSON.parse(require('fs').readFileSync('$SCRATCH/f.json','utf8'));
const st=new Set(d.checks.map(c=>c.state));
const names=d.checks.map(c=>c.name);
if(!names.includes('doh_navegador')) { console.error('falta doh_navegador'); process.exit(1); }
const doh=d.checks.find(c=>c.name==='doh_navegador');
if(doh.state!=='no_verificable'){ console.error('doh_navegador deberia ser no_verificable'); process.exit(1); }
if(!names.includes('udp53_ipv4')||!names.includes('tcp53_ipv6')){ console.error('faltan chequeos de puerto'); process.exit(1); }
process.exit(0);
" && ok "F estados presentes; DoH de navegador reportado como no_verificable (no se afirma bloqueo)" || bad "F contenido de fugas incorrecto"

##############################################################################
# G) Historial / eventos (JSON) + set-flag de privacidad
##############################################################################
echo
echo "=== [G] Eventos e historial ==="
call_cap "$SCRATCH/g_ev.json" events list --json
json_ok "$SCRATCH/g_ev.json" && ok "G events list --json valido (vacio)" || bad "G JSON eventos invalido"
# Inyectar un log de eventos como lo escribiria dnscrypt-proxy
mkdir -p "$DNSCRYPT_TEST_DATA_DIR/security/events"
printf '[%s]\t127.0.0.1\tmalone.example\tmalone.example\n' "$(date '+%Y-%m-%d %H:%M:%S')" > "$DNSCRYPT_TEST_DATA_DIR/security/events/blocked.log"
# Necesitamos la lista malware para categorizar
write_src malware valid-domains.txt domains 2
call_cli blocklists update malware >/dev/null 2>&1
call_cap "$SCRATCH/g_ev2.json" events list --json
json_ok "$SCRATCH/g_ev2.json" && ok "G events list --json valido (con datos)" || bad "G JSON eventos con datos invalido"
"$NODE_BIN" -e "
const d=JSON.parse(require('fs').readFileSync('$SCRATCH/g_ev2.json','utf8'));
if(!d.events.length){console.error('sin eventos');process.exit(1);}
if(d.events[0].category!=='malware'){console.error('categoria mal atribuida: '+d.events[0].category);process.exit(1);}
process.exit(0);
" && ok "G evento atribuido a categoria 'malware' por la regla" || bad "G categorizacion de evento incorrecta"
call_cap "$SCRATCH/g_stats.json" events stats --json
json_ok "$SCRATCH/g_stats.json" && ok "G events stats --json valido" || bad "G JSON stats invalido"
call_cli events pause >/dev/null 2>&1 && [ "$(grep '^hist_mode=' "$DNSCRYPT_TEST_DATA_DIR/run/state.env" | cut -d= -f2)" = "off" ] && ok "G pause -> hist_mode off" || bad "G pause fallo"
call_cli events resume >/dev/null 2>&1 && [ "$(grep '^hist_mode=' "$DNSCRYPT_TEST_DATA_DIR/run/state.env" | cut -d= -f2)" != "off" ] && ok "G resume restaura hist_mode" || bad "G resume fallo"
# set-flag hist_max fuera de rango
call_cli set-flag hist_max 99999 >/dev/null 2>&1; [ $? -ne 0 ] && ok "G set-flag hist_max fuera de rango rechazado" || bad "G acepto hist_max invalido"
call_cli set-flag hist_days 5 >/dev/null 2>&1; [ $? -ne 0 ] && ok "G set-flag hist_days invalido rechazado" || bad "G acepto hist_days invalido"
call_cli set-flag hist_mode blocked >/dev/null 2>&1 && ok "G set-flag hist_mode valido aceptado" || bad "G rechazo hist_mode valido"

##############################################################################
# H) status --json integra seguridad
##############################################################################
echo
echo "=== [H] status --json con campos de seguridad ==="
call_cap "$SCRATCH/h_status.json" status --json
json_ok "$SCRATCH/h_status.json" && ok "H status --json valido" || bad "H status JSON invalido"
"$NODE_BIN" -e "
const d=JSON.parse(require('fs').readFileSync('$SCRATCH/h_status.json','utf8'));
for(const k of ['failclosed','security_profile','blocked_domains','events_count']){
  if(!(k in d)){console.error('falta campo '+k);process.exit(1);}
}
if(d.failclosed!==false){console.error('failclosed deberia ser false por defecto');process.exit(1);}
process.exit(0);
" && ok "H status incluye failclosed(false)/security_profile/blocked_domains/events_count" || bad "H faltan campos de seguridad en status"

##############################################################################
# I) Aislamiento (procesos, sockets, /data, TEST_ROOT)
##############################################################################
echo
echo "=== [I] Aislamiento y limpieza ==="
# Ningun daemon deberia haber quedado vivo (esta suite no arranca el proxy)
_leftpid=$(read_test_pid)
if [ -z "$_leftpid" ] || ! pid_is_alive_as "$_leftpid" "dnscrypt-proxy"; then
  ok "I ningun dnscrypt-proxy propio vivo (esta suite no arranca el daemon)"
else
  bad "I quedo un proceso vivo: $_leftpid"; kill -9 "$_leftpid" 2>/dev/null
fi
bind_port_free "$TEST_PORT" && ok "I puerto $TEST_PORT libre" || bad "I puerto $TEST_PORT ocupado"
[ ! -e /data/adb ] && ok "I /data/adb no existe (nunca se toco)" || bad "I /data/adb existe (investigar)"
STRAY=$(find /proc -maxdepth 1 -name '[0-9]*' 2>/dev/null | while read -r p; do
  pid_is_alive_as "${p#/proc/}" "dnscrypt-proxy" && echo "${p#/proc/}"
done)
[ -z "$STRAY" ] && ok "I barrido final: ningun fake-dnscrypt-proxy residual" || { bad "I residuales: $STRAY"; for p in $STRAY; do kill -9 "$p" 2>/dev/null; done; }

##############################################################################
# Resumen
##############################################################################
kill "$WATCHDOG_PID" 2>/dev/null
END_TS=$(date +%s); DUR=$((END_TS - START_TS))
echo
echo "=== RESULTADO: $PASS OK, $FAILN FAIL, $TIMEOUTS TIMEOUT(S) (duracion: ${DUR}s, TEST_ROOT=$TEST_ROOT) ==="
[ "$FAILN" -eq 0 ] && exit 0 || exit 1
