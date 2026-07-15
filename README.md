# DNSCrypt Manager

**Creado por Skaymer AR**

Módulo root para Android que ejecuta [`dnscrypt-proxy`](https://github.com/DNSCrypt/dnscrypt-proxy) como servicio de sistema, con redirección DNS opcional, WebUI de control, modo seguro anti-bootloop y recuperación por ADB.

Compatible con **KernelSU**, **KernelSU Next**, **APatch** (WebUI completa) y **Magisk** (botón de Acción + CLI, sin WebUI nativa).

---

## Estado del proyecto

**v0.2.0** agrega una capa de protección de navegación sobre la base de v0.1.0.
Cubre:

- Servicio `dnscrypt-proxy` gestionado por una única CLI (`dnscrypt-manager`).
- Redirección DNS real vía `iptables`/`ip6tables` o `nftables`, con cadenas propias e idempotentes.
- Cloudflare, Quad9, AdGuard, Mullvad y NextDNS por Configuration ID.
- **Blocklists por categoría** (malware/phishing/estafas/rastreadores/publicidad/criptominería) con actualización verificada y **rollback automático**.
- **Allowlist**, **desbloqueo temporal** (sin cron) y **perfiles de seguridad** (equilibrado/estricto/privacidad).
- **Modo fail-closed opcional** (opt-in, cadenas propias, idempotente), **detector de fugas DNS** y panel **“por qué fue bloqueado”** con historial local limitado.
- Watchdog de arranque con rollback automático si el DNS deja de responder.
- WebUI para KernelSU/KernelSU Next/APatch; CLI y botón Acción para Magisk.
- Comandos de emergencia (`panic`, `disable`, `restore-network`) — **PANIC siempre restaura la red**.
- Pruebas aisladas de sintaxis, CLI, WebUI y **seguridad**.

Por defecto la **redirección global** y el **fail-closed** vienen **DESACTIVADOS**;
la protección de malware/phishing/estafas se activa **después de que las listas se
validen**. Probado con éxito en un **Motorola Edge 40 Pro con Android 16**, sin
pérdida de Wi‑Fi, red móvil ni conectividad.

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

## Autor

**Skaymer AR**

Proyecto creado y mantenido por Skaymer AR.
