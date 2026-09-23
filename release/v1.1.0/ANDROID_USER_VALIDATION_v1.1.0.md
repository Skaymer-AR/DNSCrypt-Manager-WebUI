# Validación en Android real — DNSCrypt Manager v1.1.0

El usuario informa que probó la RC10, cuyo código funcional se publica como
v1.1.0 estable. Esta tabla registra esa validación física; no es una prueba
independiente del equipo de desarrollo.

**Dispositivo:** Motorola Edge 40 Pro (`rtwo`) · **Android 16 / API 36** ·
**ARM64** · **KernelSU Next** · **Hybrid Mount** · ROM stock.

| Caso | Resultado reportado |
|---|---|
| Instalación y servicio DNSCrypt | funciona |
| WebUI y navegación del catálogo de fuentes | probado |
| Wi-Fi | funciona |
| Datos móviles | funciona |
| Hotspot | funciona |
| Cambios entre Wi-Fi, datos y hotspot | probado sin perder el servicio DNSCrypt |
| Persistencia tras reinicio/actualización | probada |
| IPv4 forzado | probado |
| Descarga y uso de fuentes de bloqueo de la RC10 | probados por el usuario |
| Tiempo exacto para descargar todas las fuentes | no se registró una medición reproducible |

### Rendimiento de las descargas

El usuario reportó que una descarga grande puede volver lenta o aparentemente
congelar la WebUI. La RC10 añade concurrencia limitada, menor prioridad de CPU y
actualización única del manifiesto; la suite local verifica ese comportamiento
con fixtures. No hay una medición publicada del tiempo real de todos los feeds,
del uso máximo de RAM ni del impacto en resolución DNS durante una descarga en
el Motorola.

### IPv6

IPv6 **no fue validado exhaustivamente** en todas las redes y escenarios. La
validación estable reportada utiliza IPv4 forzado; no se afirma que IPv6 esté
roto universalmente.

Esta validación corresponde a un dispositivo y configuración concretos. No
garantiza compatibilidad universal con otros teléfonos, ROM, kernels o versiones
de Android.
