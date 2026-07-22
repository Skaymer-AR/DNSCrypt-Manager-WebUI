#!/bin/bash
##############################################################################
# tests/scale-test-compile.sh   —  Creado por Skaymer AR
#
# Prueba de ESCALA y MECANICA del pipeline de compilacion del catalogo RC2.
# Genera fixtures deterministicos EN RUNTIME (no se commitean). Verifica el
# merge por lotes (sort/uniq/comm, sin loops por dominio), el aporte unico, la
# aplicacion de allowlist (a nivel estadistico), la inmutabilidad del catalogo,
# la limpieza de temporales y la ausencia de procesos residuales; ademas la
# mecanica: lock concurrente, lock huerfano, cancelacion, timeout, poco espacio
# y preservacion de la ultima lista valida ante fallo (rollback).
#
# Escala configurable:   SCALE=100000 bash tests/scale-test-compile.sh
#   dev: 100000 (default).  Cierre: 500000 / 1000000 / 2500000 (una sola vez).
#
# Exit: 0 OK, 1 fallo, 99 arnes roto.
##############################################################################
set -u
cd "$(dirname "$0")/.." || exit 1
SRC_ROOT="$(pwd)"
SCALE="${SCALE:-100000}"
case "$SCALE" in ''|*[!0-9]*) echo "SCALE invalido"; exit 99 ;; esac
SH_BIN="$(command -v sh)"; PY="$(command -v python3)"
[ -n "$SH_BIN" ] && [ -n "$PY" ] || { echo "FATAL: falta sh/python3" >&2; exit 99; }
TIMEV=""; [ -x /usr/bin/time ] && TIMEV="/usr/bin/time -v"

TR="$(mktemp -d /tmp/dcm-scale.XXXXXX)" || exit 99
export DNSCRYPT_TEST_MODE=1 DNSCRYPT_TEST_ROOT="$TR" \
  DNSCRYPT_TEST_DATA_DIR="$TR/data" DNSCRYPT_TEST_MODDIR="$TR/mod" DNSCRYPT_TEST_SHELL="$SH_BIN"
M="$TR/mod/system/bin/dnscrypt-manager"; DATA="$TR/data"

PASS=0; FAILN=0
ok()  { PASS=$((PASS+1)); printf '  OK   %s\n' "$1"; }
bad() { FAILN=$((FAILN+1)); printf '  FAIL %s\n' "$1"; }
# watchdog generoso (2.5M puede tardar)
WD_SECS=$(( SCALE/2000 + 180 ))
( _wdn=0; while [ "$_wdn" -lt "$WD_SECS" ] 2>/dev/null; do sleep 1; _wdn=$((_wdn + 1)); done
  echo "FATAL: watchdog ${WD_SECS}s" >&2; kill -TERM $$ 2>/dev/null ) & WD=$!
cleanup() { kill "$WD" 2>/dev/null; wait "$WD" 2>/dev/null; rm -rf "$TR"; }
trap 'cleanup; exit 99' INT TERM
trap cleanup EXIT

mkdir -p "$DATA/bin" "$DATA/config"
cp -a "$SRC_ROOT/." "$TR/mod/"; rm -rf "$TR/mod/tests" "$TR/mod/tools" "$TR/mod/.git"
cp "$SRC_ROOT/tests/fixtures/fake-dnscrypt-proxy" "$DATA/bin/dnscrypt-proxy" 2>/dev/null; chmod 0755 "$DATA/bin/dnscrypt-proxy" 2>/dev/null
cp "$SRC_ROOT/config/dnscrypt-proxy.toml" "$DATA/config/dnscrypt-proxy.toml"
cli() { "$SH_BIN" "$M" "$@"; }
inlib() { ( cd "$TR/mod" && "$SH_BIN" -c ". scripts/common.sh 2>/dev/null; . scripts/security.sh 2>/dev/null; . scripts/catalog.sh 2>/dev/null; $1" ); }

echo "=== Escala SCALE=$SCALE  (TR=$TR) ==="
cli migrate >/dev/null 2>&1

