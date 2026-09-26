# DNSCrypt Manager para Android

Aplicación nativa en español para manejar el módulo DNSCrypt desde el teléfono. La primera adaptación apunta al Motorola Edge 40 Pro (`rtwo`, Android 16); compatibilidad con otros equipos queda para una etapa posterior.

## Qué se puede hacer

- Ver si `dnscrypt-proxy` escucha y si la redirección DNS está activa.
- Consultar las estadísticas y los eventos DNS locales cuando la versión del módulo ofrece esa función.
- Revisar las apps instaladas y bloquear o permitir su tráfico de internet con el firewall por UID, si el teléfono confirma soporte IPv4 e IPv6.
- Activar o pausar el registro local; empieza apagado.
- Explorar el catálogo real por categorías, buscar y filtrar fuentes activas o recomendadas.
- Activar o desactivar una fuente con confirmación antes de cambiar el filtrado.
- Preparar las cachés de todas las fuentes sin activarlas automáticamente y ver el progreso.
- Agregar o quitar dominios de la allowlist.
- Elegir Cloudflare, Quad9, AdGuard, Mullvad o un perfil NextDNS y reiniciar el proxy para aplicar el cambio.

La interfaz usa Kotlin, Jetpack Compose y Material 3. El puente root ejecuta únicamente operaciones concretas y validadas del CLI `dnscrypt-manager`; no acepta comandos escritos libremente.

Al iniciar, la app consulta primero el estado del módulo y carga la actividad local en segundo plano. Si KernelSU Next solicita acceso root, hay que aprobarlo; si una orden no responde, la app muestra un diagnóstico y permite reintentar.

## Límites actuales

- La actividad es de consultas DNS. No muestra conexiones TCP/UDP completas ni identifica de forma confiable qué aplicación originó cada consulta.
- El firewall bloquea toda la red de una app seleccionada; no filtra dominios ni identifica qué app originó una consulta DNS. Solo se habilita con soporte confirmado para IPv4 e IPv6.
- Para mostrar el selector local, Android permite consultar los paquetes instalados. La lista y sus nombres se procesan en el teléfono y no se envían a un servidor.
- Los perfiles de seguridad, el rollback de listas y la validación avanzada siguen disponibles en la WebUI del módulo; todavía no tienen controles nativos propios.
- Cambiar resolver reinicia `dnscrypt-proxy` y puede pausar la conectividad unos segundos.
- Compilar el APK no prueba que funcione en el Motorola. La primera instalación física debe comprobar permiso root, lectura del módulo, actividad, catálogo, allowlist, firewall por Wi‑Fi y datos, cambio de resolver y conectividad por hotspot.

## Build y evidencia

El workflow `Build DNSCrypt Manager Android app` usa JDK 17, Gradle 8.9 y Android SDK 35. Produce un APK `debug` y su SHA-256 como artefacto de GitHub Actions; el artefacto es temporal, no una release estable. El mismo workflow ejecuta por separado el gate y empaquetado de la candidata del módulo, sin incluir `android-app/` dentro de su ZIP.

Para cada commit, confirmar que el build Android del workflow haya terminado correctamente. La instalación y la prueba física en el Edge 40 Pro siguen pendientes. El APK no actualiza el módulo: revisar su versión y SHA-256 por separado antes de instalar una candidata.
