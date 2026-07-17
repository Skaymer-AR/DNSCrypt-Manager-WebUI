#!/bin/bash
##############################################################################
# tests/smoke-test-compile.sh   —  Creado por Skaymer AR
#
# Pipeline operativo de compilacion (lock atomico, PID validado, lock huerfano,
# cancelacion, timeout, progreso, trap) y estadisticas de APORTE UNICO.
# La operacion pesada se simula con un hook numerico bajo DNSCRYPT_TEST_MODE
# (sin eval, sin comandos arbitrarios). Determinista.
#
# Uso:  bash tests/smoke-test-compile.sh    Exit: 0 OK, 1 fallo, 99 arnes roto.
##############################################################################
set -u
cd "$(dirname "$0")/.." || exit 1
SRC_ROOT="$(pwd)"; SH_BIN="$(command -v sh)"; PY="$(command -v python3)"
[ -n "$SH_BIN" ] && [ -n "$PY" ] || { echo "FATAL: falta sh/python3" >&2; exit 99; }

TR="$(mktemp -d /tmp/dcm-comp-test.XXXXXX)" || exit 99
export DNSCRYPT_TEST_MODE=1 DNSCRYPT_TEST_ROOT="$TR" DNSCRYPT_TEST_DATA_DIR="$TR/data" DNSCRYPT_TEST_MODDIR="$TR/mod" DNSCRYPT_TEST_SHELL="$SH_BIN"
M="$TR/mod/system/bin/dnscrypt-manager"; DATA="$TR/data"
PASS=0; FAILN=0; STRAY_SLEEPS=""
ok(){ PASS=$((PASS+1)); printf '  OK   %s\n' "$1"; }
bad(){ FAILN=$((FAILN+1)); printf '  FAIL %s\n' "$1"; }

( sleep 180; echo "FATAL watchdog" >&2; kill -TERM $$ 2>/dev/null ) & WD=$!
cleanup(){ kill "$WD" 2>/dev/null; for p in $STRAY_SLEEPS; do kill -9 "$p" 2>/dev/null; done; rm -rf "$TR"; }
trap 'cleanup; exit 99' INT TERM; trap cleanup EXIT

mkdir -p "$DATA/bin" "$DATA/config"
cp -a "$SRC_ROOT/." "$TR/mod/"; rm -rf "$TR/mod/tests" "$TR/mod/tools" "$TR/mod/.git"
cp "$SRC_ROOT/tests/fixtures/fake-dnscrypt-proxy" "$DATA/bin/dnscrypt-proxy" 2>/dev/null; chmod 0755 "$DATA/bin/dnscrypt-proxy" 2>/dev/null
cp "$SRC_ROOT/config/dnscrypt-proxy.toml" "$DATA/config/dnscrypt-proxy.toml"
cli(){ "$SH_BIN" "$M" "$@"; }
inlib(){ ( cd "$TR/mod" && "$SH_BIN" -c ". scripts/common.sh 2>/dev/null;. scripts/security.sh 2>/dev/null;. scripts/catalog.sh 2>/dev/null; $1" ); }

echo "=== Preparando entorno en $TR ==="
cli migrate >/dev/null 2>&1

# fixtures de dos fuentes con overlap conocido
FX="$TR/fx"; mkdir -p "$FX"
printf 'aaaa.example.net\nbbbb.example.net\ncccc.example.net\naaaa.example.net\n' > "$FX/x.txt"  # 4 total, 3 unicos
printf 'cccc.example.net\ndddd.example.net\neeee.example.net\n' > "$FX/y.txt"  # overlap {cccc}
# X = rc1_urlhaus (recomendada=1 -> primera en orden canonico); Y = rc1_phishing_army (0)
awk -F'\t' -v OFS='\t' -v u="file://$FX/x.txt" '$1=="rc1_urlhaus"{$7="domains";$8=u;$11="1"}1' "$DATA/catalog/blocklists.index.tsv" > "$TR/t" && mv "$TR/t" "$DATA/catalog/blocklists.index.tsv"
awk -F'\t' -v OFS='\t' -v u="file://$FX/y.txt" '$1=="rc1_phishing_army"{$7="domains";$8=u;$11="0"}1' "$DATA/catalog/blocklists.index.tsv" > "$TR/t" && mv "$TR/t" "$DATA/catalog/blocklists.index.tsv"

