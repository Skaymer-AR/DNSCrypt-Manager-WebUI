# Changelog

## v0.2.0-RC2

Catálogo de blocklists por metadatos y motor genérico de fuentes, sobre la capa de
seguridad de RC1. Creada por **Skaymer AR**. Predeterminados sin cambios: redirect
OFF, fail-closed OFF, transporte directo, controles de servicio OFF, fuentes
externas apagadas, sin descargas en boot.

- **Catálogo por metadatos**: `blocklists.json` canónico + `blocklists.index.tsv`
  (awk en Android; Python solo en dev/CI, generación reproducible con `--check`).
  70 fuentes, 10 familias. Estados upstream honestos:
  `unverified`/`legacy`/`archived`/`broken` — el generador **no** afirma `verified`.
- **Estado runtime separado e inmutabilidad**: `source-status.tsv` en DATA_DIR
  guarda el resultado local (`verified` tras descarga+validación, `download_failed`,
  `validation_failed`, …) sin tocar el catálogo generado; sobrevive a updates del
  módulo; un fallo posterior no destruye la última lista válida.
- **Motor genérico de fuentes**: activar/desactivar, fuentes personalizadas,
  descarga+validación, formatos hosts/domains/**ABP parcial**, compilación por lotes
  (sort/uniq/comm, sin loops por dominio).
- **Pipeline de compilación**: lock atómico, PID validado por `/proc`, lock huérfano
  recuperable, `compile-status`/`compile-cancel`, timeout real, progreso, temporales
  en DATA_DIR, reemplazo atómico + rollback, `nice`/`ionice` sobre el proceso pesado,
  **PANIC cancela la compilación** sin borrar datos. Nunca compila en boot.
- **Redundancias/conflictos** por metadatos (supersedes/contained_by/overlaps/
  conflicto/archivada/rota/ABP/allowlist-neutraliza), una advertencia canónica por
  relación; comparación exacta bajo demanda (`catalog overlap A B`); sin O(N²).
- **Aporte único** por fuente (total/dups internos/ya presentes/único/% redundante)
  en orden canónico, efectivo tras allowlist; guardado aparte del catálogo.
- **Importación BindHosts** (`--dry-run`/`--confirmed`) con detección de duplicados,
  archivadas, rotas, URLs a normalizar, sospechosos y posibles inyecciones.
- **Control de servicio YouTube** (experimental, mejor esfuerzo) con modos temporales
  y estado propio; conflicto con allowlist reportado sin tocar datos del usuario.
- **WebUI RC2**: catálogo con búsqueda/paginación, fuentes personalizadas, BindHosts
  en dos pasos y controles de servicio; argumentos validados y comillados (sin eval).
- **adult_advertising** separado de `adult_content`; mensaje literal si no hay fuente
  dedicada verificable.

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