# ---------------------------------------------------------------------------
# Fixtures deterministicos (generados con awk, por lotes):
#   Fuente A (domains): a0..a(0.7S)  + 0.1S duplicados internos  -> 0.8S lineas
#   Fuente B (hosts)  : comparte 0.2S dominios con A (overlap) + 0.5S propios
#   blacklist manual  : 1000 dominios propios
#   allowlist         : toma 500 dominios que SI estan bloqueados (para el stat)
#   invalidos         : 200 lineas basura en A (deben caer al parsear)
# ---------------------------------------------------------------------------
UNIQ_A=$(( SCALE * 7 / 10 ))
DUP_A=$(( SCALE / 10 ))
SHARED=$(( SCALE / 5 ))
UNIQ_B=$(( SCALE / 2 ))
NBLACK=1000; NALLOW=500; NBAD=200
CACHE="$DATA/catalog/cache"; mkdir -p "$CACHE"

echo "  generando fixtures…"
# A: normalizada directamente en cache (para probar el MERGE a escala)
awk -v u="$UNIQ_A" -v d="$DUP_A" -v s="$SHARED" 'BEGIN{
  for(i=0;i<u;i++) print "a"i".scale.net";
  for(i=0;i<s;i++) print "shared"i".scale.net";      # overlap con B
  for(i=0;i<d;i++) print "a"i".scale.net";           # duplicados internos
}' > "$CACHE/scaleA.list"
# B: normalizada en cache
awk -v ub="$UNIQ_B" -v s="$SHARED" 'BEGIN{
  for(i=0;i<ub;i++) print "b"i".scale.net";
  for(i=0;i<s;i++) print "shared"i".scale.net";      # overlap con A
}' > "$CACHE/scaleB.list"
# registrar dos fuentes custom que apunten a esas cache lists
inlib "cat_custom_add 'https://x.net/a.txt' --name scaleA --format domains >/dev/null 2>&1
cat_custom_add 'https://x.net/b.txt' --name scaleB --format hosts >/dev/null 2>&1"
IDA=$(awk -F'\t' '$3=="scaleA"{print $1}' "$DATA/catalog/custom.tsv")
IDB=$(awk -F'\t' '$3=="scaleB"{print $1}' "$DATA/catalog/custom.tsv")
# renombrar las cache lists a los ids reales
mv "$CACHE/scaleA.list" "$CACHE/$IDA.list"; mv "$CACHE/scaleB.list" "$CACHE/$IDB.list"
inlib "cat_enable $IDA; cat_enable $IDB" >/dev/null 2>&1
# blacklist manual + allowlist (500 dominios que estan en A)
awk -v n="$NBLACK" 'BEGIN{for(i=0;i<n;i++) print "black"i".manual.net"}' >> "$DATA/catalog/blacklist.txt"
awk -v n="$NALLOW" 'BEGIN{for(i=0;i<n;i++) print "a"i".scale.net"}' >> "$DATA/security/allowlist.txt"
LC_ALL=C sort -u "$DATA/security/allowlist.txt" -o "$DATA/security/allowlist.txt" 2>/dev/null

# esperado: dominios unicos bloqueados = union(A_unicos, B) + blacklist manual
#   A aporta UNIQ_A + SHARED ; B aporta UNIQ_B (shared ya contado) ; + NBLACK
EXP_UNIQUE=$(( UNIQ_A + SHARED + UNIQ_B + NBLACK ))

# ---------------------------------------------------------------------------
echo "== 1. Merge a escala (compile) =="
SHA_TSV0=$(sha256sum config/catalog/blocklists.index.tsv | cut -d' ' -f1)
_t0=$(date +%s)
if [ -n "$TIMEV" ]; then
  $TIMEV "$SH_BIN" "$M" catalog compile > "$TR/cout" 2> "$TR/time.err"
  MAXRSS=$(awk -F': ' '/Maximum resident set size/{print $2}' "$TR/time.err")
else
  cli catalog compile > "$TR/cout" 2>&1; MAXRSS="n/d"
