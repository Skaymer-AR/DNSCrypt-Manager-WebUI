# DNSCrypt Manager Big Update 1.2.0 RC2

Esta candidata corrige la demora y los tirones reportados al abrir Listas y Ajustes en Android.

## Cambios

- Listas conserva en memoria el catálogo ya leído, evita repetir consultas al módulo cada vez que se vuelve a la pantalla y calcula los resultados del filtro una sola vez por cambio.
- El parseo de la Actividad, el catálogo, el progreso de descarga y la allowlist se ejecuta fuera del hilo de interfaz. Las consultas de progreso no se solapan.
- Ajustes carga de forma perezosa sus secciones para mostrar antes el contenido inicial.
- Conserva la traducción español/inglés y la corrección del desplazamiento de Actividad de RC1.

## Versiones

- App Android: 0.4.1, versionCode 9.
- Módulo: v1.2.0-rc2, versionCode 12002.
- La versión estable sigue siendo v1.1.0. Esta pre-release requiere probar la navegación en el Motorola Edge 40 Pro antes de declararla estable.

El workflow compara la firma del APK con la versión 0.4.0 de RC1. El resumen de GitHub Actions confirma si Android permite instalarla encima; si las firmas no coinciden, hay que desinstalar solo la app antes de instalar el APK nuevo. El módulo y su configuración se mantienen separados.
