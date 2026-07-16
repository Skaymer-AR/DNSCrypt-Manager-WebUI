# WORK_PROGRESS — DNSCrypt Manager v0.2.0

Rama: `feature/security-v0.2.0` (sobre `main`, HEAD original `1a8fd94`).
Autor: Skaymer AR. Estado: **RC2 EN CURSO — checkpoint estable (210 checks verdes)**.

> El asistente NO tiene credenciales para `git push` ni abrir el PR. Todo está
> commiteado en la rama local. Entregables para publicar están en
> `/mnt/user-data/outputs/` (bundle, patch, PR_DESCRIPTION.md, RC1 zip + sha256).

## RC2 — ESTADO (checkpoint)

Roadmap: **v0.2.0-RC2 → v0.3.0-RC1 → prueba real ~5 días → v1.0.0**.

### Terminado en RC2 (commiteado)
- **Etapa 1 — Catálogo por metadatos**: `tools/build-catalog.py` (solo dev/CI,
  python3) emite `config/catalog/blocklists.json` (canónico) +
  `blocklists.index.tsv` (plano para awk en Android; **Python NO es dependencia
  runtime**). **70 entradas, 10 familias.** `--check` verifica reproducibilidad.
  Validaciones: IDs únicos, categorías válidas, URLs https/file, paridad JSON/TSV,
  sin URLs duplicadas, orden estable, sin tabs/saltos que rompan el TSV.
  Motor genérico en `scripts/catalog.sh` (~1070 líneas): enable/disable, custom,
  descarga+validación, formatos hosts/domains/ABP, compilación por lotes
  (sort/uniq/comm, sin loops shell), conflictos por metadatos. Integrado en
  `sec_merge_blocked` (hook liviano `cat_append_active`) y migración.
- **Etapa 2 — Importador BindHosts**: `import-bindhosts <dir> [--dry-run|--confirmed]`.
  Dry-run no modifica nada. sources/blacklist/whitelist/custom con detección de
  StevenBlack duplicado, URL de DandelionSprout corregida, fuente archivada, URL
  rota, URL en whitelist (rechazada), dominio inválido, entrada de ejemplo,
  sospechoso `s.youtube.com.domain.name` (marcado, no importado), inyección shell.
  Normaliza `https://click.redditmail.com` → `click.redditmail.com`. Aplica atómico.
- **Etapa 3 — Estados honestos**: `verified/unverified/archived/broken/legacy`.
  El generador NO afirma verified (sin red en CI): 62 unverified, 7 legacy, 1
  archived (antipopads-re), 0 broken. Validación: archived⇒status=archived,
  archived/broken no recomendables.
- **Estado runtime SEPARADO** (corrección clave): el catálogo generado queda
  **inmutable**; el resultado local vive en `catalog/source-status.tsv` (en
  DATA_DIR, sobrevive updates del módulo). Columnas: source_id, runtime_status,
  last_attempt, last_success, http, bytes, sha256, total, valid, invalid,
  partial_dns, error, effective_url. `runtime_status` en CADA intento
  (verified/download_failed/validation_failed). Nunca se mezcla con el estado
  upstream. Una descarga fallida NO destruye la última `.list` válida ni
  `last_success`. Verificado: (1) SHA del JSON intacto, (2) verified persistido,
  (3) historial sobrevive re-migración, (4) fallo preserva última fuente válida.
- **Etapa 4 — Control de servicio YouTube**: `service-controls.json/tsv` +
  motor en `catalog.sh` (`service list/info/set/conflicts/sync`). `youtube_no_history`
  bloquea `s.youtube.com`, modos normal/15m/1h/boot/perm, expiración perezosa por
  boot_id + reloj. Texto obligatorio de mejor esfuerzo + efectos colaterales.
  Usa su PROPIO estado (no toca blacklist/allowlist del usuario); conflicto con
  allowlist reportado sin resolver silenciosamente.
