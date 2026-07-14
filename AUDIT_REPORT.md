# AUDIT_REPORT.md — DNSCrypt Manager

**DNSCrypt Manager — Creado por Skaymer AR**
Fecha de esta revisión: 2026-07-14 (Ronda 3).

## Ronda 3 — gestión de procesos endurecida

Una tercera auditoría externa (sobre el ZIP v2) encontró que `tests/smoke-test-cli.sh` podía bloquearse fuera de este entorno durante las pruebas adversariales/start-con-puerto-ocupado, y que el timeout no terminaba limpiamente todos los procesos descendientes.

### Hallazgo 1: el daemon escapa al grupo de procesos del wrapper

`cmd_start` backgroundea el daemon con `( cd ... && exec nohup "$BIN" ... ) &`. Backgroundear con `&` dentro de un shell (incluso no interactivo) crea, por el propio job-control del shell, un **grupo de procesos nuevo** para ese job — **distinto** del grupo que crea un `setsid` externo envolviendo toda la cadena `timeout -> sh -> CLI`. Como consecuencia, un `kill -TERM -- -$PGID` apuntado al grupo del wrapper **nunca alcanza al daemon**: verificado de forma aislada con un script mínimo que reproduce el mismo patrón de backgrounding.

**Corrección**: además de la limpieza defensiva del grupo del wrapper (que sigue sirviendo para el árbol `timeout`/`sh`/CLI en sí), tanto `call_cli()` como el `cleanup()` final de cada suite ahora **releen el pidfile actual** (`$DNSCRYPT_TEST_DATA_DIR/run/dnscrypt-proxy.pid`) y matan **ese PID directo**, sin depender de la señal de grupo para alcanzarlo. `call_cli()` hace esto inmediatamente después de cualquier resultado con `rc=124` (timeout) o `rc>=128` (señal), no solo al final de la suite.

### Hallazgo 2 (más serio): la verificación de "sigue vivo" nunca detectaba nada

El helper `pid_is_alive_as()` comparaba el cmdline contra la cadena `"fake-dnscrypt-proxy"` — el nombre del **archivo fuente** del fixture. Pero el archivo se despliega renombrado a `dnscrypt-proxy` (sin el prefijo `fake-`, igual que el binario real de producción). Como resultado, **la condición nunca coincidía**, y cada chequeo que dependía de ella (`[4]` "sin daemon huérfano", `[15]` "barrido final", "ningún proceso propio sigue vivo") reportaba **"OK" incondicionalmente**, sin verificar nada de verdad. Esto explica por qué la ronda anterior mostró "0 FAIL" pese al problema real reportado externamente: el chequeo que debía detectarlo estaba roto, no el mecanismo de limpieza en sí (que además también tenía el Hallazgo 1).

**Corrección**: la cadena de búsqueda se corrigió a `"dnscrypt-proxy"` en ambos scripts. Con la verificación ya funcional, se re-probó todo el ciclo de limpieza de punta a punta (ver resultados abajo) para confirmar que, con AMBOS hallazgos corregidos, el aislamiento es real y no un artefacto de un chequeo que nunca fallaba.

### Watchdog global y no re-invocar la CLI si está colgada

Se agregó un watchdog en segundo plano por suite (280s en `smoke-test-cli.sh`, 120s en `smoke-test-webui.sh`) que, si se excede, manda `SIGTERM` (y luego `SIGKILL`) directo al proceso principal — **nunca** vuelve a invocar la CLI (que podría estar colgada) durante la limpieza de emergencia.

### Resultados de esta ronda (verificados EXTERNAMENTE con `ps`/`ss`/`/proc`, no solo autorreporte)

| Suite | Corrida | Exit | Resultado | Procesos (externo) | Sockets (externo) | TEST_ROOT (externo) |
|---|---|---|---|---|---|---|
| `smoke-test-cli.sh` | 1 | 0 | 48 OK, 0 FAIL, 0 TIMEOUT (41s) | ninguno | ninguno | limpiado |
| `smoke-test-cli.sh` | 2 | 0 | 48 OK, 0 FAIL, 0 TIMEOUT (38s) | ninguno | ninguno | limpiado |
| `smoke-test-cli.sh` | 3 | 0 | 48 OK, 0 FAIL, 0 TIMEOUT (41s) | ninguno | ninguno | limpiado |
| `smoke-test-webui.sh` | 1 | 0 | 23 OK, 0 FAIL | ninguno | ninguno | limpiado |
| `smoke-test-webui.sh` | 2 | 0 | 23 OK, 0 FAIL | ninguno | ninguno | limpiado |
| `smoke-test-webui.sh` | 3 | 0 | 23 OK, 0 FAIL | ninguno | ninguno | limpiado |
| `run-syntax-checks.sh` | 1 | 0 | todos los chequeos pasaron | — | — | — |

