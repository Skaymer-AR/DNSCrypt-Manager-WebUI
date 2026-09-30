# DNSCrypt Manager Big Update v1.2.0 — versión estable

v1.2.0 es la versión estable del módulo DNSCrypt Manager y de su aplicación
Android. La candidata RC2 se promueve después de que el usuario confirmara en
su Motorola Edge 40 Pro que Actividad carga los contadores y que Listas y
Ajustes volvieron a abrir con fluidez.

## Cambios

- Actividad procesa el snapshot completo en una pasada, valida el JSON y
  conserva contadores y eventos aun si falla una limpieza temporal posterior.
- La lectura rápida evita buscar cada consulta en listas que pueden tener
  millones de dominios; mantiene la regla de bloqueo y el detalle donde aplica.
- El desplazamiento de Actividad usa una lista perezosa para evitar cierres al
  recorrer los registros.
- Listas conserva los datos ya cargados; Ajustes crea las secciones bajo
  demanda. El parseo y las consultas de progreso no bloquean la interfaz.
- La aplicación Android y la WebUI ofrecen interfaz en español e inglés.
- El estado `Error` indica un código de respuesta DNS distinto de `NOERROR`;
  no significa por sí solo que el dominio haya sido bloqueado. Exportá la
  Actividad como JSON y consultá `return_code` para ver el código concreto.

## Versiones

- App Android: **0.4.2**, versionCode **10** (APK de depuración).
- Módulo: **v1.2.0**, versionCode **12003**.

## Instalación

Instalá el ZIP del módulo como actualización desde KernelSU Next y luego
instalá el APK Android por separado. Revisá el resumen de GitHub Actions para
confirmar si la firma permite actualizar directamente la app RC2. Si Android
rechaza la firma, desinstalá solo la app antes de instalar el APK nuevo; eso
borra los datos privados de la app, pero no desinstala el módulo ni borra sus
ajustes DNS. Verificá cada descarga con el SHA-256 adjunto a esta release.

## Validación

Los checks de CI validan los recursos en español e inglés, las pruebas JVM, la
compilación Android, el módulo, el ZIP y los checksums. La comprobación física
reportada por el usuario cubre la carga de Actividad y la navegación por Listas
y Ajustes en su Motorola Edge 40 Pro. No se afirma una validación exhaustiva de
todas las funciones, redes o dispositivos.