- **WebUI RC2**: 4 tarjetas nuevas (catálogo con búsqueda + paginación cliente,
  fuentes personalizadas, importación BindHosts en 2 pasos, controles de servicio).
  `initCatalogRC2()` llamado desde `init()`. `textContent`/`createElement` puro,
  estados de carga, bloqueo de botones, refresh tras éxito.
- **Seguridad de argumentos WebUI**: cada capacidad = UN subcomando fijo;
  `SOURCE_ID` `^[a-z0-9][a-z0-9._-]{0,63}$`, URL https sin metacaracteres, ruta
  absoluta sin `..`/`-`; todo interpolado entre comillas simples (`shQuote`);
  sin eval, sin sh -c con datos, sin source de archivos del usuario.
- **adult_advertising**: mensaje literal cuando no hay fuente dedicada verificable.

### Tests RC2 (ejecutados)
- syntax: **OK** · WebUI: **23/23** · security: **61/61** · CLI: **48/48**
- catalog: **41/41** (`tests/smoke-test-catalog.sh`)
- args: **37/37** (`tests/smoke-test-webui-args.cjs`)
- compile+stats: **19/19** (`tests/smoke-test-compile.sh` — **portable**: residuos
  acotados a descendientes del harness vía /proc, sin escaneo global de procesos)
- escala **100k: 24/24** (`tests/scale-test-compile.sh` — suite funcional COMPLETA;
  low-space **determinístico** vía override `DNSCRYPT_TEST_FREE_KB` solo en TEST_MODE
  y numérico; producción usa `df` real. Ambos harnesses independientes del host)
