# WORK_PROGRESS — DNSCrypt Manager v0.2.0

Rama: `feature/security-v0.2.0` (sobre `main`, HEAD original `1a8fd94`).
Autor: Skaymer AR. Estado: **RC1 COMPLETA — lista para push + PR + validación en Android**.

> El asistente NO tiene credenciales para `git push` ni abrir el PR. Todo está
> commiteado en la rama local. Entregables para publicar están en
> `/mnt/user-data/outputs/` (bundle, patch, PR_DESCRIPTION.md, RC1 zip + sha256).

## TERMINADO (todo)

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