Cada verificación "externa" se hizo con `ps -eo pid,cmd`, `ss -tulnp` y `ls -d $TEST_ROOT` ejecutados como comandos **separados**, después de que la suite ya había terminado y reportado su propio resultado — nunca confiando únicamente en el exit code o el resumen impreso por el script mismo.

---



## 1. Hallazgos de la auditoría externa y su corrección

| # | Hallazgo | Corrección |
|---|---|---|
| 1 | `pgrep -f` / `pkill` reales en `system/bin/dnscrypt-manager` (`cmd_stop`) y `uninstall.sh` | `cmd_stop` mata **únicamente** el PID validado del pidfile (sin fallback por patrón). El fallback de `uninstall.sh` (solo si la CLI no está disponible) ahora lee el pidfile directo y compara `/proc/PID/exe` contra la ruta EXACTA del binario persistente — comparación estricta de string, nunca `pgrep`/`pkill`/`killall`. |
| 2 | `cmd_start` declaraba éxito solo porque el PID seguía vivo | Ahora espera, acotado por **tiempo real transcurrido** (no cantidad fija de intentos, ver hallazgo de esta misma ronda más abajo), a que PID+cmdline+socket-por-inode+consulta real respondan TODOS a la vez. Si no, mata solo ese PID, borra el pidfile, loguea, y devuelve error. Función compartida `probe_listener_query()` extraída y reutilizada también por `test-dns`. |
| 3 | Aislamiento de rutas insuficiente | `DNSCRYPT_TEST_ROOT` obligatorio. Validación en 3 capas: rechazo de `..` crudo, canonicalización real (`readlink -f`), y verificación de que DATA_DIR/MODDIR sean descendientes reales de TEST_ROOT (no solo prefijo de string). El caso `DNSCRYPT_TEST_DATA_DIR=/tmp/../data/adb/test` se rechaza explícitamente (rc=90), verificado como test automatizado. |
| 4 | Sin timeout individual por llamada | `call_cli()` envuelve cada invocación con `timeout N` y clasifica el resultado sin ambigüedad (ver sección 2). |
| 5 | PATH global modificado sin capturar rutas absolutas antes | `NODE_BIN`/`PYTHON_BIN`/`SH_BIN` se capturan con `command -v` ANTES de cualquier manipulación de `PATH`, y se usan en todas las invocaciones subsiguientes. |
| 6 | Archivos globales en `/tmp` (`/tmp/dcm-out`, `/tmp/zip-build.log`) | Todo output de cada corrida vive dentro de su propio `$TEST_ROOT/scratch`. `build-module.sh` usa su propio `$STAGE` de `mktemp -d` para el log del zip. |
| 7 | WebUI: esperas no explícitas, cierre sin garantizar intervalos/callbacks terminados | El harness ahora consulta `status --json` DIRECTAMENTE (fuera del DOM) y espera la condición combinada `running=true && listening=true && pid entero>0`. Al cerrar, se cancelan los intervalos Y se espera activamente (`pendingCalls===0`) a que terminen todas las llamadas `ksu.exec` en vuelo antes de `process.exit()`. |
| 8 | `\s` (extensión GNU/PCRE) en un `sed` de producción | Reemplazado por `[[:space:]]` (POSIX). Auditado el resto del código: sin más ocurrencias de `\s`/`\d`/`\w`/`grep -P`/`sed -r`/`sed -E` en scripts de producción. |
| 9 | `fetch-binary` sin validación robusta ni protección contra path traversal | Nueva función compartida `scripts/validate-binary.sh` (ELF64 + EM_AARCH64 + firma estática + tamaño razonable), usada por **ambos** `cmd_fetch_binary` y `tools/inject-binary.sh`. `safe_extract_archive()` lista las entradas del zip/tar ANTES de extraer y rechaza cualquier ruta absoluta o con `../` — verificado con un zip malicioso real conteniendo `../../../tmp/pwned.txt`. |
| 10 | URLs placeholder (`CAMBIAME/dnscrypt-manager`) | `updateJson=` eliminado de `module.prop`; `update.json` eliminado del árbol (no hay repo real todavía); ningún documento afirma actualizaciones automáticas disponibles. |
| 11 | Lenguaje sobreconfiado ("congelada y auditada", "38/0 determinista") | Reformulado en `README.md`. Este informe usa lenguaje que distingue explícitamente "observado en este entorno" de "garantizado en cualquier entorno". |
| 12 | Reproducibilidad no verificada desde el ZIP extraído | Sección 4: las 3 suites, 3 veces cada una, corridas **desde una copia recién extraída** del ZIP fuente, no desde el árbol de trabajo original. |
| 13 | Faltaban pruebas específicas | Agregadas: rechazo de ruta con `..`, ausencia real de `pgrep`/`pkill`/`killall` (invocación, no mención en comentarios), `start` no exitoso antes del listener (con el puerto ya ocupado), timeout de un comando colgado, detección de herramienta ausente como arnés roto, dos llamadas concurrentes a `status --json`, cierre de WebUI sin callbacks pendientes. |

