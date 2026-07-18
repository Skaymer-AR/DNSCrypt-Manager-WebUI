# WORK_PROGRESS — DNSCrypt Manager v0.3.0-RC1

Rama: `feature/v0.3.0-rc1` (desde RC2 `34df8e4`). Autor: Skaymer AR.
Base: **v0.2.0-RC2 terminada** (schema 2, 70 fuentes, binario ARM64 `940b650…`).
Estado: **CHECKPOINT A completado**. No borra RC1/RC2. Mismo module id.

> El asistente NO tiene credenciales de push. Los entregables (bundle/patch/sha256
> por checkpoint) van a `/mnt/user-data/outputs/`. Este documento describe el
> estado hasta el commit anterior al de su propia actualización; el HEAD exacto se
> entrega fuera del repositorio.

## CHECKPOINT A1 — en progreso (correcciones de campo antes de B)
Incorporado a v0.3 (cherry-pick selectivo del hotfix RC2.2, **sin** module.prop/
branding RC2.2) + trabajo nuevo:
- **Fuentes (catálogo)**: CoinBlockerLists→broken (no se descarga), NoCoin agregada
  (supersedes), Firebog→legacy; Phishing Army conservada. 71 fuentes, reproducible.
- **Fuentes antiguas (.src de security.sh)**: cryptomining→NoCoin (hosts),
  trackers→EasyPrivacy 3rd Party (r-a-y, hosts) con Firebog legacy, phishing
  conservada (curl 6 = fallo DNS, no 404).
- **CLI resolver central** en `api.js`: eliminadas las constantes fijas duplicadas
  (`api.js`/`app.js`); 3 rutas de allowlist, probe fijo, solo acepta allowlist; si
  no resuelve → mensaje claro (no rc=127). `runEnvironmentStatus`/`cli()`/etc.
- **environment status** (Hybrid Mount, evidencia, `bindhosts_active`) + tarjeta de
  entorno en la WebUI.
- **BindHosts**: advertencia obligatoria en instalación (`customize.sh`), WebUI
  (barra) y `environment status`; + "en pruebas / v1.0.0". No lo desactiva.
- **i18n**: +env.*/bindhosts.*/app.testing/src.state.*/src.action.*/src.msg.* (114
  claves EN/ES, paridad).

### Tests A1 (verdes)
- `smoke-test-cli-resolver-v030.cjs`: **6/6**
- `smoke-test-environment-v030.sh`: **19/19**
- Regresión: `smoke-test-webui.sh` **23/23**, `smoke-test-webui-v030.cjs` **15/15**,
  `smoke-test-i18n.sh` **5/5**, `smoke-test-catalog.sh` **41/41**,
  `smoke-test-security.sh` **61/61**, `run-syntax-checks.sh` OK.

### Pendiente para cerrar A1 (próximo sub-paso, NO es B)
`dcm_fetch_url` común + `source doctor` (failure_class) + resolución bootstrap
aislada (bloqueo circular) + auditoría DNS `not_verifiable` multi-señal + UX de
errores por fuente en la WebUI (claves i18n ya presentes) + sus tests
(source-doctor/source-fetch/bindhosts-warning/dns-audit). Recién luego CHECKPOINT B.

## Confirmaciones de base
- ODoH y Anonymized DNSCrypt **soportados por el binario incluido** (verificado por
  strings: `*main.ODoHTargetConfig`, `*main.ODoHRelay`, `/.well-known/odohconfigs`,
  `oblivious_doh.go`, `OK (ODoH) - rtt`). → se implementarán de verdad (ETAPAS 3/4).
- Invariante: el fix de fuga de procesos del timeout de RC2 (`_cat_kill_tree` con
  SIGSTOP antes de recolectar + kill_tree antes del group-kill) NO se revierte.

## CHECKPOINT A — terminado (commiteado)
- **ETAPA 0**: rama `feature/v0.3.0-rc1`; `docs/V030_ARCHITECTURE.md` +
  `docs/V030_WORK_PLAN.md` (componentes, persistente vs runtime, seguridad,
  migración 2→3, límites de diseño DNS, funciones experimentales OFF).
- **ETAPA 2 (i18n)**: `webroot/i18n/{en,es}.json` (83 claves), `webroot/js/i18n.js`.
  EN por defecto y fallback; ES opcional; elección persistente (localStorage con
  try/catch); no depende del idioma del sistema; solo texto visible; DOM seguro.
- **ETAPA 1 (WebUI SPA)**: `index.html` reorganizado en 5 secciones con router
  hash (`#/status #/dns #/lists #/activity #/settings`) y navegación inferior fija;
  `webroot/js/router.js` (recuerda pestaña, botón Atrás, estado activo, fallback);
  CSS de nav + safe-area; selector de idioma en Ajustes. **Todos los IDs de RC2
  preservados** → handlers y suite WebUI intactos.

## Tests (CHECKPOINT A)
- `smoke-test-webui.sh` (RC2): **23/23** (sin regresión con el HTML reestructurado).
- `smoke-test-webui-v030.cjs`: **15/15** (router default/switch/activo/recordar/
  Atrás/fallback + i18n EN default/ES en caliente/fallback/apply).
- `smoke-test-i18n.sh`: **5/5** (JSON válido, claves idénticas, placeholders,
  referencias data-i18n sin colgar; aviso de 65 claves aún no usadas → etapas
  futuras).
- `run-syntax-checks.sh`: OK.
- Suites RC2 base previas: 210/210 (última corrida completa antes de este branch).

## Pendientes (orden de checkpoints B–E)
- **B**: Anonymized DNSCrypt + ODoH + `transport.sh` (test/apply atómico/rollback,
  last-known-good) + CLI `transport|anonymized|odoh`.
- **C**: portal cautivo (`captive.sh`), bypass ampliado (`bypass.sh`), monitor
  (`monitor.sh`).
- **D**: service-controls declarativos (`config/service-controls/*.json` +
  Spotify/Reddit/Samsung/Xiaomi/Microsoft/Meta/TikTok/Google telemetry, honestos),
  políticas por app (`apppolicy.sh`, detección de capacidades), auditoría/ampliación
  del catálogo.
- **E**: migración schema 2→3 idempotente (defaults nuevos OFF), suites nuevas,
  documentación completa, build RC1 + auditoría del ZIP + SHA-256.

## Próximo paso exacto
Iniciar CHECKPOINT B: crear `scripts/transport.sh` con el motor genérico de
aplicación atómica (temp→validar→probar aislado→reemplazar→reiniciar→verificar→
rollback) reutilizando el patrón lock+child+trap+kill_tree; luego Anonymized
DNSCrypt (resolvers/relays/routes/test/apply) y ODoH.

## Límites (no falsear — LIMITATIONS.md pendiente)
Filtro DNS: sin MITM/HTTPS/VPN/filtros cosméticos. YouTube Ads best-effort. No toda
regla ABP es convertible. Atribución por app limitada. ODoH depende del binario.
Monitor heurístico. Resultados Linux ≠ Android. Sin descargas en boot. Catálogo
inmutable. PANIC siempre disponible.
