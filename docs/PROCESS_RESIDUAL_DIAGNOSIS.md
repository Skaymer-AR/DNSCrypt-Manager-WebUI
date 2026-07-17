# Diagnóstico: proceso residual tras timeout de compilación (RC2)

## Síntoma
`tests/smoke-test-compile.sh` (J15), tras endurecer la verificación de residuos
para que fuera determinista, empezó a reportar **un PID vivo** tras ejecutar la
mecánica de cancelación/timeout/PANIC. Ejemplo observado: `J15 residuales: 24998`.

## PID observado
`24998` correspondía a una corrida previa (ya no existía al inspeccionarlo: los
PIDs no persisten entre ejecuciones). La reproducción instrumentada volvió a
producir el residual de forma consistente, permitiendo identificarlo.

## Diagnóstico
**Fuga real del producto (CASO B)**, no un falso positivo del test.

Se instrumentaron los tres caminos que lanzan un hijo pesado (con `sleep` como
stub en TEST_MODE), capturando el `child` PID desde el lock, su subárbol, el
STARTTIME (campo 22 de `/proc/PID/stat`) y esperando de forma acotada:

- **cancel** (`compile-cancel`): child y worker → **muertos**. OK.
- **PANIC** (`panic` → `compile-cancel`): child y worker → **muertos**. OK.
- **timeout** (watchdog): child **muerto**, pero el **worker (`sleep`) seguía vivo**
  con el **mismo starttime** (proceso original, no un PID reutilizado). FUGA.

## Evidencia
```
[timeout] child=10315 desc=10320
  muerto 10315
  VIVO 10320 cmd=[sleep 6 ] start=70815
```
El worker `10320` sobrevivía al watchdog con starttime intacto → fuga real
específica del camino de timeout.

## Causa
En `cat_compile`, el watchdog (y `cat_compile_cancel`) ejecutaban el **kill del
grupo de procesos antes** de recolectar el subárbol:

```
kill -TERM "-$_child"; _cat_kill_tree "$_child" TERM
```

Cuando `set -m` convertía al hijo en líder de su grupo, el `kill -TERM "-$_child"`
mataba primero al **padre** (el subshell), que **reparentaba el worker a init**.
El `_cat_kill_tree` posterior recorría `/proc` **desde el child ya muerto** y por
lo tanto **no encontraba** al worker reparentado → quedaba vivo.
(En `cancel`/`PANIC` la ventana temporal no disparaba la reparentación previa, por
eso allí no se observaba la fuga; pero el orden era igual de frágil.)

## Corrección (producto)
`scripts/catalog.sh`:
1. **`_cat_kill_tree` congela el root con `SIGSTOP` antes de recolectar** su
   subárbol: así el root no puede salir (y reparentar) ni forkear mientras se
   recorre `/proc`. Tras señalar por PID a todo lo recolectado, hace `SIGCONT`
   del root para que procese la señal pendiente y muera. Como se señala **por
   PID**, un proceso reparentado *después* de la recolección igual se alcanza.
2. **watchdog y cancel llaman a `_cat_kill_tree` (recolectar-y-señalar) ANTES**
   del kill de grupo; el kill de grupo queda como respaldo rápido.

Sin `pkill`, sin `killall`, sin matar por patrón de nombre; solo se toca el
subárbol registrado por el módulo. Verificado: cancel, PANIC y timeout no dejan
ni el hijo ni el worker vivos.

## Corrección (test, race-safe)
`tests/smoke-test-compile.sh` (J15) ya no busca por nombre genérico `sleep 6/8`.
Registra el `child` del lock + su subárbol **antes** de cada teardown con su
STARTTIME como identidad (y deja `process-registry.tsv`), luego hace **polling
acotado (~2 s, pasos de 100 ms)** y marca residual **solo** si el PID sigue vivo
**y** su starttime es el mismo (descarta PID reutilizado) **y** no es un zombie
transitorio; más un escaneo global restringido a procesos cuya cmdline contenga
el **TEST_ROOT único**. Esta verificación fue la que **destapó** la fuga real.

## Pruebas
- `smoke-test-compile.sh`: **19/19**, tres corridas seguidas.
- `scale-test-compile.sh` (SCALE=100000): **24/24**, dos corridas seguidas
  (incluye cancelación/timeout/huérfano/poco espacio deterministas).
- `run-syntax-checks.sh`: OK.

## Limitaciones
- El `SIGSTOP`/`SIGCONT` y el recorrido de `/proc` son best-effort: dependen de
  `/proc` montado y de permisos (en el dispositivo, como root, están disponibles).
- La validación se hizo en **Linux de escritorio**. En Android el planificador y
  el modelo de grupos de proceso de toolbox/busybox pueden diferir; forma parte
  del plan de pruebas en dispositivo (`docs/ANDROID_TEST_PLAN_v0.2.0.md`).
