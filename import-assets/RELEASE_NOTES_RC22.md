# DNSCrypt Manager v0.2.0-RC2.2 — preliminar

> **Versión de prueba. No es estable.** La primera versión estable del proyecto será v1.0.0 después de completar las pruebas reales en Android.

## Advertencias obligatorias

- **No uses el ZIP original de v0.2.0-RC2:** quedó descartado porque la WebUI podía no encontrar la CLI systemless.
- **BindHosts debe permanecer desactivado.** Desactivalo, reiniciá el dispositivo y recién entonces instalá o habilitá DNSCrypt Manager. Usar ambos módulos simultáneamente puede causar superposición de reglas, pérdida de conectividad o bootloop.
- En KernelSU Next, la WebUI puede requerir **Hybrid Mount habilitado y un reinicio**.

## Cambios principales

- Diagnóstico de entorno y Hybrid Mount.
- CoinBlockerLists marcada como rota por 404 permanente.
- NoCoin agregada como reemplazo preliminar.
- Firebog/EasyPrivacy marcada como legacy/degradada.
- Phishing Army se conserva: el fallo observado era DNS, no una URL 404.
- Fuentes `broken` y `archived` ya no se vuelven a descargar automáticamente.
- Catálogo ampliado a 71 fuentes.

## Pendiente

La resolución bootstrap, `source doctor`, la clasificación completa de errores de descarga y la auditoría DNS multiseñal siguen pendientes. Esta compilación se publica para pruebas y trazabilidad, no como solución definitiva.
