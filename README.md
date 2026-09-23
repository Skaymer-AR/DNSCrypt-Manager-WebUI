# DNSCrypt Manager

**Creado por Skaymer AR**

Módulo root para Android que ejecuta [`dnscrypt-proxy`](https://github.com/DNSCrypt/dnscrypt-proxy) como servicio de sistema, con redirección DNS opcional, WebUI de control, modo seguro anti-bootloop y recuperación por ADB.

Compatible con **KernelSU**, **KernelSU Next**, **APatch** (WebUI completa) y **Magisk** (botón de Acción + CLI, sin WebUI nativa).

---

## Estado del proyecto

**v1.1.0 es la versión estable actual.** Amplía v1.0.0 con un catálogo de fuentes
de bloqueo DNS auditables, descargables y reversibles. La base DNSCrypt estable se
conserva; Anonymized DNSCrypt y ODoH siguen fuera de la interfaz pública hasta contar
con validación suficiente.

Incluye:

- Servicio `dnscrypt-proxy` gestionado por una única CLI (`dnscrypt-manager`).
- Redirección DNS real vía `iptables`/`ip6tables` o `nftables`, con cadenas propias e idempotentes.
- Cloudflare, Quad9, AdGuard, Mullvad y NextDNS por Configuration ID.
- **Blocklists por categoría** (malware/phishing/estafas/rastreadores/publicidad/criptominería) con actualización verificada y **rollback automático**.
- **Allowlist**, **desbloqueo temporal** (sin cron) y **perfiles de seguridad** (equilibrado/estricto/privacidad).
- **Modo fail-closed opcional** (opt-in, cadenas propias, idempotente), **detector de fugas DNS** y panel **“por qué fue bloqueado”** con historial local limitado.
- Watchdog de arranque con rollback automático si el DNS deja de responder.
- WebUI para KernelSU/KernelSU Next/APatch; CLI y botón Acción para Magisk.
- **Privacidad por servicio** con nueve controles `service-control` y enforcement real sobre la lista compilada.
- **Eventos lazy y colapsables**: no se cargan al iniciar; se consultan únicamente al abrir el panel Actividad.
- Convivencia con **BindHosts** confirmada durante una semana por el usuario en un Motorola Edge 40 Pro con Android 16; no se presenta como garantía universal.
- Comandos de emergencia (`panic`, `disable`, `restore-network`) — **PANIC siempre restaura la red**.
- Pruebas aisladas de sintaxis, CLI, WebUI y **seguridad**.

### Catálogo de blocklists DNS

El catálogo estable usa fuentes upstream como datos descargados por HTTPS. Cada fuente se puede
activar o desactivar por separado; aparecer en el catálogo no la activa. El
parser admite listas de dominios, formato hosts y reglas AdBlock simples que
se pueden convertir sin cambiar su significado DNS. Rechaza URLs, IP-only,
localhost, dominios demasiado amplios y reglas AdBlock con paths, opciones o
semántica que DNS no puede representar.

Los nombres se normalizan, deduplican y quedan asociados a la fuente y a las
categorías declaradas por esa fuente. Una etiqueta como `spyware` describe la
clasificación del upstream; no confirma que cada dominio sea spyware. Las
blocklists pueden producir falsos positivos, no sustituyen un antivirus y no
garantizan detectar todas las amenazas. La allowlist personal de DNSCrypt
Manager prevalece sobre los filtros DNS.

Las fuentes `LICENSE_UNKNOWN` pueden descargarse directamente del upstream
mediante una acción explícita; el contenido no viene empaquetado. Descargar una
fuente no la activa: permanece apagada hasta que la selecciones y apliques. La
etiqueta no certifica permiso de redistribución del upstream.

El motor admite hasta 5 millones de dominios válidos por fuente, 256 MiB por
feed, 5 millones de dominios únicos en el catálogo activo, 10 millones de
entradas activas incluyendo duplicados y 1 GiB de cachés de fuentes activas. El
archivo DNS final admite hasta 5 millones de dominios tras fusionar el catálogo,
las listas legacy y los controles activos. La compilación pide al menos 512 MiB
libres para staging y rollback. Una respuesta rota, vacía, HTML/JSON inesperado,
HTTP fallido o una caída brusca de conteo conserva la caché verificada anterior.
El motor valida la configuración, reemplaza los archivos activos de forma
atómica y revierte la actualización si falla el reinicio o la prueba DNS.

El límite de 5.000 líneas aplica solo a importar un archivo de allowlist; no es
el máximo de dominios bloqueados.

En **Listas** podés usar **Descargar todas las fuentes** para bajar y validar en
segundo plano todas las fuentes compatibles del catálogo, con hasta cuatro
descargas simultáneas (menos si el espacio libre lo requiere). El worker usa
prioridad de CPU reducida y reconstruye el manifiesto una sola vez al finalizar
para que el resto del módulo siga respondiendo. Conserva el último caché válido
ante errores y no activa fuentes nuevas ni cambia el archivo DNS activo. Durante
descargas grandes la WebUI puede responder lenta o parecer congelada; el trabajo
se ejecuta en segundo plano, con prioridad reducida, y la lista DNS activa se
mantiene hasta una compilación explícita. Las
fuentes que el catálogo marca como rotas, archivadas o que requieren revisión
técnica se omiten. La tarea conserva 512 MiB libres como reserva. Al terminar,
seleccioná las que quieras y usá **Aplicar cambios**; si ya había fuentes
activas cuya caché se actualizó, usá **Compilar** para llevar esos cambios al
archivo activo.

El módulo **no edita `/system/etc/hosts`**. Genera `blocked-names.txt` y lo
configura en DNSCrypt Proxy como `[blocked_names] / blocked_names_file`; cada
consulta DNS pasa por el motor del proxy y se compara con esos nombres. La
allowlist personal se entrega como `[allowed_names]` y tiene precedencia sobre
el bloqueo. Es filtrado DNS local, no un archivo hosts con redirecciones ni una
VPN adicional.

La actualización se inicia manualmente. En **Listas → Catálogo de listas** podés
abrir los acordeones **Seguridad**, **Privacidad** y **Control parental** (más las
fuentes propias y las que Rethink no asigna a un grupo). El catálogo empieza
colapsado y dibuja como máximo 15 filas por página del grupo abierto. Podés buscar
una fuente, seleccionar varias y agregarlas juntas; marcar casillas no descarga
ni activa nada. La WebUI muestra estado, dominios validados, caché y último éxito.
No hace polling rutinario; consulta el progreso cada cinco segundos solo mientras
la descarga global solicitada por el usuario está en curso.
Las solicitudes solo descargan feeds públicos: el motor no envía la lista de
apps, el historial DNS ni los dominios consultados. Ver
[`BLOCKLIST_SOURCES.md`](BLOCKLIST_SOURCES.md) y el [informe de auditoría de
Rethink](docs/RETHINK_BLOCKLIST_AUDIT_ES.md) para licencias, procedencia y
límites.

Las categorías se muestran al abrir **Listas**, sin necesitar una búsqueda.
El índice local de metadatos se sincroniza en la instalación/arranque aunque la
versión del esquema ya esté al día; esta operación no cambia las fuentes activas,
la allowlist, los bloqueos manuales ni la configuración DNS.

Los nueve controles existentes de privacidad por servicio permanecen
independientes y en OFF por defecto; esta fase no agrega controles redundantes.

```sh
su -c 'dnscrypt-manager catalog list --recommended'
su -c 'dnscrypt-manager catalog info hagezi_multi_pro'
su -c 'dnscrypt-manager catalog download-all --confirmed' # descarga validada, no activa fuentes
su -c 'dnscrypt-manager catalog download-all status --json'
su -c 'dnscrypt-manager catalog enable hagezi_multi_pro'  # descarga, valida y compila
su -c 'dnscrypt-manager catalog update enabled'           # actualiza fuentes activas
su -c 'dnscrypt-manager catalog disable hagezi_multi_pro'
su -c 'dnscrypt-manager catalog rollback hagezi_multi_pro'
su -c 'dnscrypt-manager allowlist add example.org'
su -c 'dnscrypt-manager catalog manifest'
```

`catalog rollback <id>` recupera la última copia validada de esa fuente. La
allowlist se mantiene en `allowlist.txt`; se puede consultar y respaldar con
`dnscrypt-manager allowlist list` y `dnscrypt-manager allowlist export`.

Por defecto la **redirección global** y el **fail-closed** vienen **DESACTIVADOS**;
la protección de malware/phishing/estafas se activa **después de que las listas se
validen**. Probado con éxito en un **Motorola Edge 40 Pro con Android 16**, sin
pérdida de Wi‑Fi, red móvil ni conectividad.

## Descargar

El módulo instalable se publica en la sección **Releases** del repositorio:

```text
DNSCrypt-Manager-v1.1.0.zip
DNSCrypt-Manager-v1.1.0.zip.sha256
```

Verificá siempre el ZIP con el archivo `.sha256` que acompaña a la misma release. El workflow de publicación reconstruye el módulo desde el código fuente, descarga y valida el binario oficial ARM64 de `dnscrypt-proxy` y genera un checksum nuevo para ese build exacto.

## Requisitos

- Android 13, 14, 15 o 16.
- Arquitectura **arm64-v8a**.
- KernelSU, KernelSU Next, APatch o Magisk.
- SELinux Enforcing soportado.

## Instalación

1. Descargá `DNSCrypt-Manager-release.zip` desde **Releases**.
2. Instalalo desde KernelSU, APatch o Magisk.
3. Reiniciá el dispositivo.
4. Abrí la WebUI y ejecutá **Probar DNS**.
5. Activá la redirección global solo después de verificar que el proxy resuelva correctamente.

Por seguridad, **la redirección global está desactivada por defecto**.

## Recuperación de emergencia

```sh
su -c dnscrypt-manager panic
su -c dnscrypt-manager redirect remove
su -c dnscrypt-manager restore-network
su -c dnscrypt-manager disable
```

## Compilar

```sh
./tools/inject-binary.sh /ruta/al/dnscrypt-proxy
./tools/build-module.sh
```

## Pruebas

```sh
bash tests/run-syntax-checks.sh
bash tests/smoke-test-cli.sh
bash tests/smoke-test-webui.sh
bash tests/smoke-test-blocklist-engine.sh
```

## Funciones visuales actuales

- Estado del servicio, PID y listener.
- Iniciar, detener y reiniciar.
- Prueba DNS.
- Cloudflare, Quad9, AdGuard, Mullvad y NextDNS.
- Aplicar o quitar redirección DNS.
- Redirección automática al arranque.
- Modo IPv6.
- Diagnóstico de Private DNS.
- Logs.
- Botón PANIC.

## Documentación

- `SECURITY_FEATURES.md`: capa de seguridad v0.2.0 (blocklists, allowlist, excepciones, perfiles, fail-closed, fugas, eventos) con comandos.
- `BLOCKLIST_SOURCES.md`: fuentes públicas de las listas, licencias y metadatos.
- `PRIVACY.md`: qué se guarda, dónde, cuánto y cómo borrarlo (sin telemetría).
- `MIGRATION_v0.1.0_to_v0.2.0.md`: cómo se migra sin perder configuración.
- `ANDROID_TEST_PLAN_v0.2.0.md`: 29 pruebas manuales en dispositivo real.
- `BINARY_INFO.md`: procedencia y validación del binario.
- `AUDIT_REPORT.md`: pruebas, riesgos y limitaciones.
- `CHANGELOG.md`: historial de versiones públicas.

## Agradecimientos

Parte del desarrollo y la auditoría contó con asistencia de herramientas de IA. La autoría, dirección y responsabilidad del proyecto son de **Skaymer AR**.

## Novedades en v0.2.0-RC2

Catálogo de blocklists por metadatos con motor genérico de fuentes, además de la
capa de seguridad de RC1. Documentación detallada en `docs/`:
`CATALOG_SCHEMA.md`, `BLOCKLIST_CONFLICTS.md`, `BINDHOSTS_IMPORT.md`,
`SERVICE_CONTROLS.md`, `SCALE_RESULTS.md` y `ANDROID_TEST_PLAN_v0.2.0.md`.

Puntos clave:
- Catálogo canónico (`config/catalog/blocklists.json` + `.index.tsv`) generado en
  dev/CI; **inmutable en el dispositivo**. El estado local de verificación vive
  aparte en `catalog/source-status.tsv` (persistente, sobrevive updates).
- Estados de fuente honestos: `unverified`/`legacy`/`archived`/`broken`; el estado
  `verified` se otorga **solo** tras una descarga+validación real en el equipo.
- `dnscrypt-manager catalog {list|enable|disable|update|compile|compile-status|
  compile-cancel|conflicts|overlap|stats|custom|...}`,
  `dnscrypt-manager import-bindhosts <dir> [--dry-run|--confirmed]`,
  `dnscrypt-manager service {list|info|set|conflicts}`.
- Compilación por lotes a escala con lock/timeout/cancelación/rollback y **PANIC**
  que cancela la compilación sin borrar datos. No se compila en boot.
- Predeterminados sin cambios: redirect OFF, fail-closed OFF, transporte directo,
  controles de servicio OFF, fuentes externas apagadas. Fuentes multimillonarias
  son opt-in (ver advertencias de memoria en `docs/SCALE_RESULTS.md`).

## Autor

**Skaymer AR**

Proyecto creado y mantenido por Skaymer AR.
