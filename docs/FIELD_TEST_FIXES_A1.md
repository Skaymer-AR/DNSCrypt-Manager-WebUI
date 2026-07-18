# FIELD_TEST_FIXES — v0.3.0-RC1 CHECKPOINT A1

Correcciones incorporadas a `feature/v0.3.0-rc1` a partir de incidentes reales en
el Moto Edge 40 Pro (Android 16, KernelSU Next, SELinux Enforcing, Hybrid Mount).
No se implementan aun transport/Anonymized/ODoH/captive/monitor/app-policy/schema-3.

## 1. CLI "inaccessible or not found" (KernelSU Next / Hybrid Mount)
- **Causa:** Hybrid Mount apagado → el módulo no se expone a la WebUI. No era ZIP corrupto.
- **Fix:** resolvedor central de CLI en `api.js` (una sola implementación; se
  eliminaron las constantes fijas duplicadas de `api.js` y `app.js`). 3 rutas de
  allowlist en orden (`/system/bin`, `/data/adb/modules/...`,
  `/data/adb/modules_update/...`), probe con cadena fija (sin datos externos, sin
  eval, sin find global), solo acepta rutas de la allowlist. Si no resuelve →
  mensaje claro (no `rc=127`) indicando activar Hybrid Mount y reiniciar.
- **Comando:** `dnscrypt-manager environment status` (evidencia; `unknown` cuando
  no es verificable; mensaje accionable solo en KSU Next no expuesto; sin falsos en
  Magisk/APatch). Tarjeta de entorno en la WebUI.

## 2. Fuentes que fallaban al descargar
- **cryptomining** (curl 22 / HTTP 404): ZeroDot1 CoinBlockerLists caído →
  reemplazado por **NoCoin** en ambos flujos: catálogo (`nocoin_hosts`, supersedes)
  y fuente antigua (`config/blocklist-sources/cryptomining.src`, hosts). CoinBlocker
  queda `broken`, no se descarga, no se reintenta el 404, se conserva la última
  copia válida. NoCoin no bloquea toda la criptominería; no verified desde CI.
- **trackers** (curl 6): mirror Firebog degradado a `legacy`; migrado a **EasyPrivacy
  3rd Party (r-a-y/mobile-hosts)**, mantenida y apta para móvil, ya en el catálogo
  (`ray_easyprivacy_3rdparty`). No se afirma equivalencia con Native Tracker.
- **phishing** (curl 6): **conservada** (`phishing.army`). El error fue resolución
  DNS, no 404 → NO se marca broken; se conserva la última copia válida.

## 3. BindHosts
Advertencia obligatoria y visible en: instalación (`customize.sh`), WebUI (barra
siempre visible), `environment status` (`bindhosts_active` + mensaje cuando se
detecta activo) y documentación. No se desactiva automáticamente ni se borra su
carpeta. También se muestra "Esta versión continúa en pruebas; la primera estable
será v1.0.0".

## Pendiente en A1 (no incluido aún; próximo sub-paso)
- `dcm_fetch_url` (descargador común HTTPS con clasificación de error, atómico,
  preserva última copia válida) reutilizado por security.sh + catalog.sh.
- `source doctor` (failure_class: ok/dns_system_failed/self_blocked/http_404/…).
- Resolución **bootstrap aislada** por descarga (instancia temporal de
  dnscrypt-proxy con blocklist desactivada solo ahí; sin DNS públicos hardcodeados,
  sin HTTP, sin curl -k) para el bloqueo circular del actualizador.
- Auditoría DNS: `system_shell_resolution: not_verifiable` multi-señal.
- UX de errores por fuente en la WebUI (estados sin_lista/ultima_valida/… + botones
  Reintentar/Diagnosticar/Usar-reemplazo/Revertir/Copiar). Las claves i18n ya están.

## ODoH (precisión)
Los strings del binario prueban code path de ODoH y Anonymized DNSCrypt. NO se
afirma que ODoH funcione en Android: code path presente, ejecución ARM64 pendiente,
target/relay/stamps pendientes, prueba real → CHECKPOINT B.