---

## 2. `classify_rc()` — clasificación exacta de códigos de salida

```
0        ejecucion correcta
1..123   fallo funcional
124      TIMEOUT -> fallo obligatorio (no aborta el resto de la suite)
126      NO EJECUTABLE -> arnes roto, ABORTA TODA la suite
127      COMANDO AUSENTE -> arnes roto, ABORTA TODA la suite
128+N    señal N
```

`call_cli()` implementa esto envolviendo cada invocación con `timeout "$CLI_TIMEOUT"`. Ante 126/127, envía `SIGTERM` al **PID principal del script** (capturado en `$MAIN_PID` antes de cualquier subshell) para garantizar el aborto incluso si la llamada ocurrió dentro de un `$(...)` — un `exit` ahí solo terminaría el subshell, no la suite completa.

### Hallazgo real durante esta ronda: carrera entre el timeout externo e interno

El primer valor elegido para `CLI_TIMEOUT` (15s) competía con el propio timeout interno de `cmd_start` (también ~15s), y en el caso de fallo (puerto bloqueado), cada intento interno de `probe_listener_query` podía tardar varios segundos adicionales por el timeout del socket de la consulta de prueba — el tiempo real transcurrido internamente podía superar los 15s nominales. El wrapper externo entonces mataba el proceso **antes** de que su propia limpieza interna (matar PID, borrar pidfile) llegara a correr, dejando un pidfile huérfano. Corregido en dos frentes: (a) el loop interno de `cmd_start` ahora se acota por tiempo real de reloj (`date +%s`), no por cantidad fija de intentos; (b) `CLI_TIMEOUT` se subió a 30s, con margen cómodo sobre el peor caso interno (~15s + una iteración en curso).

---

## 3. Aislamiento verificado

- **Cero `mount`/`mount --bind`** en toda la infraestructura de pruebas (ver incidente de la ronda anterior, ya documentado y resuelto: se eliminó por completo el uso de `mount`).
- **Cero `pgrep`/`pkill`/`killall`** en código de producción, verificado automáticamente como test (búsqueda de invocación real, no de menciones en comentarios/documentación — el primer intento de este chequeo tuvo un falso positivo exacto por esta razón, corregido).
- **`/data/adb` y `/system` nunca tocados**: confirmado explícitamente al final de cada corrida de las 3 suites, en las 3 repeticiones, tanto desde el árbol de trabajo como desde el ZIP extraído.
- **Symlinks no sobreviven `zip`/`unzip` en este entorno**: se detectó que el symlink `tests/fixtures/fake-firewall-bin/ip6tables -> iptables` se convertía en un archivo regular (copia del contenido) tras extraer el ZIP, en vez de preservarse como symlink. Funcionalmente no cambia nada (el fake ya distingue su comportamiento por `$(basename "$0")`), pero para eliminar esta fragilidad se reemplazó el symlink por un archivo real idéntico en el árbol fuente.

---

## 4. Pruebas ejecutadas — resultado exacto (desde el ZIP recién extraído)

