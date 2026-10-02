# DNSCrypt Manager para Android

Aplicación nativa en español e inglés para manejar el módulo DNSCrypt desde el teléfono. Sigue el idioma del sistema; Android 13 o posterior permite elegir el idioma por aplicación. La primera adaptación apunta al Motorola Edge 40 Pro (`rtwo`, Android 16); compatibilidad con otros equipos queda para una etapa posterior.

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
- Agregar o quitar dominios de la allowlist, o elegir desde Actividad entre permitir o bloquear manualmente un dominio.
- Elegir Cloudflare, Quad9, AdGuard, Mullvad o un perfil NextDNS y reiniciar el proxy para aplicar el cambio.
- Revisar qué contiene una copia antes de restaurarla. La actividad DNS no se incluye.

La interfaz usa Kotlin, Jetpack Compose y Material 3. El puente root ejecuta únicamente operaciones concretas y validadas del CLI `dnscrypt-manager`; no acepta comandos escritos libremente.

Al iniciar, la app consulta primero el estado del módulo y carga la actividad local en segundo plano. Si KernelSU Next solicita acceso root, hay que aprobarlo; si una orden no responde, la app muestra un diagnóstico y permite reintentar. La lectura de actividad tiene un límite de 30 segundos; si vence, el aviso permite volver a intentarlo.

Actividad lee eventos y contadores juntos. El camino rápido conserva dominio, estado y regla sin buscar cada fila en las listas, que pueden tener millones de entradas. Ante un error conserva los datos anteriores y los distingue de una lectura válida sin consultas. El diagnóstico ejecuta una prueba DNS real; si esa prueba falla, el módulo intenta restaurar el estado de red.

## Límites actuales

- La actividad es de consultas DNS. No muestra conexiones TCP/UDP completas ni identifica de forma confiable qué aplicación originó cada consulta. `Error` significa que el resolver devolvió un código DNS distinto de `NOERROR`; el código concreto se conserva como `return_code` en el JSON exportado. Tocar una fila permite elegir entre permitir el dominio o bloquearlo manualmente.
- El firewall bloquea toda la red de una app seleccionada; no filtra dominios ni identifica qué app originó una consulta DNS. Solo se habilita con soporte confirmado para IPv4 e IPv6.
- Para mostrar el selector local, Android permite consultar los paquetes instalados. La lista y sus nombres se procesan en el teléfono y no se envían a un servidor.
- Los perfiles de seguridad, el rollback de listas y la validación avanzada siguen disponibles en la WebUI del módulo; todavía no tienen controles nativos propios.
- Cambiar resolver reinicia `dnscrypt-proxy` y puede pausar la conectividad unos segundos.
- El diagnóstico no identifica qué aplicación inició cada consulta DNS; el firewall sigue siendo un control de tráfico completo por app.
- La confirmación física disponible cubre la carga de Actividad y la navegación por Listas y Ajustes en el Motorola Edge 40 Pro. No representa una validación exhaustiva del permiso root, firewall, cambio de resolver, hotspot ni otros dispositivos.

## Build y evidencia

La versión estable Android 0.4.3 (versionCode 11) y módulo v1.2.1 (versionCode 12004) agrega el escudo verde menta como icono y las reglas manuales Permitir/Bloquear desde Actividad. Bloquear quita el permiso permanente y la excepción temporal del mismo dominio. Permitir quita su bloqueo manual. Si falla la aplicación de la regla, el módulo restaura las entradas anteriores. El usuario informó que probó la entrega y solicitó publicarla como estable.

La entrega v1.2.1 se compiló con JDK 17, Gradle 8.9 y Android SDK 35. Se comprobaron compilación, firma y alineación del APK, sintaxis de los scripts modificados e integridad y estructura del ZIP; no se ejecutaron pruebas funcionales automáticas durante esa compilación. La publicación conserva exactamente los archivos entregados al usuario. La firma del APK 0.4.3 difiere de la del APK 0.4.2 anterior: para pasar desde ese APK hay que desinstalar solo la app. Esto borra los datos privados de la app y conserva el módulo y su configuración DNS. El workflow de GitHub sigue disponible para las comprobaciones automáticas de cambios futuros.

El APK no actualiza el módulo: instalá el APK y el ZIP actualizado por separado. Permitir o bloquear manualmente desde Actividad requiere que el módulo incluya el comando catalog domain-rule. Verificá los SHA-256 de los dos archivos.
