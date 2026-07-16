# Resultados de pruebas de escala — DNSCrypt Manager v0.2.0-RC2

Fixtures deterministicos generados EN RUNTIME por los tests; **no** se commitean.
El merge usa `cat_append_active` + `sort -u` por lotes (sin loops por dominio).

## Alcance real de cada prueba (importante)

- **100 000 — suite funcional COMPLETA** (`tests/scale-test-compile.sh`, 21/21):
  merge + conteo exacto + orden + sin duplicados + catalogo inmutable + limpieza
  de temporales; aporte unico por fuente con overlap descontado y allowlist
  contabilizada; parseo real de 50k hosts; y **mecanica end-to-end del pipeline**:
  lock concurrente, `compile-status`, `compile-cancel`, recuperacion de lock
  huerfano (PID muerto), timeout real, fallo preserva la ultima lista valida,
  poco espacio, sin procesos residuales, lock liberado.
  El pipeline tambien se cubre en `tests/smoke-test-compile.sh` (19/19), que ademas
  valida lock huerfano con **PID ajeno vivo** y que **PANIC libera el lock**.

- **500 000 / 1 000 000 / 2 500 000 — benchmark MINIMO del merge por lotes**,
  NO el pipeline completo. Mide unicamente `cat_append_active` + `sort -u`:
  conteo exacto, salida ordenada, sin duplicados, catalogo canonico inmutable y
  ausencia de temporales. **No** se ejecutaron a esta escala la cancelacion, el
  timeout, el rollback, la recarga de dnscrypt-proxy ni el lock concurrente; esos
  comportamientos se validan a 100k y a nivel funcional, no a 2.5M.

## Benchmark de merge (medicion en **Linux de escritorio**, `/usr/bin/time -v`)

| Escala nominal (S) | Dominios en la salida final | Exacto | Ordenado | Sin duplicados | Catalogo inmutable | Temporales | Wall clock | maxRSS |
|-------------------:|----------------------------:|:------:|:--------:|:--------------:|:------------------:|:----------:|:----------:|:------:|
| 500 000            | 700 002                     | si     | si       | si             | si                 | 0          | 0.50 s     | 52 MB  |
| 1 000 000          | 1 400 002                   | si     | si       | si             | si                 | 0          | 0.75 s     | 103 MB |
| 2 500 000          | 3 500 002                   | si     | si       | si             | si                 | 0          | 2.28 s     | 255 MB |

### Por que la salida final supera la escala nominal
La "escala nominal" S es un parametro del fixture, no la cantidad final. El fixture
**combina dos fuentes con overlap controlado + duplicados internos + blacklist
manual**:
- Fuente A: 0.7·S dominios unicos + 0.2·S compartidos con B (+0.1·S duplicados
  internos que se descartan al deduplicar).
- Fuente B: 0.5·S propios + 0.2·S compartidos (el overlap se cuenta una sola vez).
- + 2 dominios de blacklist manual.

Total unico esperado = 0.7·S + 0.2·S + 0.5·S + 2 = **1.4·S + 2**.
Por eso S=2 500 000 produce 3 500 002, no "2.5M". No debe presentarse 2.5M como
cantidad final.

## Advertencias

- **Memoria:** el pico fue **255 MB** para 3.5M de dominios en Linux (dominado por
  `sort`, que ademas usa temporales en disco). En Android, con menos RAM y
  almacenamiento mas lento, el consumo y los tiempos seran **mayores**. Por eso los
  **catalogos multimillonarios deben ser una opcion consciente del usuario, no un
  valor predeterminado**; el modulo se entrega con las fuentes externas apagadas.
- **No se puede inferir el rendimiento en Android** a partir de estas cifras de
  Linux. La validacion real en el dispositivo forma parte del plan posterior
  (`docs/ANDROID_TEST_PLAN_v0.2.0.md`).
