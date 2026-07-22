# TEST_RESULTS — DNSCrypt Manager v1.0.0

Ejecución real sobre el árbol exacto preparado para la publicación estable. Fixtures
locales, **sin Internet**. No se repitieron los benchmarks de 500k/1M/2.5M dominios.

**Total: 30 suites funcionales · 533 checks · 0 FAIL.** Además,
`tests/run-syntax-checks.sh` completó todos los chequeos de shell, JavaScript, TOML,
HTML, CSS, referencias cruzadas y contenido instalable sin errores.

## Alcance de v1.0.0
| Suite | Resultado |
|---|---|
| smoke-test-v1-scope.cjs | **43 OK, 0 FAIL** |

Cubre: ausencia de la advertencia BindHosts en HTML/i18n/customize.sh/CLI y presencia
de una nota de convivencia; importador BindHosts conservado; ausencia de tarjetas,
botones, entradas y textos públicos de Anonymized DNSCrypt/ODoH; ausencia de la tarjeta
heredada y vacía `service`; sección real **Privacidad por servicio** conservada;
`version=v1.0.0` y `versionCode=10000`; sin leyendas de versión en pruebas.

El comportamiento de Eventos se verificó en sandbox `vm`: cero consultas al cargar la
WebUI, panel cerrado inicialmente, una sola consulta al abrir, 20 filas iniciales de 57,
botón **Cargar más**, desmontaje del DOM al cerrar, cero consultas con el panel cerrado
y descarte de respuestas tardías después de cerrarlo.

## WebUI
| Suite | Resultado |
|---|---|
| smoke-test-webui.sh | **23 OK, 0 FAIL** |
| smoke-test-webui-args.cjs | **37 OK, 0 FAIL** |
| smoke-test-webui-lazy-v030.cjs | **23 OK, 0 FAIL** |
| smoke-test-webui-controls-v030.cjs | **18 OK, 0 FAIL** |
| smoke-test-webui-v030.cjs | **15 OK, 0 FAIL** |
| smoke-test-source-ui-v030.cjs | **5 OK, 0 FAIL** |
| smoke-test-cli-resolver-v030.cjs | **6 OK, 0 FAIL** |
| smoke-test-i18n.sh | **5 OK, 0 FAIL** |

## Controles, migración y catálogo
| Suite | Resultado |
|---|---|
| smoke-test-service-controls.sh | **10 OK, 0 FAIL** |
| smoke-test-service-enforcement.sh | **8 OK, 0 FAIL** |
| smoke-test-app-policy.sh | **12 OK, 0 FAIL** |
| smoke-test-migration-v3.sh | **12 OK, 0 FAIL** |
| smoke-test-catalog-audit.sh | **6 OK, 0 FAIL** |
| smoke-test-catalog.sh | **42 OK, 0 FAIL** |

`service-enforcement` verifica enforcement real en la lista compilada: los dominios de
un control activo entran a `blocked-names.txt`, se retiran al apagarlo, un modo vencido
no bloquea y la allowlist neutraliza mediante `allowed-names.txt`. `migration-v3`
confirma que `DATA_DIR/transport` ya no se inicializa en v1.0.0.

El check adicional del catálogo valida el watchdog portable y su limpieza en shells
POSIX, evitando procesos residuales al finalizar tests y operaciones de catálogo.

## Fuentes, entorno y núcleo
| Suite | Resultado |
|---|---|
| smoke-test-source-fetch.sh | **17 OK, 0 FAIL** |
| smoke-test-source-doctor.sh | **26 OK, 0 FAIL** |
| smoke-test-source-bootstrap.sh | **10 OK, 0 FAIL** |
| smoke-test-source-errors-v030.sh | **6 OK, 0 FAIL** |
| smoke-test-dns-audit-v030.sh | **6 OK, 0 FAIL** |
| smoke-test-environment-v030.sh | **19 OK, 0 FAIL** |
| smoke-test-security.sh | **61 OK, 0 FAIL** |
| smoke-test-cli.sh | **48 OK, 0 FAIL** |
| smoke-test-compile.sh | **19 OK, 0 FAIL** |

## Componentes internos no expuestos por v1.0.0
Se ejecutan para prevenir regresiones, pero no se anuncian ni se exponen en la WebUI
estable:

| Suite | Resultado |
|---|---|
| smoke-test-transport.sh | **10 OK, 0 FAIL** |
| smoke-test-anonymized.sh | **11 OK, 0 FAIL** |
| smoke-test-odoh.sh | **9 OK, 0 FAIL** |
| smoke-test-captive.sh | **8 OK, 0 FAIL** |
| smoke-test-bypass.sh | **9 OK, 0 FAIL** |
| smoke-test-monitor.sh | **9 OK, 0 FAIL** |

## Qué no prueban estos números
La suite automatizada corre en **Linux/x86**, con binario de prueba y hooks `TEST_MODE`.
Verifica lógica, validación de entradas, máquinas de estado, seguridad DOM, catálogo,
limpieza de procesos y —para `service-control`— el merge real de dominios. No puede
ejecutar el binario ARM64 como si fuera Android ni sustituye las pruebas físicas.

La evidencia aportada por el usuario en un Motorola Edge 40 Pro real está documentada
en `ANDROID_USER_VALIDATION_v1.0.0.md`. Rollback físico forzado, consumo prolongado de
RAM y consumo prolongado de batería siguen declarados como pendientes.
