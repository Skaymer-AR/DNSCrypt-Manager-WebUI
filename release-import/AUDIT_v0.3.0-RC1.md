# AUDIT — DNSCrypt Manager v0.3.0-RC1

ZIP: `DNSCrypt-Manager-v0.3.0-RC1.zip` (4.6M, 104 archivos)
SHA-256 local de referencia: `12c1b81d8c78d707032315f127755a835dbc48f82afc0a67e106e341dfa8e725`

## Gate verificado
- `unzip -t`: integridad OK.
- `module.prop`: version=v0.3.0-RC1, versionCode=300, author=Skaymer AR, id=dnscrypt_manager.
- Binario ARM64 oficial intacto: SHA `940b650911cfa55cbc0544a9025ceb866101590a88031a90a7e1ca05f5781cbc`.
- Migración schema 2→3 presente e idempotente; defaults nuevos OFF.
- Scripts nuevos: fetch, transport, captive, bypass, monitor, servicectl y apppolicy.
- 9 service-controls declarativos y configuración de relays.
- WebUI SPA con router, i18n EN/ES, source doctor y environment.
- Sin tests, tools, dist, .git, WORK_PROGRESS, bundles, patches ni placeholders en el ZIP.

## Defaults OFF
Anonymized, ODoH, captive, bypass strict, service-controls y app-policy están desactivados por defecto. Monitor inicia en audit. Sin descargas en boot. PANIC permanece disponible. BindHosts debe permanecer desactivado.

## Honestidad
ODoH no se marca activo sin prueba real. En x86 queda `not_verifiable`. App-policy devuelve `unsupported` sin soporte owner/skuid. El monitor es heurístico y nunca afirma malware confirmado.

## Nota
Las pruebas físicas en Moto Edge 40 Pro, Android 16, KernelSU Next, SELinux Enforcing e Hybrid Mount quedan pendientes del usuario. RC1 es para pruebas; la primera estable será v1.0.0.
