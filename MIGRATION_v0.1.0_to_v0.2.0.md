# MIGRATION_v0.1.0_to_v0.2.0.md — DNSCrypt Manager

Creado por **Skaymer AR**.

Cómo se actualiza de v0.1.0 a v0.2.0 sin perder nada de tu configuración.

## Qué se conserva

La migración es **aditiva**: no toca ni pisa lo que ya tenías. Se conservan:

- Proveedor seleccionado (Cloudflare/Quad9/AdGuard/Mullvad).
- Configuration ID de NextDNS.
- Modo IPv6 (redirect/block).
- Redirección automática al boot (`boot_redirect`).
- Configuración TOML actual y backups existentes.
- Estado de habilitación del módulo.
- Logs existentes cuando es seguro conservarlos.
- Comportamiento del botón **PANIC**.

Lo único que agrega son los valores nuevos de la capa de seguridad, y **solo si
no existían**: categorías de protección con sus defaults (malware/phishing/
estafas activadas; el resto no), `failclosed=0`, e historial en `blocked`/3
días/1000. Crea también los directorios y las fuentes de blocklists.

## Versionado del esquema

- **Schema 1** = v0.1.0 (no existe archivo de versión).
- **Schema 2** = v0.2.0 (archivo `/data/adb/dnscrypt-manager/schema_version`
  con el valor `2`).

La migración corre una sola vez y es **idempotente**: si el esquema ya es 2, no
hace nada.

## Cuándo corre

1. Al **instalar/actualizar** el ZIP (`customize.sh`, best-effort).
2. En el **primer arranque** tras actualizar (`service.sh`), como red de
   seguridad si el paso anterior no pudo completarse.
3. Manualmente: `dnscrypt-manager migrate`.

## Si la migración falla

Diseño de recuperación segura. Si algo sale mal durante la migración:

- Tu **configuración anterior queda intacta**.
- La **redirección global no se activa** ese arranque (aunque `boot_redirect`
  estuviera en 1), gracias a un flag `migration-failed`.
- **Fail-closed queda en 0** (nunca se activa por una migración a medias).
- Se registra el error en los logs del módulo.
- El sistema sigue usable y podés reintentar con `dnscrypt-manager migrate`.

## Verificación post-migración

```
cat /data/adb/dnscrypt-manager/schema_version      # debe imprimir: 2
dnscrypt-manager status                            # proveedor/estado intactos
dnscrypt-manager protection status                 # defaults de seguridad
dnscrypt-manager failclosed status                 # debe estar inactivo
```

## Reversión

v0.2.0 no borra nada de v0.1.0, así que reinstalar v0.1.0 vuelve a la CLI/WebUI
anteriores; los datos nuevos (listas, allowlist, eventos) simplemente quedan
ignorados por la versión vieja. Para una limpieza total, desinstalá el módulo
(se elimina el directorio de datos) y reinstalá desde cero.
