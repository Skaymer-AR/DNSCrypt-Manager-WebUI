# DNSCrypt Manager Big Update 1.2.0-rc1

**Candidata pre-release / Pre-release candidate.**

La versión estable sigue en v1.1.0 hasta completar la prueba física en el Motorola Edge 40 Pro (`rtwo`/RETAR, Android 16). Los checks de CI no cuentan como prueba en el teléfono.

Stable remains v1.1.0 until this candidate is physically tested on the Motorola Edge 40 Pro (`rtwo`/RETAR, Android 16). CI checks do not count as a phone test.

## Cambios / Changes

- Actividad asigna una clave única a cada fila. Consultas repetidas con el mismo dominio, resultado y segundo ya no chocan al desplazarse.
- Activity gives every row a unique key. Repeated queries with the same domain, result, and second no longer collide while scrolling.
- La app Android está traducida al español y al inglés, sigue el idioma del teléfono y permite selección por aplicación en Android 13 o posterior.
- The Android app is available in Spanish and English, follows the phone's language, and supports per-app language selection on Android 13 or later.
- La WebUI está traducida al español y al inglés, conserva la selección manual y sigue el idioma del navegador cuando no hay preferencia guardada.
- The WebUI is available in Spanish and English, keeps the manual choice, and follows the browser language when no preference is saved.
- Se conservan el snapshot de Actividad de RC8, su ventana completa de hasta 200 eventos y la lectura rápida de RC6, que evita búsquedas en listas DNS grandes y mantiene la regla del bloqueo.
- The RC8 Activity snapshot, its complete window of up to 200 events, and the RC6 fast path remain. The fast path avoids searches through large DNS lists and keeps the blocking rule.

## Archivos / Files

- `DNSCrypt-Manager-Android-v0.4.0-debug.apk` — Android 0.4.0, versionCode 8.
- `DNSCrypt-Manager-v1.2.0-rc1.zip` — module v1.2.0-rc1, versionCode 12001.
- Los dos binarios incluyen archivos SHA-256. El workflow compara la firma del APK con la última publicación / Both binaries include SHA-256 files. The workflow compares the APK signing certificate with the latest release.

## Prueba física / Physical test

La candidata seguirá como pre-release hasta probar Actividad en el Motorola. No se afirma que esté instalada ni probada en el teléfono.

This remains a pre-release until Activity is tested on the Motorola. It is not claimed to be installed or tested on the phone.
