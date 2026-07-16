# Catálogo de blocklists — esquema y modelo de estado (v0.2.0-RC2)

## Dos artefactos, dos responsabilidades

1. **Catálogo canónico (estático, inmutable en runtime)**
   - `config/catalog/blocklists.json` — documento canónico con el esquema completo.
   - `config/catalog/blocklists.index.tsv` — índice plano (19 columnas) que el
     dispositivo lee con `awk` (sin Python en runtime).
   - Generados **solo en desarrollo/CI** por `tools/build-catalog.py`
     (reproducible; `--check` valida que no cambió). **Android NUNCA reescribe
     estos archivos** con `sed`/`awk` durante la ejecución.

2. **Estado runtime (persistente, separado)**
   - `/data/adb/dnscrypt-manager/catalog/source-status.tsv` — resultado local de
     cada fuente. Vive en DATA_DIR, así que **sobrevive a las actualizaciones del
     módulo**. Nunca se mezcla con el estado declarado del catálogo.

## Columnas del índice TSV (1–19)
`id`, `family_id`, `name`, `maintainer`, `categories`, `aggressiveness`, `format`,
`primary_url`, `license`, `upstream_status`, `recommended`, `mobile_suitability`,
`archived`, `supersedes`, `contained_by`, `overlaps_with`, `conflicts_with`,
`last_verified`, `description_es`.

## Estado UPSTREAM (declarado por el catálogo)
- `unverified` — URL de mantenedor conocido, **no descargada/confirmada en CI**.
- `legacy` — fuente heredada del usuario (procedencia/licencia no verificadas).
- `archived` — el upstream está archivado.
- `broken` — confirmado roto (0 en RC2).
- `verified` — reservado; el catálogo **no** afirma verified solo por generar la
  entrada.

> "No verificada" **no** significa "rota". El generador no puede probar una URL sin
> red, por eso el default honesto es `unverified`.

## Estado RUNTIME (resultado local, en `source-status.tsv`)
`never_checked` (default), `verified` (descarga+validación OK en este equipo),
`download_failed`, `validation_failed`, `stale`/`rollback_active` (reservados).
Campos por fuente: `runtime_status`, `last_attempt`, `last_success`, `http_status`,
`bytes`, `sha256`, `total_source`, `valid`, `invalid`, `partial_dns`, `error`,
`effective_url`.

**Promoción `unverified → verified`**: ocurre SOLO tras una descarga+validación
exitosa en el dispositivo; se registra en `source-status.tsv`, nunca en el catálogo.
Una descarga fallida posterior **no** destruye la última `.list` válida ni borra
`last_success`.

## Conversión de formatos
- `hosts`: `0.0.0.0 dominio` / `127.0.0.1 dominio` (localhost y comentarios se
  ignoran).
- `domains`: un dominio por línea.
- `abp`: **solo** reglas de dominio inequívocas (`||dominio^`). Se **ignoran**
  reglas cosméticas (`##`, `#@#`), scripts, `redirect=`, `removeparam=`, reglas por
  ruta, regex, wildcards ambiguos y excepciones (`@@`). Es **cobertura DNS parcial**
  y así se reporta.

## Publicidad para adultos vs contenido adulto
Categorías **separadas**: `adult_advertising` ≠ `adult_content`. Las listas NSFW
**no** se clasifican como publicidad. No se inventan fuentes: si no hay una fuente
dedicada verificable de publicidad para adultos, el CLI lo dice literalmente y aclara
que la cobertura proviene de listas generales de anuncios/pop-ups/malvertising.

## No compilación en boot
En boot se usa la **última lista compilada** existente; no se descarga, no se
recompila, no se depende de red. La compilación completa es una acción explícita
(`catalog compile`) o consecuencia de actualizar fuentes / cambiar activas /
modificar blacklist-allowlist / importar BindHosts.

## Fuentes multimillonarias = opt-in
El módulo se entrega con las fuentes externas **apagadas**. Catálogos de millones de
dominios consumen memoria/tiempo notables (ver `SCALE_RESULTS.md`); activarlos es una
decisión consciente del usuario.
