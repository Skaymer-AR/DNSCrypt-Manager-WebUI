# Resultados de pruebas — DNSCrypt Manager v1.1.0

**Fecha:** 2026-09-23 · **Árbol:** `feat/blocklist-engine` preparado para
v1.1.0 · **Resultado del gate local de empaquetado:** PASS.

Las pruebas usan fixtures locales y mocks cuando corresponde. No requieren
acceder a los upstreams en CI y no sustituyen las pruebas físicas de Android.

| Suite | Checks | Resultado |
|---|---:|---|
| `smoke-test-v1-scope.cjs` | 43 | 43 PASS, ejecutada después del cambio a la versión estable |
| `smoke-test-cli.sh` | 48 | 48 PASS |
| `smoke-test-security.sh` | 61 | 61 PASS |
| `smoke-test-blocklist-engine.sh` | 44 | 44 PASS |
| `smoke-test-webui.sh` | 33 | 33 PASS |
| Pruebas de filtros del catálogo | 12 | 12 PASS |
| Pruebas de UI de fuentes | 18 | 18 PASS |
| `smoke-test-catalog.sh` | 47 | 47 PASS |
| `smoke-test-catalog-bootstrap.sh` | 15 | 15 PASS |
| `smoke-test-catalog-download-all.sh` | 10 | 10 PASS |
| `smoke-test-webui-args.cjs` | 41 | 41 PASS |
| **Total funcional listado** | **372** | **372 PASS, 0 FAIL** |

También pasaron `tests/run-syntax-checks.sh`, `python3
tools/build-catalog.py --check`, el empaquetado del ZIP ARM64, la verificación
de la estructura del ZIP y `git diff --check`.

La prueba de descarga global simula cuatro feeds lentos: verifica concurrencia
de hasta cuatro, normalización de las cuatro cachés, un único rebuild del
manifiesto, ausencia de activación automática y protección contra compilación
concurrente.

## Límites de la evidencia

- Los conteos son de pruebas locales; no implican validación de todos los
  servidores upstream en cada actualización.
- El usuario reporta haber probado RC10 en el Motorola Edge 40 Pro. No se
  registraron duración total, máximo de RAM ni latencia DNS durante la descarga.
- IPv6 no fue validado exhaustivamente.
- El gate de publicación de GitHub volverá a ejecutar las pruebas al publicar.