Cada suite se corrió **3 veces consecutivas**, desde una copia extraída en `/tmp/extracted-v2` (no desde `/home/claude/DNSCrypt-Manager`), inmediatamente después de reempaquetar con el fix del symlink.

### 4.1 `tests/run-syntax-checks.sh`

| Corrida | Exit | Duración |
|---|---|---|
| 1 | 0 | 0s |
| 2 | 0 | 1s |
| 3 | 0 | 0s |

### 4.2 `tests/smoke-test-cli.sh`

| Corrida | Exit | OK | FAIL | TIMEOUT | Duración | Procesos residuales | `/data/adb` | TEST_ROOT residual |
|---|---|---|---|---|---|---|---|---|
| 1 | 0 | 45 | 0 | 0 | 34s | ninguno | intacto | ninguno |
| 2 | 0 | 45 | 0 | 0 | 34s | ninguno | intacto | ninguno |
| 3 | 0 | 45 | 0 | 0 | 34s | ninguno | intacto | ninguno |

Incluye las pruebas nuevas del item 13: `[14a]` ruta con `..` rechazada (rc=90), `[14b]` ausencia real de pgrep/pkill/killall, `[4]` start con puerto ocupado no declara éxito falso y no deja pidfile huérfano, `[14c]` timeout de comando colgado clasificado como rc=124 sin colgar la suite, `[14d]` verificación de detección de herramienta ausente, `[14e]` dos `status --json` concurrentes devuelven JSON válido en ambos.

### 4.3 `tests/smoke-test-webui.sh`

| Corrida | Exit | OK | FAIL | Duración | Procesos residuales | `/data/adb` | TEST_ROOT residual |
|---|---|---|---|---|---|---|---|
| 1 | 0 | 23 | 0 | 8s | ninguno | intacto | ninguno |
| 2 | 0 | 23 | 0 | 8s | ninguno | intacto | ninguno |
| 3 | 0 | 23 | 0 | 8s | ninguno | intacto | ninguno |

Incluye la espera combinada explícita (`running=true && listening=true && pid entero>0`, consultado directo vía `status --json`, no solo texto del DOM) y la verificación de cierre limpio (`pendingCalls===0` antes de `process.exit()`).

---

## 5. Limitaciones conocidas (vigentes de la ronda anterior)

- Sin `iptables`/`ip6tables`/`nft` reales instalados: se verifica secuencia/sintaxis contra fakes con estado, no comportamiento real de netfilter. Requiere validación en Android real.
- Sin acceso a red: el binario oficial no está incluido; `BINARY_INFO.md` documenta el procedimiento exacto.
- Sin emulación cross-arquitectura (host x86_64): la verificación por ejecución de `-version` se omite honestamente cuando no es posible, apoyándose en la firma estática + cabecera ELF.
- Sockets IPv6 no soportados en este sandbox específico (irrelevante en Android real).
- WebUI probada contra un stub de DOM hecho a mano, no un navegador real ni el WebView de KernelSU Manager.

## 6. Funciones todavía no implementadas (diferidas, no son bugs)

Editor TOML avanzado, sección "Aplicaciones" por UID, listas de bloqueo personalizadas, gestor visual de backups, cambio asistido de Private DNS. Todo operable hoy por CLI.

## 7. Riesgos que requieren prueba en un Android real

1. Netfilter real (iptables-nft/toybox/busybox según ROM).
2. SELinux Enforcing y `chcon` en la ROM stock de Motorola.
3. Timing real de arranque (`service.sh`/`boot-completed.sh`).
4. Compatibilidad del TOML por defecto con la versión real de `dnscrypt-proxy` que se incorpore.
5. WebView real de KernelSU Manager / KernelSU Next / APatch.
6. Conflictos con otros módulos/apps de red instalados simultáneamente.
7. Los timeouts elegidos (15s de espera de arranque, 30s de wrapper de test) son apropiados para el doble de pruebas; con el binario real pueden necesitar ajuste (p. ej. `cert_refresh_delay` y latencia real de red del proveedor DoH elegido).

---

## Agradecimientos

Esta ronda de correcciones (aislamiento de pruebas, eliminación de `pgrep`/`pkill`, endurecimiento de `cmd_start`/`fetch-binary`, portabilidad) se realizó con asistencia de Claude (Anthropic), sobre la base de una auditoría externa detallada. La responsabilidad y autoría del proyecto son de **Skaymer AR**.
