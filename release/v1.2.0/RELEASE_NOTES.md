# DNSCrypt Manager Big Update v1.2.0 — estable / stable

## Español

La v1.2.0 es la versión estable del módulo y la app Android. El usuario
confirmó en su Motorola Edge 40 Pro que Actividad carga los contadores y que
Listas y Ajustes vuelven a abrir con fluidez.

- Actividad valida y procesa su snapshot completo en una pasada; una limpieza
  temporal posterior fallida no descarta datos válidos.
- El camino rápido evita buscar cada consulta en listas de millones de dominios
  y conserva la regla de bloqueo en las vistas detalladas.
- El desplazamiento de Actividad usa una lista perezosa; Listas conserva los
  datos cargados y Ajustes carga secciones bajo demanda.
- La app Android y la WebUI están disponibles en español e inglés.
- `Error` significa que la respuesta DNS no fue `NOERROR`; no implica por sí
  solo que la lista de bloqueo haya detenido el dominio. Exportá la Actividad y
  revisá `return_code` para obtener el código concreto.

Versiones: app Android 0.4.2 (versionCode 10); módulo v1.2.0 (versionCode
12003). CI valida los recursos ES/EN, pruebas JVM, compilación Android, módulo,
ZIP y checksums. La prueba física comunicada cubre Actividad, Listas y Ajustes
en el Motorola; no representa una validación exhaustiva de todas las funciones
ni de otros dispositivos.

Instalá el ZIP del módulo y el APK por separado. Revisá en el resumen de CI si
la firma permite actualizar la app RC2; si no, desinstalá solo la app antes de
instalar el APK nuevo. Eso no elimina el módulo ni sus ajustes DNS. Verificá
cada archivo con el SHA-256 adjunto.

## English

v1.2.0 is the stable release of the module and Android app. The user confirmed
on their Motorola Edge 40 Pro that Activity loads its counters and Lists and
Settings open smoothly again.

- Activity validates and processes the complete snapshot in one pass; a later
  temporary-file cleanup failure does not discard valid data.
- The fast path avoids searching million-domain lists for each query and keeps
  the blocking rule in detailed views.
- Activity uses a lazy list while scrolling; Lists retains loaded data and
  Settings loads sections on demand.
- The Android app and WebUI are available in Spanish and English.
- `Error` means the DNS response was not `NOERROR`; it does not alone mean that
  a blocklist stopped the domain. Export Activity and inspect `return_code` for
  the specific response code.

Versions: Android app 0.4.2 (versionCode 10); module v1.2.0 (versionCode
12003). CI validates ES/EN resources, JVM tests, the Android build, module,
ZIP, and checksums. The reported physical test covers Activity, Lists, and
Settings on the Motorola; it does not claim exhaustive validation of every
feature or device.

Install the module ZIP and APK separately. Check the CI summary to see whether
the signing certificate allows updating the RC2 app; if not, uninstall only the
app before installing the new APK. This does not remove the module or its DNS
settings. Verify each file with its attached SHA-256.