- escala **500k/1M/2.5M: benchmark MÍNIMO del merge** (solo `cat_append_active`+`sort -u`;
  NO se ejecutaron cancel/timeout/rollback/recarga DNS/lock a esa escala):
  700 002 / 1 400 002 / 3 500 002 dominios; wall 0.50/0.75/2.28 s; maxRSS 52/103/**255** MB
  (Linux; **advertencia para Android**: catálogos multimillonarios deben ser opt-in).
- **Suite completa base: 210/210, 0 fallos.** Sin regresiones de RC1.

### Conflictos/redundancias, aporte único y pipeline (verificado en código)
- Conflictos distingue supersedes/contained_by/overlaps_with/conflicto funcional +
  **archivada/rota/formato-parcial-ABP/allowlist-neutraliza**, una sola advertencia
  canónica por relación; `catalog overlap A B` exacto bajo demanda; sin O(N²).
- Aporte único por fuente en orden canónico (recomendadas→id), lotes comm/sort,
  resumen efectivo tras allowlist; guardado en `contribution-stats.tsv` (runtime,
  separado del catálogo). Documentado: depende del orden → se fija orden canónico.
- Pipeline: lock atómico (mkdir), PID validado por `/proc/cmdline`, huérfano
  recuperable (PID muerto **y** ajeno vivo), trap EXIT/INT/TERM/HUP, `_cat_kill_tree`
  portable (sin pkill/killall), `compile-status`/`compile-cancel`, timeout real,
  temporales en DATA_DIR, rollback + última lista preservada, nice/ionice sobre el
  proceso pesado real, **PANIC cancela compilación sin borrar datos**, boot no recompila.

### HEAD
Este documento describe el estado hasta el commit anterior al de su propia
actualización; el HEAD final exacto se entrega fuera del repositorio (bundle/patch
y en la respuesta de cierre), para no auto-referenciar un hash que cambia al
commitear este archivo.

### Pendientes reales de RC2 (orden)
1. Docs de capacidad restantes: CATALOG_SCHEMA.md, BLOCKLIST_CONFLICTS.md,
   BINDHOSTS_IMPORT.md, SERVICE_CONTROLS.md, ANDROID_TEST_PLAN_v0.2.0.md;
   actualizar README/CHANGELOG/AUDIT_REPORT. 2. `module.prop` → v0.2.0-RC2 /
   versionCode=202 (mantener author=Skaymer AR). 3. Suite completa una sola vez.
   4. Build limpio + `unzip -t` + auditoría de contenido + verificación binario
   ARM64 + SHA-256 final. **Sin** reemplazar RC1.

### Próximo paso exacto
Escribir las docs de capacidad restantes; luego cambiar module.prop a RC2, correr
la suite completa una vez, build, auditoría del ZIP y checksum.

### Pendientes documentados para v0.3.0-RC1 (fuera de RC2)
Anonymized DNSCrypt, ODoH, captive portal, extensión de detección de bypass,
monitor de actividad sospechosa, reorganización WebUI por pestañas, i18n ES/EN,
controles de servicio más allá de YouTube, dashboard de estadísticas, análisis de
conflictos más rico.

---

## (RC1) TERMINADO — histórico

- **CLI** (`system/bin/dnscrypt-manager`): sourcea `security.sh`; 10 comandos en
  dispatch; `set-flag` ampliado (hist_*); hooks fail-closed en start/stop/panic/
  test-dns/restore-network; `status --json` con campos de seguridad.
- **`scripts/security.sh`** (~1560 líneas): blocklists (pipeline 16 pasos +
  rollback), allowlist, excepciones sin cron, perfiles atómicos, fail-closed
  opt-in aislado, detector de fugas, eventos/historial rotado, migración 1→2.
- **`config/blocklist-sources/*.src`** (6 fuentes documentadas).
- **Boot**: `service.sh` (migrate+sweep+engage-if-set+guard) y `customize.sh`.
- **WebUI**: 9 secciones (`index.html`), `api.js` (whitelist + acciones de
  dominio validadas), `validation.js` (`isValidDomain`), `app.js` (handlers),
  `style.css`.
- **module.prop**: v0.2.0 / versionCode=200.
- **Docs**: SECURITY_FEATURES.md, BLOCKLIST_SOURCES.md, PRIVACY.md,
  MIGRATION_v0.1.0_to_v0.2.0.md, ANDROID_TEST_PLAN_v0.2.0.md + README/CHANGELOG/
  AUDIT (Ronda 4).
- **Tests**: `smoke-test-security.sh` (61 OK, 0 FAIL, determinista 3x) + fixtures.
  Regresiones: cli 48/0, webui 23/0, syntax verde. Build exige las 4 suites.

## RESULTADOS DE PRUEBAS (verificados)

| Suite | Resultado |
|-------|-----------|
| smoke-test-security.sh | 61 OK / 0 FAIL / 0 TIMEOUT (3 corridas) |
| smoke-test-cli.sh | 48 OK / 0 FAIL |
| smoke-test-webui.sh | 23 OK / 0 FAIL |
| run-syntax-checks.sh | todo verde (incluye security.sh) |

## RC1 GENERADA Y VERIFICADA

`DNSCrypt-Manager-v0.2.0-RC1.zip` (+ `.sha256`). Checklist RC1: module.prop en
raíz (v0.2.0 / author=Skaymer AR), binario ARM64 oficial intacto (sha256
940b6509…), sin tests/tools/fixtures, sin estado pre-activado (fail-closed y
redirect OFF), security.sh + 6 fuentes incluidos, 5 docs presentes. TODO OK.

## SIGUIENTE PASO CONCRETO

1. **Push + PR** (requiere credenciales del usuario). Usar el bundle o el patch
   de `/mnt/user-data/outputs/`; el cuerpo del PR está en `PR_DESCRIPTION.md`.
2. **Validación manual en Android real** siguiendo `ANDROID_TEST_PLAN_v0.2.0.md`
   (netfilter del fail-closed, SELinux enforcing, IPv6/VPN/hotspot/Private DNS,
   binario oficial corriendo). Es lo único que CI no puede cubrir.
3. Tras validar en dispositivo, promover RC1 a release estable (recién ahí
   reemplaza a v0.1.0).

## Invariantes respetados

Redirección global y fail-closed OFF por defecto. PANIC siempre restaura la red.
Sin eval/pgrep/pkill/killall/chmod 777/flush ajeno/setenforce. Escrituras
atómicas, archivos 0600. Binario intacto. Compatible KernelSU/Next/APatch/Magisk,
Android 13–16, ARM64, SELinux enforcing.
