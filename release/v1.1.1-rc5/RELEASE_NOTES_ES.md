# Big Update — DNSCrypt Manager Android 0.3.1 + módulo v1.1.1-rc5

Esta es una **pre-release candidata**. La versión estable publicada sigue siendo v1.1.0; la RC5 no la reemplaza.

## Qué trae esta actualización

- **Inicio con diagnóstico claro:** separa el estado del módulo, `dnscrypt-proxy`, la redirección, una consulta DNS real, las listas y la compatibilidad del firewall.
- **Actividad DNS más confiable:** carga contadores y consultas juntas; si falla una lectura, conserva los últimos datos y muestra el error para reintentar en lugar de mostrar ceros falsos. Permite gestionar excepciones, elegir retención local y exportar hasta 200 eventos.
- **Firewall por aplicación:** bloqueos temporales con vencimiento visible, perfiles guardados y restauración de reglas vigentes al reiniciar. Se habilita solo si el teléfono confirma compatibilidad con IPv4 e IPv6.
- **Conexiones en vivo:** muestra una lectura puntual de sockets TCP/UDP agrupados por app; no conserva un historial ni atribuye consultas DNS a aplicaciones.
- **Copias más seguras:** muestra el contenido antes de restaurar, valida rutas y tipos de archivo, y reemplaza las preferencias incluidas. El historial DNS permanece en el teléfono y no se agrega a la copia.
- **Listas por categoría:** permite activar fuentes ya preparadas sin iniciar descargas ocultas; conserva la selección anterior si falla la compilación.
- **Interfaz nativa en español**, con acciones root validadas a través del CLI del módulo.

## Archivos

- `DNSCrypt-Manager-Android-v0.3.1-debug.apk` — app Android 0.3.1, versionCode 4, compilación de depuración.
- `DNSCrypt-Manager-v1.1.1-rc5.zip` — módulo instalable, versionCode 11015.
- Cada archivo incluye su suma SHA-256 para comprobar integridad.

## Verificación y alcance

GitHub Actions aprobó las pruebas de sintaxis, CLI, seguridad, WebUI, firewall por UID, conexiones, copias, listas y compilación del APK. También validó el ZIP, la versión interna y el binario ARM64 oficial. Estas pruebas automatizadas no sustituyen la instalación y prueba en el Motorola Edge 40 Pro con Android 16; esa validación física sigue pendiente, por eso esta versión permanece como candidata.

Como posible etapa futura, la WebUI podría quedar enfocada en opciones avanzadas y el uso cotidiano concentrarse más en la app. Ese rediseño no forma parte de esta actualización.
