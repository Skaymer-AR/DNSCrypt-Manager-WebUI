# DNSCrypt Manager Android 0.3.4 + módulo v1.1.1-rc8

Esta es una **pre-release candidata**. La versión estable sigue siendo v1.1.0. RC8 no se anuncia como estable hasta completar la prueba física en el Motorola Edge 40 Pro (rtwo/RETAR, Android 16).

## Qué corrige

- La pantalla Actividad podía vencer el límite de lectura de 30 segundos con muchos eventos recientes. El snapshot del módulo ahora serializa los hasta 200 eventos en una sola pasada de `awk`; evita miles de procesos de shell y mantiene el JSON completo, los contadores y el motivo del bloqueo.
- Se conserva la lectura rápida de RC6: no busca cada evento en listas DNS grandes. La clasificación de categorías permanece en las vistas detalladas.
- Los errores de limpieza de temporales siguen quedando registrados en `manager.log`. La app valida los contadores y la ventana completa de eventos; ante timeout, respuesta parcial, JSON inválido o campos ausentes muestra un mensaje breve y permite reintentar, sin reemplazar la lectura por ceros.

## Archivos

- `DNSCrypt-Manager-Android-v0.3.4-debug.apk` — APK Android 0.3.4, versionCode 7, compilación de depuración.
- `DNSCrypt-Manager-v1.1.1-rc8.zip` — módulo instalable, versionCode 11018.
- Cada archivo incluye su SHA-256. El workflow informa si el certificado del APK coincide con RC7 para permitir instalarlo encima.

## Instalación

Actualizá el ZIP del módulo desde KernelSU Next y reiniciá. Después instalá el APK. Si Android rechaza el APK por una firma distinta, desinstalá solo la app e instalá la nueva versión; esto borra los datos privados de la app, pero no desinstala el módulo ni sus ajustes DNS. El APK no actualiza el módulo: instalá ambos archivos.

## Verificación y alcance

La validación incluye sintaxis de shell, pruebas del módulo y de blocklists, serialización de 200 eventos, pruebas JVM de Actividad, compilación Android, comparación de firma y auditoría del ZIP/binario ARM64. Los checks de CI no prueban el dispositivo físico. La instalación y la comprobación de contadores en el Edge 40 Pro siguen pendientes; mantené esta versión como candidata hasta probarla en el teléfono.

La simplificación de la WebUI queda fuera de este parche.