# =====================================================================
echo "== I. Aporte unico (orden canonico, comm/sort por lotes) =="
inlib "cat_update_one rc1_urlhaus >/dev/null 2>&1; cat_update_one rc1_phishing_army >/dev/null 2>&1; cat_enable rc1_urlhaus; cat_enable rc1_phishing_army; cat_stats_compute; cat stats 2>/dev/null; cat \"\$CAT_STATS\"" > "$TR/st" 2>&1
# X primero (recomendada): unico=3 ; Y: unico=2, already_present=1
grep -q "^rc1_urlhaus	3	0	0	3	0" "$DATA/catalog/contribution-stats.tsv" && ok "I1 X: total3/intdup0(cache deduplicado)/unico3/red0%" || bad "I1 stats X ($(grep rc1_urlhaus $DATA/catalog/contribution-stats.tsv))"
grep -q "^rc1_phishing_army	3	0	1	2	33" "$DATA/catalog/contribution-stats.tsv" && ok "I2 Y: already_present1/unico2/red33%" || bad "I2 stats Y ($(grep phishing $DATA/catalog/contribution-stats.tsv))"
grep -q "^#summary	total_unique	5	allowlisted	0	effective	5" "$DATA/catalog/contribution-stats.tsv" && ok "I3 resumen: total_unico=5, efectivo=5" || bad "I3 resumen ($(grep summary $DATA/catalog/contribution-stats.tsv))"
# efectivo tras allowlist
cli allowlist add cccc.example.net >/dev/null 2>&1
inlib "cat_stats_compute; grep '^#summary' \"\$CAT_STATS\"" > "$TR/st2" 2>&1
grep -q "effective	4" "$TR/st2" && ok "I4 allowlist reduce el efectivo (5->4)" || bad "I4 efectivo allowlist ($(cat $TR/st2))"
cli allowlist remove cccc.example.net >/dev/null 2>&1
# orden canonico estable: X (recomendada) siempre antes que Y
FIRST=$(inlib "cat_enabled_ordered" 2>/dev/null | head -1)
[ "$FIRST" = "rc1_urlhaus" ] && ok "I5 orden canonico estable (recomendada primero)" || bad "I5 orden ($FIRST)"

# =====================================================================
echo "== J. Pipeline: lock / huerfano / cancelacion / timeout / progreso =="
# descendants: recorre /proc por PPID desde un PID raiz (para rastrear subarbol).
descendants() {
  _root="$1"; [ -n "$_root" ] || return 0; _pending="$_root"; _acc=""
  while [ -n "$_pending" ]; do
    _next=""
    for _p in $_pending; do
      for _st in /proc/[0-9]*/stat; do
        [ -r "$_st" ] || continue
        set -- $(sed 's/([^)]*)/X/' "$_st" 2>/dev/null)
        if [ "${4:-}" = "$_p" ]; then _acc="$_acc $1"; _next="$_next $1"; fi
      done
    done
    _pending="$_next"
  done
  echo $_acc
}
# starttime (campo 22 de /proc/PID/stat, tras neutralizar (comm)) para detectar
# reutilizacion de PID: si cambia, el PID ya no es el proceso que registramos.
pid_starttime() {
  [ -r "/proc/$1/stat" ] || { echo ""; return; }
  set -- $(sed 's/([^)]*)/X/' "/proc/$1/stat" 2>/dev/null); echo "${22:-}"
}
# Registro tecnico de procesos del test (evidencia, no se commitea).
REG_TSV="$TR/process-registry.tsv"
printf 'phase\tpid\tppid\tpgid\tstarttime\tcmd\n' > "$REG_TSV"
reg_row() {
  _p="$1"; _ph="$2"; [ -d "/proc/$_p" ] || return 0
  _ppid=$(awk '/^PPid:/{print $2}' "/proc/$_p/status" 2>/dev/null)
  _pgid=$(ps -o pgid= -p "$_p" 2>/dev/null | tr -d ' ')
  _cmd=$(tr '\0' ' ' < "/proc/$_p/cmdline" 2>/dev/null)
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$_ph" "$_p" "${_ppid:-?}" "${_pgid:-?}" "$(pid_starttime "$_p")" "$_cmd" >> "$REG_TSV"
}
# KIDS: lista "pid:starttime" del hijo pesado que el motor anota en el lock y de
# su subarbol, capturada ANTES de cancel/timeout/PANIC.
KIDS=""
reg_kids() {
  _phase="${1:-run}"
  _c=$(cat "$DATA/run/catalog.compile.lock/child" 2>/dev/null)
  [ -n "$_c" ] || return 0
  for _p in $_c $(descendants "$_c"); do
    [ -n "$_p" ] || continue
    _st=$(pid_starttime "$_p")
    KIDS="$KIDS $_p:$_st"
    reg_row "$_p" "$_phase-before"
  done
}
# J1 exito + status=done (stub rapido, SLEEP no seteado)
cli catalog compile > "$TR/c" 2>&1
grep -q "OK: compilacion terminada" "$TR/c" && ok "J1 compilacion exitosa (hook)" || bad "J1 compile ($(cat $TR/c))"
cli catalog compile-status > "$TR/cs" 2>&1
grep -q "estado    : inactiva" "$TR/cs" && grep -q "progreso  : done" "$TR/cs" && ok "J2 compile-status: inactiva + progreso done" || bad "J2 status ($(cat $TR/cs))"
[ ! -d "$DATA/run/catalog.compile.lock" ] && ok "J3 trap: lock liberado tras compilar" || bad "J3 lock no liberado"

