# TEST_RESULTS — DNSCrypt Manager v0.2.0-RC2.2 (Network/Sources Hotfix)

Rama `hotfix/v0.2.0-rc2.2-network-sources` desde RC2 `34df8e4`. Fixtures locales;
sin Internet. Resultados exactos:

## Nuevas / afectadas por el hotfix
- `smoke-test-environment-v030.sh`: **19/19** (detección de Hybrid Mount: KSU Next
  no expuesto → mensaje accionable; KSU Next expuesto → sin advertencia; Magisk/
  APatch → sin advertencia falsa y `hybrid_mount_detected=unknown`; campos
  obligatorios presentes; nunca `rc=127` crudo).
- `smoke-test-catalog.sh`: **41/41** (con las 3 fuentes corregidas; incluye
  separación estado upstream vs runtime y que una fuente `broken` no se descarga).

## Regresión (sin cambios respecto de RC2)
- `run-syntax-checks.sh`: OK
- `smoke-test-cli.sh`: **48/48**
- `build-catalog.py --check`: reproducible (71 fuentes)

## No ejecutado en este hotfix (fuera de alcance)
Benchmarks de escala 500k/1M/2.5M (no se repiten). Las suites security/webui/
compile/scale-100k/i18n/router permanecen verdes en sus ramas respectivas; este
hotfix no toca esos componentes.

## Verificado a mano (evidencia de diseño, pendiente prueba en dispositivo)
- `environment status` clasifica correctamente los 4 managers con sondas TEST_MODE.
- `catalog update rc1_coinblocker` → OMITIDA (broken, no se descarga), conserva la
  última copia válida y registra `download_failed`.

Nota: las pruebas en el Moto Edge 40 Pro (Android 16, KernelSU Next, SELinux
Enforcing, Hybrid Mount) las realiza el usuario; no se afirman como hechas.
