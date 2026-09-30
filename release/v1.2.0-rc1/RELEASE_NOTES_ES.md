# DNSCrypt Manager Big Update 1.2.0-rc1

**Candidata pre-release.** La versión estable se mantiene en v1.1.0 hasta
completar la prueba física de esta candidata en el Motorola Edge 40 Pro
(`rtwo`/RETAR, Android 16). Los checks de CI no cuentan como prueba en el
teléfono.

## Cambios

- Actividad usa claves únicas para cada registro de la lista. Las consultas
  repetidas del mismo dominio, resultado y segundo ya no chocan al desplazarse.
- La app Android está traducida al español y al inglés. Sigue el idioma del
  teléfono; Android 13 o posterior permite elegir el idioma en los ajustes de
  la aplicación.
- La WebUI está traducida al español y al inglés, conserva la selección manual
  y elige el idioma del navegador cuando todavía no hay una preferencia guardada.
- Se tradujeron también los mensajes dinámicos de acciones, validaciones y
  registros de eventos.
- Se conservan el snapshot de Actividad de RC8 y su ventana completa de hasta
  200 eventos. La lectura rápida de RC6 evita buscar cada evento en listas DNS
  grandes y conserva la regla del bloqueo.

## Archivos

- `DNSCrypt-Manager-Android-v0.4.0-debug.apk` — Android 0.4.0, versionCode 8.
- `DNSCrypt-Manager-v1.2.0-rc1.zip` — módulo v1.2.0-rc1, versionCode 12001.
- Los dos binarios incluyen sus archivos SHA-256. El workflow compara el
  certificado del APK con el último APK publicado y deja el resultado en su
  resumen.

## Instalación y validación

Instalá el ZIP del módulo y el APK por separado. La candidata se mantiene como
pre-release hasta comprobar en el Motorola que Actividad carga sus registros y
permite desplazarse sin cerrar la app. No se afirma que esta versión esté
instalada ni probada físicamente.

Las pruebas JVM verifican que dos eventos idénticos reciben claves distintas.
CI compila el APK, ejecuta las pruebas del módulo y valida las traducciones. La
compilación no sustituye la prueba física.
