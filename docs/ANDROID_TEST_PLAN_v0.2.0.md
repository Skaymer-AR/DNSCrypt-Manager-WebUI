# Plan de pruebas en Android — DNSCrypt Manager v0.2.0-RC2

Lo que **no** pudo probarse fuera de Android y debe validarse en el dispositivo
(Motorola Edge 40 Pro, Android 16 / API 36, KernelSU/KernelSU Next/APatch/Magisk,
Zygisk Next, LSPosed). Las cifras de escala del entorno de desarrollo son de Linux
y **no** predicen el rendimiento en Android.

## 1. Instalación y arranque
- [ ] Flashear el ZIP en KernelSU, KernelSU Next, APatch y Magisk.
- [ ] Migración desde v0.1.0 conserva config; se crean `catalog/`, `enabled.txt`,
      `custom.tsv`, `blacklist.txt`, `source-status.tsv`, índices sincronizados.
- [ ] Boot: **no** hay descarga ni recompilación; se usa la última lista; fallback
      seguro si no existe.
- [ ] SELinux **enforcing**; contextos correctos (`chcon`) en ROM stock.

## 2. Catálogo y compilación real
- [ ] `catalog update <id>` sobre fuentes reales (HTTPS): descarga+validación,
      `source-status.tsv` pasa a `verified`, `last_success` correcto.
- [ ] `catalog compile` con varias fuentes grandes: medir **tiempo real**, uso de
      memoria y espacio; confirmar reemplazo atómico y recarga de dnscrypt-proxy.
- [ ] `nice`/`ionice` efectivos en el dispositivo (toolbox/busybox).
- [ ] Fuentes multimillonarias: confirmar comportamiento y decidir límites de UX.

## 3. Pipeline end-to-end (a escala real, NO probado a 2.5M en dev)
- [ ] `compile-cancel` cancela y no deja hijos ni temporales.
- [ ] Timeout real corta una compilación larga.
- [ ] Lock concurrente y **lock huérfano** (reinicio a mitad de compilación).
- [ ] **Rollback**: si dnscrypt-proxy rechaza la nueva config, se restaura la previa.
- [ ] Poco espacio real aborta sin corromper la lista vigente.

## 4. Redirección y transporte
- [ ] `redirect` OFF por defecto; activarlo redirige :53; netfilter correcto.
- [ ] Verificar reglas iptables/nftables sin tocar cadenas ajenas.
- [ ] `-version` del binario oficial ARM64; transporte directo por defecto.

## 5. BindHosts
- [ ] Importar un BindHosts real (dry-run → aplicar); verificar buckets y atomicidad.

## 6. Controles de servicio (YouTube)
- [ ] `service set youtube_no_history` en cada modo; **expiración temporal por
      reloj**; `boot` desaparece tras reiniciar; `perm` persiste.
- [ ] Conflicto con allowlist se reporta; datos del usuario intactos.
- [ ] Comprobar empíricamente el efecto de bloquear `s.youtube.com` (mejor esfuerzo).

## 7. PANIC y seguridad
- [ ] PANIC durante una compilación: cancela, libera lock, restaura red y **no**
      borra catálogos/fuentes/config.
- [ ] fail-open por defecto; fail-closed opt-in.
- [ ] WebUI: catálogo, fuentes personalizadas, BindHosts (2 pasos) y servicios
      funcionan vía el puente ksu; validación de argumentos efectiva.

## 8. KernelSU Next / WebView
- [ ] Cargar la WebUI en KernelSU Next; confirmar `ksu.exec` y render.
