# Changelog

## v0.2.0

Capa de protección de navegación sobre v0.1.0. Creada por **Skaymer AR**.

- Blocklists por categoría (malware, phishing, estafas, rastreadores, publicidad, criptominería). Malware/phishing/estafas activas por defecto tras validarse; el resto desactivadas para no romper apps/páginas.
- Actualización verificada de listas (tamaño, SHA-256, sintaxis, `-check` de dnscrypt-proxy) con reemplazo atómico y **rollback automático**. Nunca queda una lista vacía o incompleta activa.
- Allowlist con validación estricta (misma clase en WebUI y CLI; la CLI es la autoridad final).
- Desbloqueo temporal (5m/15m/1h/hasta reiniciar/permanente) con expiración **sin cron** y protección ante cambios de reloj.
- Perfiles de seguridad (equilibrado/estricto/privacidad), aplicación atómica con rollback; el estricto pide confirmación por activar fail-closed.
- Modo **fail-closed opcional** (opt-in): cadenas/tabla propias, idempotente, nunca bloquea loopback ni la recuperación root; desactivable por WebUI/CLI/ADB. **PANIC siempre restaura la red.**
- Detector de fugas DNS (protegido/posible_fuga/no_verificable/conflicto/fallo); no afirma bloquear DoH de navegador si no puede comprobarse. No bloquea el puerto 443 global, no hace MITM, no instala certificados.
- Panel “por qué fue bloqueado” con historial local limitado y rotado (por defecto: solo bloqueos, 3 días, 1000 eventos). Sin telemetría.
- WebUI con 9 secciones nuevas; CLI con ~30 comandos nuevos; migración versionada v0.1.0 → v0.2.0 que conserva proveedor, NextDNS, IPv6, redirección, backups y PANIC.
- Nuevas pruebas: `smoke-test-security.sh` (61 checks) + fixtures; el build exige todas las suites.

La redirección global y el fail-closed permanecen desactivados por defecto.


## v0.1.0

Primera versión pública funcional de **DNSCrypt Manager**, creada por **Skaymer AR**.

- WebUI para KernelSU, KernelSU Next y APatch.
- CLI y botón de Acción para Magisk.
- dnscrypt-proxy oficial ARM64 2.1.17.
- Cloudflare, Quad9, AdGuard, Mullvad y NextDNS.
- Redirección DNS opcional mediante iptables/nftables.
- Watchdog, rollback automático y modo PANIC.
- Probado en Moto Edge 40 Pro con Android 16 sin pérdida de conectividad.

La redirección global permanece desactivada por defecto.
