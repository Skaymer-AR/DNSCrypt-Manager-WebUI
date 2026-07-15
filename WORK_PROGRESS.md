# WORK_PROGRESS — DNSCrypt Manager v0.2.0

Rama: `feature/security-v0.2.0` (sobre `main`, HEAD original `1a8fd94`).
Autor: Skaymer AR. Objetivo: capa de proteccion de navegacion (RC1).

> Nota: el asistente NO tiene credenciales para hacer `git push` ni abrir el PR.
> Todo esta commiteado en la rama local. Entregables para publicar: bundle git,
> patch y `PR_DESCRIPTION.md` (ver seccion final). El usuario debe hacer el push.

## Estado: TERMINADO (codigo + tests + build) / PENDIENTE (docs restantes)

### Commits en la rama (orden)
1. `feat(security)`: core `scripts/security.sh` (~1560 lineas) + cableado CLI.
2. `feat(security)`: 6 fuentes de blocklists + wiring de boot (service/customize).
3. `feat(webui)`: 9 secciones WebUI + api.js/validation.js/app.js/css.
4. `test(security)`: `smoke-test-security.sh` (61 checks) + fixtures + gate build.
5. (este) `chore`: module.prop v0.2.0 + WORK_PROGRESS.md.

### COMPLETADO
- **CLI** (`system/bin/dnscrypt-manager`): sourcea `security.sh`; 10 comandos
  nuevos en dispatch (protection/blocklists/allowlist/temporary-allow/
  security-profile/failclosed/leak-test/events/security-regen/migrate);
  `set-flag` ampliado (hist_mode|hist_days|hist_max, validados; diag auto-24h);
  hooks `sec_on_service_failure` (start sin-binario/-check/timeout, test-dns) y
  `fc_release` (start-OK/stop/panic/restore-network); `status --json` con campos
  de seguridad. Sintaxis sh+bash OK.
- **security.sh**: blocklists con pipeline de 16 pasos + rollback automatico;
  allowlist; excepciones temporales (5m/15m/1h/boot/perm) con expiracion sin
  cron (sweep perezoso + sleeper detacheado en prod); perfiles balanced/strict/
  privacy (atomicos con snapshot+rollback; strict pide `--confirmed`); fail-closed
  opt-in (cadena `DNSCRYPT_FC` filter / tabla nft `dnscrypt_manager_fc`, nunca
  toca loopback, idempotente); detector de fugas (13 checks, estados protegido/
  posible_fuga/no_verificable/conflicto/fallo; DoH de navegador = no_verificable
  con el mensaje exacto del contrato); eventos + historial local rotado (default
  blocked/3d/1000); migracion schema 1->2 aditiva.
- **Fuentes** `config/blocklist-sources/*.src` (6): URLhaus, Phishing Army,
  durablenapkin, EasyPrivacy, StevenBlack, CoinBlockerLists. Con name/category/
  url/format/license/min-max bytes/min domains.
- **Boot** (`service.sh`): migrate idempotente + sweep de excepciones antes de
  arrancar; `failclosed engage-if-set` si el listener no levanta; salta la
  redireccion si existe `migration-failed`. `customize.sh`: migrate best-effort.
- **WebUI**: `index.html` con 9 tarjetas nuevas (Proteccion web, Perfiles,
  Listas, Allowlist, Excepciones, Auditoria de fugas, Eventos, Privacidad).
  `api.js`: whitelist fija para todo + acciones de dominio validadas (patron
  runNextdns; cliente valida, CLI revalida, valor citado, jamas eval).
  `validation.js`: `isValidDomain`. `app.js`: handlers (textContent puro,
  botones bloqueados durante operaciones, errores concretos comando+rc+mensaje).
  `style.css`: toggles + estados de fuga. WebUI test 23/0.
- **Tests**: `smoke-test-security.sh` 61 OK, 0 FAIL, deterministico 3x.
  Regresiones OK: `smoke-test-cli.sh` 48/0, `smoke-test-webui.sh` 23/0,
  `run-syntax-checks.sh` todo verde (incluye security.sh).
  Fixtures en `tests/fixtures/blocklists/`.
- **module.prop**: version=v0.2.0, versionCode=200.

### PENDIENTE (siguiente paso concreto)
1. Docs a crear: `SECURITY_FEATURES.md`, `BLOCKLIST_SOURCES.md`,
   `ANDROID_TEST_PLAN_v0.2.0.md` (29 pruebas manuales; marcar las que NO corren
   en GitHub Actions), `MIGRATION_v0.1.0_to_v0.2.0.md`, `PRIVACY.md`.
2. Docs a actualizar: `README.md`, `CHANGELOG.md`, `AUDIT_REPORT.md` (Ronda 4
   con resultados 3x + verificacion externa ps/ss).
3. Build RC1: `DCM_OUTPUT=/mnt/user-data/outputs/DNSCrypt-Manager-v0.2.0-RC1.zip
   bash tools/build-module.sh` (corre las 4 suites como gate). Generar `.sha256`,
   `git bundle`, `patch` y `PR_DESCRIPTION.md`. Verificar checklist RC1:
   module.prop en raiz, author=Skaymer AR, binario ARM64 oficial, fail-closed
   OFF, redireccion OFF, sin tests/tools/fixtures en el ZIP.

### Verificacion util
```
bash tests/run-syntax-checks.sh
bash tests/smoke-test-security.sh   # 61 OK
bash tests/smoke-test-cli.sh        # 48 OK
bash tests/smoke-test-webui.sh      # 23 OK
```

### Invariantes respetados
- Redireccion global OFF por defecto; fail-closed OFF por defecto.
- PANIC siempre restaura la red (ademas fuerza failclosed=0 + fc_release).
- Sin eval, sin pgrep/pkill/killall, sin chmod 777, sin flush de reglas ajenas,
  sin tocar SELinux. Escrituras atomicas (tmp+mv), archivos 0600.
- Binario `bin/arm64/dnscrypt-proxy` intacto (sha256 940b6509...).
