# DNSCrypt Manager — app nativa y backend compartido

Estado: diseño e integración inicial, todavía sin prueba física en el Motorola Edge 40 Pro.

## Objetivo

La app nativa será el panel principal de uso diario. El módulo seguirá siendo el único responsable de:

- ejecutar `dnscrypt-proxy`;
- aplicar la redirección DNS systemless;
- compilar y activar blocklists;
- aplicar allowlist, excepciones y rollback;
- conservar el estado en `/data/adb/dnscrypt-manager`.

La WebUI no se elimina. Queda como panel avanzado, rescate y alternativa cuando la app no tenga acceso root.

La app no usará una VPN. No se agregará `VpnService`, inspección HTTPS ni firewall de aplicaciones en esta primera etapa.

## Decisiones de producto

### Primera etapa — segura y medible

La app muestra y modifica solamente capacidades que el módulo ya puede sostener:

1. estado de DNSCrypt y redirección;
2. proveedor activo, incluido NextDNS;
3. actividad DNS local: consultas, bloqueos, respuestas permitidas y bypass por allowlist;
4. catálogo por categorías, fuentes recomendadas y fuentes seleccionadas;
5. allowlist y excepciones temporales;
6. perfiles de seguridad, fail-closed, validación y rollback;
7. acceso al panel avanzado de la WebUI.

La actividad completa es opt-in. `activity` queda apagado por defecto, conserva como máximo una ventana corta y utiliza archivos locales con permisos 0600. El módulo no envía telemetría.

### Segunda etapa — monitor de aplicaciones

“Qué app hizo cada consulta” no se puede deducir de un log DNS local de forma fiable: varias aplicaciones pueden compartir resolutores, procesos o UID, y una consulta no contiene por sí sola una identidad de aplicación.

Por eso la atribución por app queda separada y experimental. Antes de implementarla habrá que medir en el teléfono si la combinación Android 16 + KernelSU Next + kernel actual permite obtener UID/paquetes sin convertir el producto en VPN ni tocar firmware. La pantalla podrá mostrar `No disponible todavía` sin inventar datos.

## Contrato compartido

La app nativa y la WebUI llaman a la misma CLI del módulo mediante comandos allowlisted.

Lecturas iniciales:

```text
dnscrypt-manager status --json
dnscrypt-manager activity status --json
dnscrypt-manager activity list --limit 100 --json
dnscrypt-manager activity stats --json
dnscrypt-manager catalog list --json
dnscrypt-manager blocklists status --json
dnscrypt-manager allowlist list --json
```

Operaciones de escritura que la app podrá habilitar progresivamente:

```text
dnscrypt-manager activity enable|disable
dnscrypt-manager catalog enable <id>
dnscrypt-manager catalog disable <id>
dnscrypt-manager allowlist add|remove <domain>
dnscrypt-manager temporary-allow add <domain> <duration>
dnscrypt-manager restart
```

La app no aceptará comandos libres. El puente root tendrá una lista cerrada de operaciones y validará límites, IDs y dominios antes de construir cada llamada.

## Navegación visual

La experiencia será una app Android nativa, no una WebView disfrazada:

- **Inicio:** estado grande protegido/detenido, contador de consultas, bloqueos y permitidas, proveedor activo y acciones rápidas.
- **Actividad:** pestañas `Todas`, `Bloqueadas` y `Permitidas`; búsqueda local; filas compactas con dominio, hora, motivo y lista.
- **Listas:** categorías, recomendadas, seleccionadas, estado de caché y descarga global; ninguna descarga activa una fuente automáticamente.
- **DNS:** proveedor, NextDNS, modo IPv4/IPv6, prueba DNS y estado de red.
- **Ajustes:** perfil, allowlist, excepciones, fail-closed, rollback, idioma y enlace al panel WebUI avanzado.

La dirección visual será oscura, limpia y orientada a estado: navegación inferior, tipografía fuerte para métricas, chips de estado y animaciones breves. Se inspira en la claridad de Rethink, pero no copia código, recursos de marca ni una VPN que el módulo no utiliza.

## Estado de evidencia

| Elemento | Evidencia actual |
|---|---|
| DNSCrypt Proxy como motor | prueba física previa de v1.0.0; validación estructural/CI posterior |
| WebUI, catálogo y descargas | validación local, simulación y reportes previos; la prueba física de v1.1.1 sigue pendiente |
| Nuevo comando `activity` | validación local aislada: 70 OK, 0 FAIL en `smoke-test-security.sh` |
| App Android nativa | diseño y esqueleto; no compilada en este entorno |
| Actividad en Android real | pendiente: consumo, latencia, formato del log y persistencia |
| Atribución por aplicación | pendiente y experimental; no se afirma soporte |

## Rescate y rollback

La app no modifica firmware, kernel, TWRP ni módulos de root. Todo cambio de configuración pasa por la CLI del módulo, que mantiene sus validaciones, backups, `-check`, prueba DNS y rollback. TWRP sigue siendo la plataforma de rescate físico.

