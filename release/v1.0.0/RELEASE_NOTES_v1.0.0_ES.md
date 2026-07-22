# DNSCrypt Manager v1.0.0 — Notas de versión (ES)

**Primera versión estable.** El alcance se redujo a propósito a lo que está
implementado, probado y realmente en uso: se retiró lo experimental en vez de
etiquetarlo como estable.

- `version=v1.0.0` · `versionCode=10000` · mismo module ID (`dnscrypt_manager`).
- Se instala encima de v0.3.0-RC1 / RC2.x **conservando configuración y datos**.

## Qué incluye v1.0.0
- **DNSCrypt / DoH / NextDNS** con proveedores preestablecidos.
- **Redirección DNS** opcional y **fail-closed**.
- **IPv4 estable**; Wi-Fi, datos móviles y hotspot, con cambio de red sin perder DNS.
- **Listas**: catálogo por metadatos, compilación por lotes, allowlist, blacklist,
  **permitir temporalmente**, perfiles y protección por categorías.
- **Importación de listas de BindHosts**.
- **Privacidad por servicio**: 9 controles reales sobre el backend `service-control`,
  con enforcement verificado (sus dominios entran de verdad a la lista compilada),
  modos `off/15m/1h/until_reboot/permanent`, expiración y aviso de conflicto con la
  allowlist. Todos **OFF** en una instalación limpia.
- **Eventos bajo demanda** (ver más abajo).
- **PANIC** y recuperación; rollback y last-known-good; locks, timeouts y cancelación.
- **KernelSU Next + Hybrid Mount** (resolvedor central de CLI con 3 rutas permitidas).

## Cambios destacados
### BindHosts: ya no se pide desactivarlo
Se eliminó por completo la advertencia que decía que BindHosts era incompatible o que
podía cortar la conectividad o provocar bootloop. **No se bloquea, no se exige
desactivarlo y no hay alerta roja.**

Registro honesto: el usuario usó **DNSCrypt Manager y BindHosts al mismo tiempo
durante una semana** en un **Motorola Edge 40 Pro (Android 16, KernelSU Next, Hybrid
Mount, SELinux Enforcing)**, con Wi-Fi, datos móviles y hotspot, **sin pérdida de DNS,
sin pérdida de conectividad y sin bootloop**. Es una **prueba física confirmada por el
usuario**, no una garantía de compatibilidad universal en cualquier dispositivo o
versión. Nota práctica: ambos filtran por su cuenta; si un dominio aparece bloqueado y
no está en tus listas, revisá también BindHosts.

### Eventos: carga diferida y colapsable
Antes la lista de Eventos se cargaba durante la inicialización general y podía trabar
la WebUI incluso sin entrar a Actividad. Ahora:
- al arrancar la WebUI **no** se ejecuta `events list` ni `events stats`, no se crean
  filas ni se consulta el historial en segundo plano;
- en Actividad aparece solo una cabecera compacta **cerrada**;
- al expandir: "Cargando eventos…", **una sola** consulta y como máximo **20 filas**,
  con **Cargar más** si hay más resultados;
- al cerrar: la lista se **desmonta del DOM**, se ignoran respuestas tardías y no se
  vuelve a consultar. Siguen disponibles Actualizar, Estadísticas, Borrar historial,
  Permitir 5m/1h, Allowlist y Copiar.

### Se retiró lo experimental o incompleto
- **Anonymized DNSCrypt y ODoH**: fuera del alcance estable. Se eliminaron sus
  tarjetas, botones, entradas, carga de estado, polling y textos EN/ES; tampoco se
  inicializan. v1.0.0 **no** los promete. El código queda interno y marcado como
  experimental, sin exponer.
- **Tarjeta heredada "Controles de servicio"** (motor RC2 `service`), que aparecía
  vacía y duplicaba la sección real: eliminada por completo.
- Se quitaron las leyendas "esta versión continúa en pruebas" y "la primera versión
  estable será v1.0.0".

## Limitaciones reales (sin promesas exageradas)
- Es un **filtro y gestor DNS**: no es una VPN, no hace MITM, no instala CA y no
  inspecciona HTTPS. No aplica filtros cosméticos.
- El bloqueo de anuncios por DNS es **best-effort**; no bloquea todo (por ejemplo, los
  anuncios servidos desde los mismos dominios que el contenido).
- **IPv6** depende de la red y no fue validado exhaustivamente; el uso estable
  confirmado es con **IPv4 forzado**.
- Las políticas por aplicación (`app-policy`) **no** tienen enforcement: quedan
  registradas, sin exponer y sin crear reglas de firewall.
- Pendientes documentados, sin datos inventados: rollback físico forzando un fallo
  grave, consumo prolongado de batería y de RAM.
- Los resultados en Linux/x86 **no** equivalen a Android; ver
  `ANDROID_USER_VALIDATION_v1.0.0.md`.

## Actualización
Instalá el ZIP encima de la versión anterior (mismo module ID). La migración de schema
es **idempotente y con backup**: conserva configuración, redirect, fail-closed, listas,
allowlist, blacklist, fuentes personalizadas, perfiles, excepciones, historial dentro de
la retención, el control de YouTube y el idioma elegido. No se descargan listas durante
el arranque.