# J4 lock ocupado: una compilacion lenta en curso -> la segunda se rechaza
DNSCRYPT_TEST_COMPILE_SLEEP=6 cli catalog compile > "$TR/cbg" 2>&1 & BGP=$!
_tries=0; while [ ! -d "$DATA/run/catalog.compile.lock" ] && [ $_tries -lt 50 ]; do sleep 0.1; _tries=$((_tries+1)); done
sleep 0.3; reg_kids cancel   # anotar hijo pesado (se cancelara en J5)
cli catalog compile > "$TR/c2" 2>&1
grep -q "ya hay una compilacion en curso" "$TR/c2" && ok "J4 lock ocupado: segunda compilacion rechazada" || bad "J4 no rechazo ($(cat $TR/c2))"

# J5 cancelacion: cancelar la compilacion en curso (mata solo nuestro hijo)
cli catalog compile-cancel > "$TR/cc" 2>&1
grep -qi "cancelada" "$TR/cc" && ok "J5 compile-cancel reporta cancelacion" || bad "J5 cancel ($(cat $TR/cc))"
wait "$BGP" 2>/dev/null
cli catalog compile-status > "$TR/cs2" 2>&1
grep -q "cancelled" "$TR/cs2" && ok "J6 progreso registra cancelled" || bad "J6 progreso ($(cat $TR/cs2))"
[ ! -d "$DATA/run/catalog.compile.lock" ] && ok "J7 lock liberado tras cancelar" || bad "J7 lock tras cancel"

# J8 lock HUERFANO (pid muerto) -> recuperable
mkdir -p "$DATA/run/catalog.compile.lock"; echo 999999 > "$DATA/run/catalog.compile.lock/pid"; echo "$(date +%s)" > "$DATA/run/catalog.compile.lock/started"
cli catalog compile > "$TR/c3" 2>&1
grep -q "OK: compilacion terminada" "$TR/c3" && ok "J8 lock huerfano (pid muerto) recuperado" || bad "J8 huerfano muerto ($(cat $TR/c3))"

# J9 lock HUERFANO por PID reutilizado (proceso vivo ajeno, sin marcador)
sleep 30 & ALIEN=$!; STRAY_SLEEPS="$STRAY_SLEEPS $ALIEN"
mkdir -p "$DATA/run/catalog.compile.lock"; echo "$ALIEN" > "$DATA/run/catalog.compile.lock/pid"; echo "$(date +%s)" > "$DATA/run/catalog.compile.lock/started"
cli catalog compile > "$TR/c4" 2>&1
grep -q "OK: compilacion terminada" "$TR/c4" && ok "J9 lock huerfano (PID ajeno vivo) recuperado" || bad "J9 huerfano ajeno ($(cat $TR/c4))"
kill -9 "$ALIEN" 2>/dev/null; STRAY_SLEEPS=""

# J10 timeout: SLEEP largo con timeout corto -> aborta y conserva lista
LSHA=$(sha256sum "$DATA/security/active/blocked-names.txt" 2>/dev/null | cut -d' ' -f1)
DNSCRYPT_TEST_COMPILE_SLEEP=8 CAT_COMPILE_TIMEOUT=2 cli catalog compile > "$TR/c5" 2>&1 & BGT=$!
_tries=0; while [ ! -d "$DATA/run/catalog.compile.lock" ] && [ $_tries -lt 50 ]; do sleep 0.1; _tries=$((_tries+1)); done
sleep 0.3; reg_kids timeout   # anotar hijo pesado del timeout
wait "$BGT" 2>/dev/null
grep -q "timeout" "$TR/c5" && ok "J10 timeout aborta la compilacion" || bad "J10 timeout ($(cat $TR/c5))"
[ ! -d "$DATA/run/catalog.compile.lock" ] && ok "J11 lock liberado tras timeout" || bad "J11 lock tras timeout"

