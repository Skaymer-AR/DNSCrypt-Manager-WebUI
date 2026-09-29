# DNSCrypt Manager para Android

Aplicación nativa en español para manejar el módulo DNSCrypt desde el teléfono. La primera adaptación apunta al Motorola Edge 40 Pro (`rtwo`, Android 16); compatibilidad con otros equipos queda para una etapa posterior.

## Qué se puede hacer

- Ver si `dnscrypt-proxy` escucha y si la redirección DNS está activa.
- Consultar las estadísticas y los eventos DNS locales cuando la versión del módulo ofrece esa función.
- Ejecutar un diagnóstico guiado de módulo, proxy, redirección, prueba DNS, listas y soporte del firewall.
- Revisar las apps instaladas y bloquear o permitir su tráfico de internet con el firewall por UID, si el teléfono confirma soporte IPv4 e IPv6.
- Activar o pausar el registro local; empieza apagado.
- Explorar el catálogo real por categorías, buscar y filtrar fuentes activas o recomendadas.
- Activar o desactivar una fuente con confirmación antes de cambiar el filtrado.
- Activar de una vez las fuentes ya preparadas de una categoría; lo que no tenga caché queda apagado y no se descarga en segundo plano.
- Preparar las cachés de todas las fuentes sin activarlas automáticamente y ver el progreso.
- Agregar o quitar dominios de la allowlist.
- Elegir Cloudflare, Quad9, AdGuard, Mullvad o un perfil NextDNS y reiniciar el proxy para aplicar el cambio.
- Revisar qué contiene una copia antes de restaurarla. La actividad DNS no se incluye.

La interfaz usa Kotlin, Jetpack Compose y Material 3. El puente root ejecuta únicamente operaciones concretas y validadas del CLI `dnscrypt-manager`; no acepta comandos escritos libremente.

Al iniciar, la app consulta primero el estado del módulo y carga la actividad local en segundo plano. Si KernelSU Next solicita acceso root, hay que aprobarlo; si una orden no responde, la app muestra un diagnóstico y permite reintentar. La lectura de actividad tiene un límite de 30 segundos; si vence, el aviso permite volver a intentarlo.

Actividad lee eventos y contadores juntos. El camino rápido conserva dominio, estado y regla sin buscar cada fila en las listas, que pueden tener millones de entradas. Ante un error conserva los datos anteriores y los distingue de una lectura válida sin consultas. El diagnóstico ejecuta una prueba DNS real; si esa prueba falla, el módulo intenta restaurar el estado de red.

## Límites actuales

- La actividad es de consultas DNS. No muestra conexiones TCP/UDP completas ni identifica de forma confiable qué aplicación originó cada consulta.
- El firewall bloquea toda la red de una app seleccionada; no filtra dominios ni identifica qué app originó una consulta DNS. Solo se habilita con soporte confirmado para IPv4 e IPv6.
- Para mostrar el selector local, Android permite consultar los paquetes instalados. La lista y sus nombres se procesan en el teléfono y no se envían a un servidor.
- Los perfiles de seguridad, el rollback de listas y la validación avanzada siguen disponibles en la WebUI del módulo; todavía no tienen controles nativos propios.
- Cambiar resolver reinicia `dnscrypt-proxy` y puede pausar la conectividad unos segundos.
- El diagnóstico no identifica qué aplicación inició cada consulta DNS; el firewall sigue siendo un control de tráfico completo por app.
- Compilar el APK no prueba que funcione en el Motorola. La primera instalación física debe comprobar permiso root, lectura del módulo, actividad, catálogo, allowlist, firewall por Wi‑Fi y datos, cambio de resolver y conectividad por hotspot.

## Build y evidencia

El workflow `Build DNSCrypt Manager Android app` usa JDK 17, Gradle 8.9 y Android SDK 35. En cada PR compila el APK `debug` y ejecuta el gate completo del módulo. Al integrar esta candidata en `main`, publica una pre-release de GitHub con el APK Android 0.3.2, el ZIP del módulo v1.1.1-rc6 y sus SHA-256. Esta publicación sigue siendo candidata: la prueba física del arreglo en el Edge 40 Pro todavía está pendiente y no se marca como versión estable. El certificado del APK debug puede cambiar entre ejecuciones; si Android no acepta la actualización por la firma, seguí las opciones de instalación de las notas de release.

Para cada commit, confirmar que el build Android del workflow haya terminado correctamente. La instalación y la prueba física en el Edge 40 Pro siguen pendientes. El APK no actualiza el módulo: revisar su versión y SHA-256 por separado antes de instalar una candidata.
