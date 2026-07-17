# DNSCrypt Manager v0.3.0-RC1 — Arquitectura

Base: **v0.2.0-RC2** (schema 2). Autor: Skaymer AR. Mismo module id
`dnscrypt_manager`. Esta versión AMPLÍA RC2; no reescribe lo estable.

## 1. Componentes
- **CLI** (`system/bin/dnscrypt-manager`): autoridad. Toda entrada se revalida
  aquí aunque venga de la WebUI. Allowlist de subcomandos, `shQuote`, sin `eval`.
- **Librerías shell** (`scripts/`): `common.sh`, `security.sh` (redirect,
  fail-closed, allowlist/blacklist, excepciones, perfiles, fugas, eventos),
  `catalog.sh` (catálogo, compilación por lotes, aporte único, conflictos,
  service-controls, lock/cancel/status/timeout, PANIC). **Nuevas**:
  `transport.sh` (DNSCrypt directo / Anonymized / ODoH), `captive.sh` (portal
  cautivo), `bypass.sh` (detección ampliada), `monitor.sh` (actividad
  sospechosa), `apppolicy.sh` (políticas por UID).
- **WebUI** (`webroot/`): SPA liviana con router hash y navegación inferior.
- **Binario**: `dnscrypt-proxy` ARM64 oficial (SHA `940b650…`). Confirmado por
  strings que soporta **DNSCrypt, Anonymized DNSCrypt y ODoH**. Nunca se
  descargan binarios en runtime.

## 2. Almacenamiento persistente (DATA_DIR = /data/adb/dnscrypt-manager)
- `config/` config base y perfiles. `catalog/` índice + cache + custom +
  blacklist + `source-status.tsv` (runtime) + `service-state.tsv` +
  `contribution-stats.tsv`. `security/` allowlist/blacklist/excepciones/eventos.
- **Nuevo** `transport/`: `anonymized.json`, `odoh.json`, `last-known-good/`
  (respaldos de TOML validados), `transport-state.tsv`.
- **Nuevo** `captive/state.tsv`, `monitor/` (alertas + retención + rotación),
  `apppolicy/policies.tsv`.
- Archivos de estado privados 0600; directorios 0700. Nunca se toca el catálogo
  generado (inmutable) en runtime; los resultados runtime van a archivos aparte.

## 3. Estado runtime vs configuración (invariante de RC2)
El catálogo canónico (`blocklists.json` + `.index.tsv`) y los controles
(`service-controls/*.json`) son **inmutables** en el dispositivo. Los resultados
locales (verified, latencias, last-known-good, alertas) viven en archivos
separados. `verified` de una fuente solo tras descarga+validación runtime, nunca
desde CI.

## 4. Seguridad (invariantes)
- **Fix de fuga de procesos del timeout es invariante**: `_cat_kill_tree` congela
  el root (SIGSTOP) antes de recolectar el subárbol y se llama ANTES del kill de
  grupo (que queda como respaldo). No reintroducir el orden viejo que reparentaba
  workers a init. Todo motor pesado nuevo (pruebas de transporte, etc.) usa el
  mismo patrón lock+child+trap+kill_tree.
- Prohibido: `eval`, shell arbitrario, concatenar parámetros externos en `sh -c`,
  sourcear archivos del usuario, `chmod 777`, `setenforce 0`, `pkill`, `killall`,
  matar por nombre, flush global de iptables/nftables, borrar reglas ajenas.
- Locks atómicos (`mkdir`), PID validado por `/proc/cmdline`, timeouts, límites de
  tamaño, rotación, reemplazo atómico, rollback/last-known-good, PANIC limpia solo
  lo propio.

## 5. Rutas de migración (schema 2 → 3)
Idempotente, con backup previo y rollback. Instala directo encima de RC2 (mismo
id). Conserva: config, listas descargadas válidas, allowlist, blacklist,
excepciones, perfiles, historial (según retención), custom sources, control
YouTube. Crea los nuevos directorios/estado con **defaults seguros OFF**.

## 6. Compatibilidad Android
KernelSU / KernelSU Next / APatch / Magisk; Android 13–16; ARM64; SELinux
Enforcing. Las funciones que dependen del kernel (políticas por app, detección de
puerto 53/853) primero **detectan capacidades reales**; si no hay soporte,
muestran "No compatible en este dispositivo" y no aplican reglas aproximadas.

## 7. Funciones experimentales (todas OFF por defecto)
Anonymized DNSCrypt, ODoH, portal cautivo automático, monitor (audit-only por
defecto), políticas por app, protección estricta de bypass, nuevos service
controls. Cada una: estado propio, rollback, PANIC, eventos.

## 8. Límites del filtrado DNS (documentados, no falseados)
DNSCrypt Manager es un **gestor y filtro DNS**. NO hace: MITM, CA propia,
inspección HTTPS, filtros cosméticos, inyección JS, bloqueo por contenido visual,
bloqueo por palabras dentro de HTTPS, bloqueo total del 443, VPN. Consecuencias:
- YouTube Ads es **best-effort** (no se bloquean todos).
- No toda regla ABP es convertible (solo reglas de dominio inequívocas; cobertura
  parcial documentada).
- La atribución por aplicación es limitada: separar (A) política de red por UID,
  (B) atribución de consultas DNS, (C) filtrado de dominios; solo se implementa lo
  que el kernel permita verificar.
- ODoH depende del binario; el monitor es heurístico ("no malware confirmado").
- Resultados en Linux no equivalen a Android.
