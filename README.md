# DNSCrypt Manager

**Creado por Skaymer AR**

Módulo root para Android que ejecuta [`dnscrypt-proxy`](https://github.com/DNSCrypt/dnscrypt-proxy) como servicio de sistema, con redirección DNS opcional, WebUI de control, modo seguro anti-bootloop y recuperación por ADB.

Compatible con **KernelSU**, **KernelSU Next**, **APatch** (WebUI completa) y **Magisk** (botón de Acción + CLI, sin WebUI nativa).

---

## Estado del proyecto

Esta es la **versión mínima funcional**. Cubre:

- Servicio `dnscrypt-proxy` gestionado por una única CLI (`dnscrypt-manager`).
- Redirección DNS real vía `iptables`/`ip6tables` o `nftables`, con cadenas propias e idempotentes.
- Cloudflare, Quad9, AdGuard, Mullvad y NextDNS por Configuration ID.
- Watchdog de arranque con rollback automático si el DNS deja de responder.
- WebUI para KernelSU/KernelSU Next/APatch.
- CLI y botón Acción para Magisk.
- Comandos de emergencia (`panic`, `disable`, `restore-network`).
- Pruebas aisladas de sintaxis, CLI y WebUI.

La primera versión fue probada con éxito en un **Motorola Edge 40 Pro con Android 16**, sin pérdida de Wi‑Fi, red móvil ni conectividad durante las pruebas iniciales.

## Descargar

El módulo instalable se publica en la sección **Releases** del repositorio:

```text
DNSCrypt-Manager-release.zip
DNSCrypt-Manager-release.zip.sha256
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

- `BINARY_INFO.md`: procedencia y validación del binario.
- `AUDIT_REPORT.md`: pruebas, riesgos y limitaciones.
- `CHANGELOG.md`: historial de versiones públicas.

## Agradecimientos

Parte del desarrollo y la auditoría contó con asistencia de herramientas de IA. La autoría, dirección y responsabilidad del proyecto son de **Skaymer AR**.

## Autor

**Skaymer AR**

Proyecto creado y mantenido por Skaymer AR.
