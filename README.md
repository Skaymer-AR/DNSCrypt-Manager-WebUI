# DNSCrypt Manager

**Creado por Skaymer AR**

Módulo root para Android que ejecuta [`dnscrypt-proxy`](https://github.com/DNSCrypt/dnscrypt-proxy) como servicio de sistema, con redirección DNS opcional, WebUI de control, modo seguro anti-bootloop y recuperación por ADB.

Compatible con **KernelSU**, **KernelSU Next**, **APatch** (WebUI completa) y **Magisk** (botón de Acción + CLI, sin WebUI nativa).

---

## Estado del proyecto

Esta es la **versión mínima funcional**. Cubre:

- Servicio `dnscrypt-proxy` gestionado por una única CLI (`dnscrypt-manager`).
- Redirección DNS real vía `iptables`/`ip6tables` (cadenas propias) o `nftables`, con detección automática de backend.
- Cuatro proveedores preestablecidos (Cloudflare, Quad9, AdGuard, Mullvad) y NextDNS por Configuration ID.
- Watchdog de arranque con rollback automático si el DNS deja de responder.
- WebUI mínima (panel principal, servidores, redirección, logs, diagnóstico, emergencia).
- Comandos de emergencia por CLI/ADB (`panic`, `disable`, `restore-network`).
- Batería de pruebas aislada (sintaxis, CLI, WebUI) — ver `tests/` y `AUDIT_REPORT.md`.

**Todavía no incluidos** (explícitamente diferidos, no son bugs): editor TOML avanzado en la WebUI, selección de aplicaciones por UID, listas de bloqueo personalizadas, gestor visual de copias de seguridad, cambio asistido de Private DNS. Todo lo anterior ya es operable por CLI (`su -c dnscrypt-manager help`) mientras se agrega su contraparte visual.

## Requisitos

- Android 13, 14, 15 o 16.
- Arquitectura **arm64-v8a** (prioritaria; armeabi-v7a opcional).
- KernelSU, KernelSU Next, APatch o Magisk (v20.4+).
- SELinux Enforcing soportado sin pedir desactivarlo.

## Instalación

1. Descargá el ZIP instalable desde `dist/DNSCrypt-Manager-release.zip` o desde la sección de archivos del repositorio.
2. Aplicalo desde Magisk Manager, KernelSU Manager o APatch.
3. Reiniciá el dispositivo.
4. Abrí la WebUI desde el gestor de módulos (KernelSU/KernelSU Next/APatch) o usá el botón de Acción (Magisk).

Por seguridad, **la redirección global arranca desactivada**. Activala desde la WebUI (o `redirect apply` por CLI) una vez que confirmes que el servicio resuelve DNS correctamente.

## Comandos de emergencia (ADB o terminal root)

```sh
su -c dnscrypt-manager panic
su -c dnscrypt-manager disable
su -c dnscrypt-manager enable
su -c dnscrypt-manager restore-network
su -c dnscrypt-manager reset-config
su -c dnscrypt-manager logs
```

Ver `su -c dnscrypt-manager help` para la lista completa de comandos.

## Compilar / empaquetar

```sh
./tools/inject-binary.sh /ruta/al/dnscrypt-proxy
./tools/build-module.sh
```

## Pruebas

```sh
bash tests/run-syntax-checks.sh
bash tests/smoke-test-cli.sh
bash tests/smoke-test-webui.sh
```

## Autor

**Skaymer AR**

Proyecto creado y mantenido por Skaymer AR.