# J12 PANIC cancela compilacion en curso sin borrar catalogos
DNSCRYPT_TEST_COMPILE_SLEEP=6 cli catalog compile >/dev/null 2>&1 & BGP2=$!
_tries=0; while [ ! -d "$DATA/run/catalog.compile.lock" ] && [ $_tries -lt 50 ]; do sleep 0.1; _tries=$((_tries+1)); done
sleep 0.3; reg_kids panic   # anotar hijo pesado (PANIC lo cancela)
ENABLED_BEFORE=$(wc -l < "$DATA/catalog/enabled.txt" 2>/dev/null | tr -d ' ')
cli panic >/dev/null 2>&1
wait "$BGP2" 2>/dev/null
[ ! -d "$DATA/run/catalog.compile.lock" ] && ok "J13 PANIC libera el lock de compilacion" || bad "J13 PANIC no libero lock"
ENABLED_AFTER=$(wc -l < "$DATA/catalog/enabled.txt" 2>/dev/null | tr -d ' ')
[ "$ENABLED_BEFORE" = "$ENABLED_AFTER" ] && [ -f "$DATA/catalog/blocklists.index.tsv" ] && ok "J14 PANIC no borra catalogo/fuentes/config" || bad "J14 PANIC borro datos"
cli enable >/dev/null 2>&1  # revertir el disable del panic

# ---------------------------------------------------------------------------
# J15 residuales — DETERMINISTA, race-safe y sin tocar procesos ajenos.
# Criterios, ambos acotados exclusivamente a ESTE test:
#   (a) los PIDs hijos que el motor registro en el lock (pid:starttime), con
#       ESPERA ACOTADA (<=2 s, polling 100 ms) a que desaparezcan. Un PID cuenta
#       como residual REAL solo si sigue vivo, con el MISMO starttime (no fue
#       reutilizado) y en estado activo (no zombie) al agotar la espera.
#   (b) cualquier proceso cuya cmdline contenga el TEST_ROOT unico ($TR): no debe
#       quedar ninguno (drivers/subshells del modulo bajo $TR).
# Los PIDs de fondo (BGP/BGP2/BGT) ya fueron 'wait'eados.
STRAY=""
_iter=0
while :; do
  STRAY=""
  # (a) PIDs hijos concretos registrados por el motor
  for _e in $KIDS; do
    _p=${_e%%:*}; _s0=${_e#*:}
    [ -n "$_p" ] || continue
    [ -d "/proc/$_p" ] || continue                    # desaparecio -> OK
    _s1=$(pid_starttime "$_p")
    [ "$_s1" != "$_s0" ] && continue                  # starttime distinto -> PID reutilizado, no es nuestro
    _stt=$(awk '/^State:/{print $2}' "/proc/$_p/status" 2>/dev/null)
    [ "$_stt" = "Z" ] && continue                     # zombie -> se recolectara, no es residual real
    STRAY="$STRAY $_p"
  done
  [ -z "$STRAY" ] && break
  [ "$_iter" -ge 20 ] && break                         # ~2 s
  _iter=$((_iter+1)); sleep 0.1
done
# registrar estado final de los KIDS para evidencia
for _e in $KIDS; do _p=${_e%%:*}; [ -d "/proc/$_p" ] && reg_row "$_p" "final-alive"; done
# (b) procesos que referencian el TEST_ROOT unico (no pueden ser del host)
for _cf in /proc/[0-9]*/cmdline; do
  _pid=${_cf#/proc/}; _pid=${_pid%/cmdline}
  [ "$_pid" = "$$" ] && continue
  _cl=$(tr '\0' ' ' < "$_cf" 2>/dev/null)
  case "$_cl" in *"$TR"*) STRAY="$STRAY $_pid"; reg_row "$_pid" "final-testroot" ;; esac
done
STRAY=$(echo $STRAY | tr ' ' '\n' | grep -v '^$' | sort -u | tr '\n' ' ')
if [ -n "$STRAY" ]; then for _p in $STRAY; do echo "  [DIAG] stray=$_p state=$(awk '/^State:/{print $2}' /proc/$_p/status 2>/dev/null) start=$(pid_starttime $_p) ppid=$(awk '/^PPid:/{print $2}' /proc/$_p/status 2>/dev/null) cmd=[$(tr '\0' ' ' </proc/$_p/cmdline 2>/dev/null)]" >&2; done; fi
[ -z "$STRAY" ] && ok "J15 sin procesos residuales del test (hijos registrados race-safe + cmdline con TEST_ROOT)" || { bad "J15 residuales: $STRAY"; for p in $STRAY; do kill -9 "$p" 2>/dev/null; done; }

echo ""
echo "Resumen compile+stats: $PASS OK, $FAILN FAIL"
[ "$FAILN" -eq 0 ] && exit 0 || exit 1
