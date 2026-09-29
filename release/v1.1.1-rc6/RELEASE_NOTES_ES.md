# Big Update — DNSCrypt Manager Android 0.3.2 + módulo v1.1.1-rc6

Esta es una **pre-release candidata**. La versión estable publicada sigue siendo v1.1.0; esta RC6 no la reemplaza.

## Qué corrige

- **Actividad deja de revisar las blocklists por cada consulta.** La vista rápida devuelve juntos los contadores y hasta 200 eventos sin buscar repetidamente en listas que pueden contener millones de dominios. Conserva el dominio, el estado y la regla que produjo el bloqueo.
- **Espera limitada en Android.** Si el módulo no responde, Actividad deja de girar a los 30 segundos y muestra el error para reintentar.
- **Filas más claras.** La app no repite el dominio como si fuera un segundo motivo y muestra “Bloqueada por una regla DNS” cuando la categoría no está disponible. El listado detallado conserva el motivo original.

## Archivos

- `DNSCrypt-Manager-Android-v0.3.2-debug.apk` — app Android 0.3.2, versionCode 5, compilación de depuración.
- `DNSCrypt-Manager-v1.1.1-rc6.zip` — módulo instalable, versionCode 11016.
- Cada archivo incluye su suma SHA-256 para verificar la descarga.

## Instalación de la app

Android puede rechazar el APK debug encima de una instalación firmada con otro certificado. Si aparece ese mensaje, usá un instalador autorizado que permita cambiar la firma, o desinstalá solo la app y después instalá este APK. Desinstalar la app borra su caché privada, pero no desinstala el módulo KernelSU ni elimina sus ajustes DNS. El APK no reemplaza al ZIP del módulo: instalá también RC6 para corregir la lectura lenta de Actividad.

## Verificación y alcance

La candidata debe pasar las pruebas automáticas de sintaxis, CLI, seguridad, WebUI y compilación Android, además de validar el ZIP, las versiones y el binario ARM64 oficial. Esas pruebas no sustituyen la instalación física. La captura del Edge 40 Pro demuestra el problema de carga de RC5; falta comprobar RC6 en ese teléfono antes de considerar el arreglo verificado en hardware.

La futura simplificación de la WebUI para dejar allí principalmente las opciones avanzadas queda fuera de esta actualización.
