# Big Update — DNSCrypt Manager Android 0.3.3 + módulo v1.1.1-rc7

Esta es una **pre-release candidata**. La versión estable publicada sigue siendo v1.1.0; esta RC7 no la reemplaza.

## Qué corrige

- **Actividad aprovecha el conteo que el módulo ya entrega.** RC6 aceleró el snapshot, pero en algunos teléfonos el comando podía terminar con un código de error después de haber generado JSON válido. La app lo descartaba y mostraba el JSON entero en una tarjeta roja. RC7 trata como válida una respuesta completa con contadores y eventos, y el módulo ya no informa como fallo una limpieza temporal secundaria.
- **Errores más claros.** Si la respuesta está incompleta o dañada, la app muestra una explicación breve y una opción para reintentar, sin volcar cientos de eventos en pantalla.
- **Lectura rápida con listas grandes.** Conserva contadores, dominio, estado y regla sin recorrer las blocklists por cada fila. La fila tampoco repite el dominio como segundo motivo.

## Archivos

- `DNSCrypt-Manager-Android-v0.3.3-debug.apk` — app Android 0.3.3, versionCode 6, compilación de depuración.
- `DNSCrypt-Manager-v1.1.1-rc7.zip` — módulo instalable, versionCode 11017.
- Cada archivo incluye su suma SHA-256 para verificar la descarga.

## Instalación

Actualizá el ZIP del módulo desde KernelSU/KernelSU Next y reiniciá. Después instalá el APK. Android puede rechazar el APK debug encima de otra firma; si aparece ese mensaje, usá un instalador autorizado que permita el cambio de firma o desinstalá solo la app y volvé a instalarla. Esa alternativa borra la caché privada de la app, pero no desinstala el módulo ni elimina sus ajustes DNS. El APK solo no corrige el código del módulo: instalá ambos archivos.

## Verificación y alcance

La candidata debe pasar las pruebas automáticas de sintaxis, CLI, seguridad, WebUI, compilación Android y auditoría del ZIP/binario ARM64. La instalación y prueba en el Edge 40 Pro siguen pendientes; no se considera validada en hardware hasta comprobar que Actividad carga los contadores en ese teléfono.

La futura simplificación de la WebUI para dejar allí principalmente las opciones avanzadas queda fuera de esta actualización.
