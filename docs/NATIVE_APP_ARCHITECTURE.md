# DNSCrypt Manager: aplicación nativa

Estado del diseño al 25/09/2026. La app nativa se desarrolla primero para el Motorola Edge 40 Pro `rtwo` con Android 16. Compatibilidad genérica con otros teléfonos queda para después de la prueba física.

## Arquitectura

```text
App Android (Kotlin + Compose)
          │ operaciones root allowlisted
          ▼
CLI dnscrypt-manager del módulo
          │ estado y configuración compartidos
          ▼
dnscrypt-proxy + catálogo + allowlist
```

El módulo sigue siendo el único motor DNS y conserva el estado. La app no mantiene un segundo proceso DNS, no usa `VpnService` y no edita archivos de configuración directamente. La WebUI existente se conserva como panel avanzado y respaldo.

## Funciones conectadas en el cliente Android

| Pantalla | Lecturas | Acciones |
|---|---|---|
| Inicio | Servicio, escucha, redirección, resolver, versión, actividad y estadísticas | Actualizar estado; activar o pausar registro local |
| Actividad | Eventos DNS recientes y estadísticas | Buscar y filtrar eventos; borrar con confirmación |
| Catálogo | Grupos y fuentes reales, consultados por categoría | Buscar, filtrar recomendadas/activas, activar o desactivar con confirmación, preparar todas las cachés y ver progreso |
| Permitidos | Dominios de allowlist | Agregar o quitar un dominio; el CLI valida y aplica el cambio |
| Ajustes | Resolver actual, versión y estado del registro | Cambiar entre Cloudflare, Quad9, AdGuard, Mullvad o NextDNS; el cambio confirmado reinicia `dnscrypt-proxy` |

Los comandos se limitan a `status`, `activity`, `catalog groups/list/enable/disable/download-all`, `allowlist list/add/remove`, `provider`, `nextdns` y `restart`. Los grupos, IDs, proveedores, dominios, IDs NextDNS y tiempos se validan antes de construir una llamada root.

Al abrir la app, Inicio muestra primero el estado del servicio; los eventos y estadísticas locales se consultan después, sin bloquear la pantalla principal. Cada ejecución root y la lectura de su respuesta tienen límites de tiempo para que un proceso trabado no deje un indicador girando indefinidamente.

La lectura del catálogo se hace por grupo, como en la WebUI, para no transportar su JSON entero en cada carga. “Preparar todas” descarga cachés verificadas y consulta el progreso; no activa fuentes. Una activación individual requiere una confirmación visible porque puede cambiar qué dominios se bloquean. Las etiquetas y licencias upstream se presentan como metadata del feed, no como una auditoría propia.

## Diseño de interfaz

- Textos y navegación en español, navegación inferior con Inicio, Actividad, Listas y Ajustes.
- Tema oscuro azul verdoso, estado de protección destacado, métricas legibles y tarjetas compactas.
- Búsqueda local y filtros directos para reducir pasos.
- Confirmaciones antes de borrar eventos, modificar allowlist, activar listas o cambiar el resolver.
- Errores y operaciones en curso se muestran al usuario; no se presentan categorías ficticias ni atribución de aplicación inexistente.

La dirección visual se inspira en la jerarquía clara de estado y registros de Rethink, sin incorporar su código, marca, VPN o firewall. Rethink separa sus registros de solicitudes DNS de su firewall de red ([documentación del firewall](https://docs.rethinkdns.com/firewall/), [preguntas frecuentes](https://rethinkdns.com/faq)); esta app empieza únicamente por el flujo DNS que sí entrega el módulo.

## Límites y trabajo posterior

- No hay conexiones IP/TCP/UDP completas, reglas por UID, bloqueo por aplicación ni inspección HTTPS.
- La actividad DNS no atribuye con fiabilidad una consulta a un paquete Android. `app-policy` del módulo continúa en modo `RECORDED-ONLY`.
- No se exponen todavía desde la app los perfiles de seguridad, el modo fail-closed, las excepciones temporales, rollback, pruebas de fugas ni diagnóstico avanzado. La WebUI sigue disponible para esas operaciones.
- La app no valida automáticamente la calidad de un resolver nuevo con una prueba DNS antes de considerarlo operativo; informa el resultado real de reinicio y el usuario debe comprobar la conectividad.
- Los cambios DNS deben probarse físicamente en Wi‑Fi, datos y hotspot. La compilación no demuestra que el acceso root, el backend o la red funcionen en Android.

## Build y evidencia

El workflow `.github/workflows/build-android-app.yml` compila el APK debug con JDK 17, Gradle 8.9 y Android SDK 35. También ejecuta el gate del módulo y sube la candidata del módulo como artefacto independiente. `android-app/` queda fuera del ZIP del módulo.

| Elemento | Evidencia |
|---|---|
| Diseño y puente root | revisión estructural del código fuente |
| Comandos de actividad | pruebas locales previas del CLI: 70 checks de seguridad/actividad, 0 fallos |
| Catálogo, cachés, allowlist y motor DNS | CI/simulación existente del módulo; no sustituye prueba en el teléfono |
| APK de cada revisión | verificar la ejecución correspondiente de GitHub Actions; CI no prueba operación en el teléfono |
| Instalación, permiso KernelSU Next y operación Android 16 | pendiente de prueba física |
| Wi‑Fi, datos, hotspot, Tailscale y rollback | pendiente de prueba física de esta app y del módulo candidato |

Antes de publicar una versión estable, compilar, instalar, probar cada acción, registrar versión y SHA-256, verificar conectividad, confirmar recuperación por TWRP y revisar el workflow de publicación. El candidato no es una actualización estable por el mero hecho de generar un APK.