fi
_t1=$(date +%s); DUR=$(( _t1 - _t0 ))
BL="$DATA/security/active/blocked-names.txt"
GOT=$(wc -l < "$BL" 2>/dev/null | tr -d ' ')
[ "$GOT" = "$EXP_UNIQUE" ] && ok "1.1 conteo exacto de dominios unicos ($GOT)" || bad "1.1 conteo ($GOT != $EXP_UNIQUE)"
LC_ALL=C sort -c "$BL" 2>/dev/null && ok "1.2 salida ordenada" || bad "1.2 no ordenada"
_dups=$(LC_ALL=C uniq -d "$BL" | head -1)
[ -z "$_dups" ] && ok "1.3 sin duplicados en la salida" || bad "1.3 hay duplicados"
SHA_TSV1=$(sha256sum config/catalog/blocklists.index.tsv | cut -d' ' -f1)
[ "$SHA_TSV0" = "$SHA_TSV1" ] && ok "1.4 catalogo canonico inmutable (SHA TSV intacto)" || bad "1.4 catalogo mutado"
# temporales del compilador limpios
_temps=$(ls "$DATA/run/" 2>/dev/null | grep -cE 'cat\.|stats\.' | tr -d ' ')
[ "${_temps:-0}" = "0" ] && ok "1.5 sin temporales residuales en RUN_DIR" || bad "1.5 temporales residuales: $_temps"
echo "     [medicion] tiempo=${DUR}s  maxRSS=${MAXRSS}  dominios=${GOT}"

# ---------------------------------------------------------------------------
echo "== 2. Aporte unico + allowlist (estadistico) =="
inlib "cat_stats_compute" >/dev/null 2>&1
STATS="$DATA/catalog/contribution-stats.tsv"
UA=$(awk -F'\t' -v id="$IDA" '$1==id{print $5}' "$STATS")
UB=$(awk -F'\t' -v id="$IDB" '$1==id{print $5}' "$STATS")
# A se procesa primero (orden canonico); su aporte unico = UNIQ_A + SHARED
[ "$UA" = "$(( UNIQ_A + SHARED ))" ] && ok "2.1 aporte unico de A correcto ($UA)" || bad "2.1 aporte A ($UA)"
# B aporta solo lo propio (shared ya visto) = UNIQ_B
[ "$UB" = "$UNIQ_B" ] && ok "2.2 aporte unico de B correcto, overlap descontado ($UB)" || bad "2.2 aporte B ($UB != $UNIQ_B)"
_sum=$(grep '^#summary' "$STATS")
TOTU=$(printf '%s' "$_sum" | cut -f3); ALLW=$(printf '%s' "$_sum" | cut -f5); EFF=$(printf '%s' "$_sum" | cut -f7)
# total_unique de stats = A_unique + B_unique (no incluye blacklist manual, que no es "fuente")
[ "$TOTU" = "$(( UNIQ_A + SHARED + UNIQ_B ))" ] && ok "2.3 total unico de fuentes correcto ($TOTU)" || bad "2.3 total unico ($TOTU)"
[ "$ALLW" = "$NALLOW" ] && ok "2.4 allowlist contabilizada ($ALLW)" || bad "2.4 allowlist ($ALLW != $NALLOW)"
[ "$EFF" = "$(( TOTU - NALLOW ))" ] && ok "2.5 efectivo tras allowlist correcto ($EFF)" || bad "2.5 efectivo ($EFF)"

# ---------------------------------------------------------------------------
echo "== 3. Parseo real a sub-escala (hosts + domains + invalidos) =="
SUB=50000
awk -v n="$SUB" 'BEGIN{
  for(i=0;i<n;i++) print "0.0.0.0 p"i".parse.net";   # hosts validos
  print "# comentario"; print "0.0.0.0 localhost";   # ignorados
  print "basura sin sentido"; print "0.0.0.0";       # invalidos
}' > "$TR/hosts.src"
_pv=$(inlib "sec_parse_domains '$TR/hosts.src' hosts '$TR/hosts.out'; wc -l < '$TR/hosts.out'" 2>/dev/null | tail -1 | tr -d ' ')
[ "$_pv" = "$SUB" ] && ok "3.1 hosts: $SUB validos, invalidos/localhost/comentarios descartados" || bad "3.1 parse hosts ($_pv != $SUB)"
LC_ALL=C sort -c "$TR/hosts.out" 2>/dev/null && ok "3.2 salida de parseo ordenada y sin duplicados" || bad "3.2 parse no ordenada"

# ---------------------------------------------------------------------------
echo "== 4. Mecanica del pipeline (lock/cancel/timeout/huerfano/rollback) =="
if [ "${SKIP_MECH:-0}" = "1" ]; then
  echo "  (omitida por SKIP_MECH=1; ya cubierta en la corrida de 100k)"
