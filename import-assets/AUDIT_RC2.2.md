# AUDIT — DNSCrypt Manager v0.2.0-RC2.2 (Network/Sources Hotfix)

ZIP: `DNSCrypt-Manager-v0.2.0-RC2.2-Network-Sources-Hotfix.zip`
SHA-256: `6dfcbe623f3c0080b2c02ac1598b292acdbb2459e4796b995fd3aafad48bcc2f`
Tamaño: 4.6M

## Contenido y seguridad (verificado)
- `unzip -t`: integridad OK.
- `module.prop` en la raíz: version=v0.2.0-RC2.2, versionCode=204, author=Skaymer AR, id=dnscrypt_manager.
- Binario ARM64 oficial intacto: SHA `940b650911cfa55cbc0544a9025ceb866101590a88031a90a7e1ca05f5781cbc` (sin tocar).
- Presentes: CLI (`system/bin/dnscrypt-manager`, con `cmd_environment` y el skip de fuentes broken), scripts (incl. `catalog.sh`), catálogo JSON/TSV (71 fuentes), controles de servicio, WebUI completa.
- Catálogo del ZIP: `rc1_coinblocker`=broken, `rc1_easyprivacy_firebog`=legacy, `nocoin_hosts`=unverified (reemplazo), `rc1_phishing_army` conservada.
- PANIC preservado (`cmd_panic`).
- **NO** incluye: tests/, tools/, dist/, .git, *.bundle, *.patch, *.sha256, WORK_PROGRESS, placeholders (verificado: 0 coincidencias).

## Defaults (invariantes de RC2)
- redirect OFF por defecto; fail-closed OFF por defecto; controles de servicio OFF.
- Fuentes externas no activadas accidentalmente; `broken`/`archived` no se descargan.
- Sin descargas durante boot; catálogo canónico inmutable en runtime.
- Instalación directa encima de RC2/RC2.1 (mismo module id); redirect y fail-closed conservan el valor previo; no borra listas válidas.

## Cambios del hotfix (resumen)
1. **CLI/Hybrid Mount**: `environment status` (evidencia, `unknown` cuando no es verificable; mensaje accionable solo en KSU Next no expuesto; sin falsos en Magisk/APatch).
2. **Fuentes**: CoinBlockerLists→broken (404 permanente, no se descarga) + NoCoin como reemplazo (supersedes); Firebog→legacy (degradada, alternativas del catálogo); Phishing Army conservada (el fallo era curl(6), no 404).
3. **Motor**: `cat_update_one` omite fuentes broken/archived preservando la última copia válida.

## Pendiente para completar RC2.2 (no incluido aún, documentado)
`source doctor` (clasificación de failure_class), `dcm_fetch_url` centralizado con
resolución bootstrap por descarga, y la corrección de la auditoría "resolución del
sistema" a `not_verifiable` multi-señal. Este hotfix entrega las correcciones
deterministas de mayor impacto (Hybrid Mount + las 3 fuentes); el resto queda para
un RC2.2 completo o se traslada a v0.3.

## Pruebas
Ver `TEST_RESULTS_RC2.2.md`. Las pruebas en dispositivo las hace el usuario.
