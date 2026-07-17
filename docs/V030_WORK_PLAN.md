# DNSCrypt Manager v0.3.0-RC1 — Plan de trabajo

Rama: `feature/v0.3.0-rc1` (desde RC2 `34df8e4`). Objetivo final:
version=v0.3.0-RC1, versionCode=300, author=Skaymer AR. **No** borra RC1/RC2.

## Invariantes (no regresionar)
Todo lo estable de RC2 se conserva y sus suites siguen verdes. El fix de fuga de
procesos del timeout es invariante. Defaults nuevos OFF. Sin descargas en boot.
Catálogo inmutable. PANIC siempre disponible.

## Checkpoints (con bundle+patch+sha256 y WORK_PROGRESS_v0.3.md en cada uno)
- **A**: arquitectura + WebUI por secciones + i18n.
- **B**: Anonymized DNSCrypt + ODoH + transporte y rollback.
- **C**: portal cautivo + bypass + monitor.
- **D**: service controls declarativos + políticas por app + catálogo.
- **E**: migración schema 3 + tests + documentación + build.

## Etapas
0. Recuperación/auditoría + esta arquitectura. (hecho)
1. WebUI SPA por secciones (router hash, nav inferior, DOM seguro). Commit propio.
2. i18n EN/ES (`webroot/i18n/{en,es}.json`, `webroot/js/i18n.js`), EN default,
   persistente, fallback EN; test de claves faltantes/extra. Commit propio.
3. Anonymized DNSCrypt (`transport.sh`): resolvers/relays/routes, test, apply
   atómico, rollback, estado, eventos; CLI `transport|anonymized`.
4. ODoH (soportado por el binario, confirmado): targets/relays, test, apply
   atómico, rollback, estado; CLI `odoh`. Nunca "activo" sin prueba real.
5. Portal cautivo (`captive.sh`): detección de cambio de red/conectividad
   limitada, modo manual, pausa mínima con temporizador, restauración, eventos;
   CLI `captive status|enter|restore`. No desactiva todo silenciosamente.
6. Bypass ampliado (`bypass.sh`): 53/853/DoH conocido/Private DNS/VPN/hotspot/
   IPv6; modos auditoría/advertencia/estricto opt-in; niveles info/warning/high.
7. Monitor (`monitor.sh`): heurísticas locales (ráfagas, NXDOMAIN, DGA/entropía,
   túneles), clasificación normal/unusual/suspicious/high-risk, retención+rotación,
   export JSON/CSV; sin nube.
8. Service controls declarativos (`config/service-controls/*.json`): YouTube +
   Spotify/Reddit/Samsung/Xiaomi/Microsoft/Meta/TikTok/Google **telemetry/tracking**
   (nombres honestos, "reduce telemetry"). Sin control de publicidad adulta.
9. Políticas por app (`apppolicy.sh`): detectar capacidades (owner match/skuid);
   cadenas propias con marca; rollback; PANIC solo lo propio; si no hay soporte,
   "No compatible".
10. Catálogo: auditoría (URLs repetidas/redirects/404/archivado/formato/licencia/
    HTML/tamaño/cert); ampliar solo con fuentes mantenidas y verificables;
    conservar las 70. No verified desde CI.
11. Estadísticas/dashboard con lazy loading/paginación; sin historiales ilimitados.

## Migración
`sec_migrate` schema 2→3 idempotente con backup+rollback; nuevos defaults OFF;
idioma EN; redirect/fail-closed conservan valor previo.

## CLI (nuevos, sin romper existentes)
`transport …`, `anonymized …`, `odoh …`, `captive …`, `monitor …`, `bypass …`,
`app-policy …`. Toda entrada revalidada en CLI.

## Pruebas (fixtures locales, sin Internet)
Nuevas suites por componente (router/i18n/transport/anonymized/odoh/captive/
bypass/monitor/service-controls/app-policy/migration-v3/webui-v030/args-v030).
Mantener verdes las de RC2. Suite completa solo en checkpoints y al final.

## Build final
ZIP RC1 sin tests/tools/fixtures/dist/.git/bundles/patches/WORK_PROGRESS/estado
runtime/caches/temporales/placeholders; con module.prop raíz, CLI, WebUI, i18n,
scripts, catálogo, service controls, migración schema 3, binario ARM64, PANIC.
Auditar `unzip -t`, permisos, defaults OFF, boot sin descargas.