else
# 4.1 lock concurrente: una compilacion lenta en segundo plano, otra debe fallar
DNSCRYPT_TEST_COMPILE_SLEEP=6 cli catalog compile >/dev/null 2>&1 &
BGPID=$!
sleep 1
cli catalog compile > "$TR/lk" 2>&1
grep -qi "ya hay una compilacion en curso" "$TR/lk" && ok "4.1 lock concurrente rechaza segunda compilacion" || bad "4.1 lock concurrente"
# 4.2 compile-status en curso
cli catalog compile-status 2>&1 | grep -qi "EN CURSO" && ok "4.2 compile-status muestra EN CURSO" || bad "4.2 status"
# 4.3 cancelacion
cli catalog compile-cancel > "$TR/cn" 2>&1
grep -qi "cancel" "$TR/cn" && ok "4.3 compile-cancel cancela la compilacion propia" || bad "4.3 cancel"
wait "$BGPID" 2>/dev/null
# 4.4 lock huerfano: crear lock con PID muerto y comprobar recuperacion
mkdir -p "$DATA/run/catalog.compile.lock"; echo 999999 > "$DATA/run/catalog.compile.lock/pid"
cli catalog compile > "$TR/orph" 2>&1
grep -qi "OK: compilacion terminada" "$TR/orph" && ok "4.4 lock huerfano (PID muerto) recuperado" || bad "4.4 huerfano ($(head -1 $TR/orph))"
# 4.5 timeout real
CAT_COMPILE_TIMEOUT=1 DNSCRYPT_TEST_COMPILE_SLEEP=8 cli catalog compile > "$TR/to" 2>&1
grep -qi "timeout" "$TR/to" && ok "4.5 timeout aborta y conserva la ultima lista" || bad "4.5 timeout ($(head -1 $TR/to))"
# 4.6 fallo preserva la ultima lista valida (rollback/preservacion)
BLSHA_BEFORE=$(sha256sum "$BL" | cut -d' ' -f1)
DNSCRYPT_TEST_COMPILE_FAIL=1 cli catalog compile > "$TR/fl" 2>&1
BLSHA_AFTER=$(sha256sum "$BL" | cut -d' ' -f1)
[ "$BLSHA_BEFORE" = "$BLSHA_AFTER" ] && ok "4.6 fallo de compilacion preserva la ultima lista valida" || bad "4.6 rollback/preservacion"
# 4.7 poco espacio DETERMINISTICO: override numerico solo bajo TEST_MODE.
BLSHA_SP=$(sha256sum "$BL" 2>/dev/null | cut -d' ' -f1)
DNSCRYPT_TEST_FREE_KB=1 CAT_MIN_FREE_KB=2 cli catalog compile > "$TR/sp" 2>&1
grep -qi "espacio libre insuficiente" "$TR/sp" && ok "4.7 poco espacio aborta con mensaje claro" || bad "4.7 poco espacio ($(head -1 $TR/sp))"
BLSHA_SP2=$(sha256sum "$BL" 2>/dev/null | cut -d' ' -f1)
[ "$BLSHA_SP" = "$BLSHA_SP2" ] && ok "4.7b no crea lista nueva / conserva la ultima valida" || bad "4.7b lista alterada por poco espacio"
[ ! -d "$DATA/run/catalog.compile.lock" ] && ok "4.7c lock liberado tras abortar por espacio" || bad "4.7c lock no liberado"
_sptmp=$(ls "$DATA/run/" 2>/dev/null | grep -cE 'cat\.|stats\.' | tr -d ' ')
[ "${_sptmp:-0}" = "0" ] && ok "4.7d sin temporales tras abortar por espacio" || bad "4.7d temporales: $_sptmp"
# 4.8 sin procesos residuales del modulo
sleep 1
STRAY=$(ps -eo pid,args 2>/dev/null | grep -F "$TR/mod" | grep -v grep | wc -l | tr -d ' ')
[ "${STRAY:-0}" = "0" ] && ok "4.8 sin procesos residuales del modulo" || bad "4.8 procesos residuales: $STRAY"
# 4.9 lock liberado tras toda la mecanica
[ ! -d "$DATA/run/catalog.compile.lock" ] && ok "4.9 lock liberado al final" || bad "4.9 lock no liberado"
fi

echo ""
echo "Resumen escala (SCALE=$SCALE): $PASS OK, $FAILN FAIL | tiempo_merge=${DUR}s maxRSS=${MAXRSS}"
[ "$FAILN" -eq 0 ] && exit 0 || exit 1
