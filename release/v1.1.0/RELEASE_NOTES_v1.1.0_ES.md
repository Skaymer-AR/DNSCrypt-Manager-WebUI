# DNSCrypt Manager v1.1.0 — versión estable

v1.1.0 incorpora un motor local de blocklists DNS sobre la base estable v1.0.0.
Conserva DNSCrypt Proxy como único motor DNS: no integra Rethink, no instala otra
VPN y no usa su `VpnService`.

## Novedades

- Catálogo navegable por las categorías originales de seguridad, privacidad y
  control parental. Las secciones se abren bajo demanda; se puede activar una
  categoría completa o elegir fuentes individuales.
- Fuentes descargadas directamente desde sus upstream por HTTPS. El catálogo
  conserva la procedencia, clasificación, formato, URL y estado de licencia;
  los feeds no vienen empaquetados ni se ejecutan.
- Parser para listas de dominios, formato hosts y reglas AdBlock simples que se
  pueden representar fielmente como bloqueo DNS. Normaliza, valida y deduplica;
  las respuestas corruptas o las caídas anómalas conservan la última caché
  válida.
- Descarga global en segundo plano, con hasta cuatro transferencias simultáneas,
  prioridad de CPU reducida y manifiesto reconstruido una sola vez. La descarga
  prepara cachés y **no activa fuentes ni altera el archivo DNS activo**. Para
  aplicar cambios se seleccionan las fuentes y se compila explícitamente.
- Allowlist personal prioritaria, desactivación individual de fuentes,
  reemplazo atómico y rollback de la lista activa.
- Capacidad configurada para hasta 5.000.000 de dominios únicos en el archivo
  DNS final, con límites de tamaño, validación de contenido y comprobaciones de
  espacio libre.
- Informe de auditoría del catálogo derivado de `celzero/rethink-app`, sus
  metadatos y las fuentes upstream identificadas en
  `docs/RETHINK_BLOCKLIST_AUDIT_ES.md`.

## Rendimiento y comportamiento conocido

La descarga global puede transferir muchos datos y las blocklists grandes
requieren CPU, almacenamiento y tiempo para validarse. En un teléfono la WebUI
puede responder lenta o parecer congelada durante una operación grande. El
trabajo corre en segundo plano con prioridad reducida; la lista activa sigue
siendo la última versión compilada hasta que el usuario aplica y compila los
cambios. La prueba automatizada confirma concurrencia limitada, pero no mide el
tiempo de todos los upstream ni el rendimiento DNS en el Motorola del usuario.

## Compatibilidad y alcance

La validación física reportada por el usuario corresponde a Motorola Edge 40
Pro (`rtwo`), Android 16 / API 36, ARM64, KernelSU Next y Hybrid Mount. Se
probaron DNSCrypt, Wi-Fi, datos móviles, hotspot, cambios de red, persistencia,
IPv4 forzado y la WebUI. IPv6 no fue validado exhaustivamente. Ver
`ANDROID_USER_VALIDATION_v1.1.0.md` para el detalle y los límites de esa prueba.

Las etiquetas `malware`, `spyware`, `tracking` o `telemetry` reflejan la
clasificación de una fuente; no prueban que cada dominio sea malicioso. Puede
haber falsos positivos. El módulo no edita `/system/etc/hosts`, no inspecciona
HTTPS y no sustituye un antivirus.

## Instalación y actualización

Instalá el ZIP desde KernelSU Next como actualización del módulo existente. Se
conserva el mismo ID (`dnscrypt_manager`) y la migración de datos es idempotente.
Las nuevas fuentes permanecen apagadas hasta que las selecciones y confirmes.
Para revisar el checksum, descargá el archivo `.sha256` de esta misma release.
