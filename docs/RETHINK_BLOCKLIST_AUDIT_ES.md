# Auditoría de fuentes de Rethink DNS — 2026-09-22

## Alcance y resultado

Se revisaron el código público de `celzero/rethink-app`, el proyecto oficial
`serverless-dns` y su repositorio `serverless-dns/blocklists`, además de los
upstreams indicados en su `config.json`. La aplicación Rethink usa un proxy
DNS/firewall local y recibe artefactos compilados de su servicio; esta auditoría
no reutiliza ni recomienda sus binarios, trie, endpoints, `VpnService` ni
archivos empaquetados.

El catálogo oficial revisado contiene 197 definiciones: 85 `Privacy`, 44
`Security`, 67 `ParentalControl` y una sin grupo. Los campos son nombre visible,
grupo, subgrupo, formato, URL, `pack` y `level`. No hay un campo de licencia por
fuente. La licencia MPL-2.0 del generador/repositorio no concede derechos sobre
cada lista externa. Las fuentes agregadas sin licencia clara se registran como
`LICENSE_UNKNOWN`: son elegibles para selección manual, no se activan por defecto
y el contenido se descarga directamente del upstream al aplicar.

La metadata integrada es una instantánea reproducible de
`serverless-dns/blocklists`, revisión
`d93e0b380dd74dcb7fd48d8f4525536d4cdf9c2d`, SHA-256
`044fcbf1e2df3288abd499c3170ee65584a3e2e1e40c76c11403e06e519ee18c`.
El archivo `config/catalog/rethink-blocklists-upstream.json` contiene solo esa
metadata pública; no contiene feeds ni dominios descargados. De las 197
definiciones, 182 quedan `LICENSE_UNKNOWN`; 43 además necesitan revisión técnica
por tener varias URLs, carecer de URL HTTPS o declarar un formato que no se
puede convertir de forma segura. El grupo y las etiquetas originales quedan
visibles aunque la fuente esté deshabilitada por ese motivo técnico.

Rethink compila y publica un trie generado con más de 200 listas y millones de
entradas. Ese artefacto empaquetado no es adecuado para DNSCrypt Manager: no
preserva la procedencia por dominio y no resuelve las licencias individuales.

## Fuentes relevantes y decisión

Los conteos son los publicados por el mantenedor cuando existen; cambian entre
actualizaciones. “Redistribución” se refiere a incluir una copia en DNSCrypt
Manager. El diseño elegido descarga el upstream en el dispositivo y no guarda
una lista empaquetada en Git.

| Fuente que referencia Rethink | Taxonomía original de Rethink | Upstream y URL directa | Formato / volumen aproximado | Licencia y redistribución | Frecuencia / decisión |
|---|---|---|---|---|---|
| HaGeZi Multi LIGHT | `Privacy / HaGeZi / liteprivacy / nivel 0` | `hagezi/dns-blocklists`, `wildcard/light.txt` | Wildcard Domains para DNSCrypt; ~39.461 entradas | GPL-3.0 para las listas publicadas. Redistribuible bajo GPL-3.0 con licencia/avisos; los derechos de datos de terceros no quedan concedidos por HaGeZi | GitHub publica a diario; candidata de menor alcance, opt-in |
| HaGeZi Multi NORMAL | `Privacy / HaGeZi / liteprivacy / nivel 0` | `hagezi/dns-blocklists`, `wildcard/multi.txt` | Wildcard Domains; ~200.527 | GPL-3.0; aplicar la advertencia de fuentes de terceros | Diario; alternativa general, no activar junto con otra Multi |
| HaGeZi Multi PRO | `Privacy / HaGeZi / aggressiveprivacy / nivel 1` | `hagezi/dns-blocklists`, `wildcard/pro.txt` | Wildcard Domains; ~228.000 | GPL-3.0; derechos de datos de terceros por revisar si se redistribuye | Diario; buena candidata opt-in para ads/tracking/telemetry combinados |
| HaGeZi Multi PRO++ | `Privacy / HaGeZi / extremeprivacy / nivel 2` | `hagezi/dns-blocklists`, `wildcard/pro.plus.txt` | Wildcard Domains; ~254.846 | GPL-3.0; alto riesgo de falsos positivos, dependencias de telemetría y fuentes de terceros | Diario; agresiva, no combinar con otra Multi |
| HaGeZi Threat Intelligence Feeds (TIF) | `Security / HaGeZi / spam, malware, crypto, scams & phishing / nivel 2` | `hagezi/dns-blocklists`, `wildcard/tif.txt` | Wildcard Domains; ~2.712.863 | GPL-3.0; fuentes terceras mantienen posibles términos propios | Diario; demasiado grande como primera activación móvil. Considerar una variante Medium/Mini luego de medir |
| 1Hosts Lite | `Privacy / 1Hosts / recommended + liteprivacy` | `https://raw.githubusercontent.com/badmojr/1Hosts/master/Lite/domains.wildcards` | Dominios wildcard; ~102.274 líneas en la copia consultada | MPL-2.0 en el upstream; redistribuible cumpliendo avisos/condiciones MPL y respetando derechos de datos de terceros | Repositorio activo; cadencia del archivo no fijada en `config.json`. Candidata liviana. Rethink también declara `mini` y `Pro`, pero esas rutas hoy dan 404; el mantenedor marcó Pro EOL. DNSCrypt Manager actualizó Lite/Xtra y dejó Pro como historial roto, sin migración automática |
| OISD Small | `Privacy / OISD / liteprivacy` | `https://raw.githubusercontent.com/sjhgvr/oisd/main/domainswild_small.txt` (Rethink referencia ese archivo) | Wildcard Domains; 56.940 entradas en metadata del archivo | GPL-3.0 declarada por el autor; redistribuible conservando obligaciones GPL | OISD indica actualización diaria (puede saltear algún día). La variante Small se enfoca principalmente en ads y mobile-app ads; no atribuirle las categorías completas de Big |
| HaGeZi Native Tracker | `Privacy / NativeTracker` en Rethink; el subgrupo conserva fabricante | Archivos NextDNS por proveedor: `nextdns/native-tracking-domains` | Dominios por fabricante; el repositorio tiene diez archivos, no un único feed Motorola | MIT en el repositorio NextDNS; redistribución permitida conservando aviso MIT | Sin cadencia reciente documentada en la metadata revisada y no cubre Motorola. No seleccionada para el Edge 40 Pro |
| URLhaus | `Security / ThreatIntelligence / malware` | `https://urlhaus.abuse.ch/downloads/hostfile/` | Hosts; lista de dominios de distribución de malware | CC0-1.0 según la metadata del catálogo existente; redistribución permitida | Upstream dinámico; la frecuencia exacta depende del export. Mantener opt-in y validar recuentos |
| Phishing.Army | `Security / ThreatIntelligence / scams & phishing` | `https://phishing.army/download/phishing_army_blocklist.txt` | Dominios, decenas de miles según el export y variable | CC-BY-NC-4.0 en el catálogo existente: atribución y uso no comercial; no usar en distribución comercial | Feed activo; ya existe en el catálogo. No crear control duplicado |
| NoCoin (hoshsadiq) | Parte de `Security / Cryptojacking / pack crypto` | `https://raw.githubusercontent.com/hoshsadiq/adblock-nocoin-list/master/hosts.txt` | Hosts; 322 líneas en la copia consultada (el propio proyecto describe “unos pocos” sitios; conteo de dominios no verificado) | MIT publicada por el upstream; redistribuible con aviso MIT | Lista pequeña para mineros JavaScript de navegador; actualización por commits, sin SLA. Ya figura como `nocoin_hosts`, opt-in |
| UT1 Cryptojacking | También agregado bajo `NoCoin (hoshsadiq + ShadowWhisperer + Olbat)` | `https://raw.githubusercontent.com/olbat/ut1-blacklists/master/blacklists/cryptojacking/domains` | Dominios; ~11.5k según README/mirror consultado | CC-BY-SA según el mirror del autor; redistribución con atribución y compartir derivados bajo la misma licencia | El mirror indica sincronización diaria. No se copia en el feed `nocoin_hosts`; es una fuente más amplia, pero requiere preservar CC-BY-SA |
| ShadowWhisperer Cryptocurrency | También agregado bajo `NoCoin` | `https://raw.githubusercontent.com/ShadowWhisperer/BlockLists/master/Lists/Cryptocurrency` | Lista de dominios; recuento variable no calculado | Unlicense/public domain según `LICENSE` del proyecto | Opt-in de Rethink. La procedencia del dato de cada dominio no está detallada; preferir el upstream pequeño MIT si se busca mínimo alcance |
| NoCoin agregado de Rethink | `Security / Cryptojacking / pack crypto` | NoCoin + ShadowWhisperer + UT1 + `https://v.firebog.net/hosts/Prigent-Crypto.txt` | Hosts y dominios combinados; volumen depende de la descarga y duplicados | Licencias mixtas. El feed Firebog no queda licenciado por las otras tres licencias; `LICENSE_UNKNOWN` para redistribuir el agregado sin separar/verificar ese componente | Rethink declara las cuatro URLs en una entrada. DNSCrypt Manager usa únicamente el upstream NoCoin MIT y conserva la procedencia; no descarga este agregado |
| Coin Blocker (ZeroDot1) | `Security / Cryptojacking / pack crypto`, nivel 2 | Cuatro URLs declaradas por Rethink bajo `https://gitlab.com/ZeroDot1/CoinBlockerLists/-/raw/master/`: `list.txt`, `list_browser.txt`, `list_browser_AdBlock.txt`, `list_optional.txt` | Rethink declara formato `domains`; incluye una variante AdBlock que no debe convertirse como si fueran dominios | `LICENSE_UNKNOWN`: no se encontró licencia clara aplicable al contenido; no redistribuir/activar automáticamente | No seleccionada. La URL GitLab redirigió a login y la URL histórica GitHub devuelve 404; revisar upstream antes de cualquier uso |
| NextDNS Native Tracking | `Privacy / NativeTracking` | `https://github.com/nextdns/native-tracking-domains` (archivos por fabricante) | Dominios; volumen por archivo no consolidado | MIT | Mantener como referencia y no presentarlo como protección específica de Motorola |
| Disconnect Tracking | `Privacy`, pack `spyware` | `https://s3.amazonaws.com/lists.disconnect.me/simple_tracking.txt` | Dominios | `LICENSE_UNKNOWN`: el manifiesto de Rethink no da licencia por feed y no se confirmó permiso del upstream | Excluida hasta aclaración de licencia |
| NoTrack (Quidsup) | `Privacy / Quidsup`, packs `aggressiveprivacy` y `spyware` | `https://gitlab.com/quidsup/notrack-blocklists/-/raw/master/trackers.list` | Dominios; cantidad no verificada | GPL-3.0 publicada en el repositorio | El endpoint no entregó contenido útil en la consulta pública; no seleccionada hasta verificar descarga, frescura y conteo |
| NoTracking | `Privacy`, packs `aggressiveprivacy` y `spyware` | `https://raw.githubusercontent.com/notracking/hosts-blocklists/master/hostnames.txt` | Hosts/dominios; cantidad no consolidada | `LICENSE_UNKNOWN`: no se confirmó licencia de la lista | El repositorio fue archivado en 2023 y anunció el cierre del feed; no seleccionada |
| NSO + Others (Amnesty) | `Security / Amnesty / spyware, malware` | Ocho URLs agregadas, entre ellas AmnestyTech, cbuijs, scafroglia y FMHY | Domains/hosts mixtos | `LICENSE_UNKNOWN`: agregación multi-origen, licencias/condiciones distintas y términos incompletos en el registro | Excluida automáticamente; no republicar el agregado |
| AdGuard Tracking and Spyware (r-a-y) | `Privacy`, pack `aggressiveprivacy`, nivel 1 | Rethink declara `r-a-y/mobile-hosts/AdguardMobileSpyware.txt`, `AdguardMobileAds.txt` y `AssoEchap/stalkerware-indicators/generated/hosts` | Dos hosts y un archivo hosts/dominios; conteo combinado no medido | GPL-3.0 en `r-a-y/mobile-hosts`; no se confirmó la licencia específica del componente AssoEchap (`LICENSE_UNKNOWN` para el conjunto) | Excluida automáticamente hasta separar upstreams y verificar términos/composición |
| ThreatFox | `Security / ThreatIntelligence` | `https://threatfox.abuse.ch/` | Hostfile domain-only (payload y C2) | `LICENSE_UNKNOWN`; requiere Auth-Key para descargar | Export se regenera cada cinco minutos y expira indicadores antiguos; no apto para descarga anónima del módulo |

OISD Big se revisó como alternativa del mismo upstream, no como el preset que
declara el catálogo de Rethink. La FAQ oficial indica ads, mobile-app ads,
phishing, malvertising, malware, spyware, ransomware, cryptojacking y
telemetry/analytics/tracking; licencia GPL-3.0 y actualización al menos cada
24 h. La descarga `domainswild` superó el límite de lectura de 4 MiB del
inspector web, así que no se afirma un conteo ni tamaño exactos aquí. La entrada
ya presente en DNSCrypt Manager ahora refleja esas categorías y licencia; el
actualizador aplica sus límites locales y no habilita la lista.

### Qué significan las categorías

La interfaz de Rethink conserva tres grupos (`Privacy`, `Security`,
`ParentalControl`) y etiquetas `pack` independientes. `spyware` aparece como
un pack, pero eso expresa el propósito asignado a la lista, no una confirmación
de que cada dominio sea spyware. `liteprivacy`, `aggressiveprivacy` y
`extremeprivacy` tampoco equivalen a `tracking`, `telemetry` o `malware`.
DNSCrypt Manager conserva su clasificación local (por ejemplo, `trackers`,
`telemetry`, `spyware`, `malware`) y añade `source_id` por entrada; no infiere
culpabilidad del dominio ni colapsa el grupo original de Rethink.

El catálogo oficial sí etiqueta entradas de `Cryptojacking`, `malware`,
`scams & phishing`, `spyware`, `Windows Telemetry` y rastreo nativo por
proveedor; `analytics` y `fingerprinting` no aparecen como grupos/subgrupos o
packs explícitos en ese `config.json`. Tampoco hay una taxonomía explícita
`command-and-control`: se referencia inteligencia de amenazas y fuentes que
pueden contener infraestructura C2, pero no se puede etiquetar cada dominio
como C2 a partir del catálogo. Bloqueo DNS puede impedir consultas a dominios
conocidos de rastreo/fingerprinting, pero no detectar ni neutralizar técnicas
de fingerprinting ejecutadas desde un sitio permitido. Esas categorías no se
inventan ni se asignan sin metadatos upstream.

En Rethink se encontraron fuentes útiles para el objetivo de privacidad:
HaGeZi Multi Pro/Pro++ y listas de rastreo por proveedor NextDNS. Los agregados
Disconnect, NoTrack, r-a-y y NSO son referencias de descubrimiento, no fuentes
para incorporar hasta verificar cada licencia upstream. El alcance actual de
los nueve controles por servicio ya cubre telemetría/rastreo de Google, Meta,
Microsoft, Reddit, Samsung, Spotify, TikTok, Xiaomi y YouTube. No se agregan
controles duplicados; el catálogo de listas existente cubre categorías amplias.

## Auditoría del repositorio DNSCrypt Manager

- La rama de trabajo parte del tag estable `v1.0.0`; `main` no se modifica.
- Hay dos motores funcionales: seis categorías legacy y un catálogo de 252
  entradas, incluidas 197 definiciones de fuentes del inventario de Rethink.
  Las fuentes nuevas del catálogo están inicialmente desactivadas.
- El catálogo ya tiene actualización HTTPS, validación, caché por fuente,
  compilación bajo demanda, enable/disable individual, estadísticas de
  deduplicación y allowlist que termina en `allowed_names` de DNSCrypt.
- `blocked-names.txt` ya se construye en un archivo temporal y se reemplaza por
  `mv`; DNSCrypt solo se reinicia si el contenido/configuración cambia. La
  descarga de una fuente que falla conserva su caché previa.
- El catálogo WebUI muestra inicialmente grupos cerrados; abrir un grupo dibuja
  solo ese grupo y como máximo 15 fuentes por página. La búsqueda sigue
  disponible y no hay polling. Cada fuente conserva su grupo, subgrupo, packs,
  formato y URLs upstream, además del estado y el último éxito/caché.
- Varias rutas HaGeZi existentes referían a `dns-blocklists/main/hosts`, que fue
  migrado fuera de `main`. El upstream actual recomienda `wildcard/` para
  DNSCrypt y mantiene formatos legacy en `dns-blocklists-legacy`.
- El upstream actual de 1Hosts publica MPL-2.0, no CC-BY-SA. Se corrigieron
  licencias y rutas Lite/Xtra; Pro quedó `broken` (EOL/404) para conservar
  historial sin cambiar una activación del usuario por Xtra. OISD declara
  GPL-3.0 en la FAQ: se corrigió `custom-oisd`, se actualizó OISD Small a la
  URL wildcard actual y Big ahora conserva las categorías que OISD declara.
- Las 182 definiciones de Rethink sin licencia individual verificada quedan
  rotuladas `LICENSE_UNKNOWN`, pero se pueden seleccionar manualmente. No se
  incluyen sus datos en el módulo: cada fuente se descarga del upstream solo al
  confirmar la activación, y permanece OFF mientras no se seleccione. Las 43
  entradas que requieren revisión técnica siguen sin activarse hasta corregir
  sus URLs o formato. Las fuentes personalizadas conservan su flujo explícito.
- Los nueve controles por servicio empiezan OFF y no deben cambiar.

## Arquitectura propuesta y límites

Se amplía el catálogo existente; no se crea un segundo servicio ni una copia
estática de listas:

1. URLs HTTPS fijas por fuente; los upstreams descargan como datos y nunca se
   ejecutan.
2. Descargar a temporal con timeout/límite, revisar código HTTP/contenido,
   rechazar HTML/JSON inesperado, parsear formatos soportados, normalizar ASCII
   a minúsculas y filtrar hostnames, IPs, localhost y reglas complejas.
3. Comparar la cantidad nueva con la caché válida anterior; un descenso brusco
   se marca como anomalía y conserva la caché anterior. Cada feed queda bajo
   32 MiB/1.000.000 de dominios por feed, 1.000.000 de entradas normalizadas y
   64 MiB de cachés activas, 500.000 dominios únicos en el catálogo y 1.000.000
   en el archivo final combinado con legacy/controles.
4. Guardar caché normalizada, SHA-256, conteos, URL y fecha en metadata atómica.
   Mantener un mapa `dominio / source_id / categorías locales` para explicar la
   procedencia. La compilación ya deduplica dominios antes de escribir la lista
   de DNSCrypt.
5. Generar `blocked-names.new`, validar configuración DNSCrypt y reemplazar de
   forma atómica. La allowlist sigue teniendo precedencia; si falla la
   compilación o la prueba de DNS, restaurar caché/lista anterior.
6. Exponer runtime status, último éxito, dominios en caché y hash en el panel
   lazy ya existente, sin introducir polling.

`DNSCrypt Proxy` acepta `*.example.com` y especifica que equivale a
`example.com`, incluyendo apex y subdominios. La conversión segura elimina el
prefijo `*.` o `||` solo para reglas de dominio simples. Excepciones ABP,
reglas cosméticas, opciones, paths, parámetros y patrones complejos se ignoran;
no se aproximan silenciosamente. Los nombres IDN Unicode se rechazan si no
vienen ya en ASCII/Punycode, porque Android no incorpora un conversor IDNA
genérico en este motor shell.

El número total de dominios no prueba el impacto en latencia en un teléfono.
En una carga sintética Linux x86_64 de 200.000 entradas de fuente A y 140.000
de B (40.000 compartidas, 20.000 duplicadas dentro de A), el compilador produjo
281.000 dominios incluyendo 1.000 manuales: 4.986.560 bytes; el merge tomó 1 s
según reloj de segundos. Un muestreo de PSS del árbol de procesos durante la
suite completa midió un pico aproximado de 47.702 KiB. Es una referencia de
host sintética, no una medición Android. El repositorio estable no contiene
cachés runtime ni un `blocked-names.txt` activo con el que comparar antes y
después; tampoco se midieron recarga del daemon ni latencia DNS en el Edge 40
Pro. Esas mediciones físicas siguen pendientes antes de recomendar agregados
grandes. El TIF full supera 2,7 millones de reglas y excede los límites iniciales.

## Referencias oficiales consultadas

- Rethink para Android: <https://github.com/celzero/rethink-app>
- Resolver/generador: <https://github.com/serverless-dns/serverless-dns>
- Catálogo de feeds: <https://github.com/serverless-dns/blocklists/blob/main/config.json>
- Lista de licencias/copyright de HaGeZi: <https://github.com/hagezi/dns-blocklists>
- Formato HaGeZi compatible con DNSCrypt y volúmenes: <https://github.com/hagezi/dns-blocklists/blob/main/README.md>
- NextDNS native tracking: <https://github.com/nextdns/native-tracking-domains>
- DNSCrypt blocked-name patterns: <https://github.com/DNSCrypt/dnscrypt-proxy/blob/master/dnscrypt-proxy/example-blocked-names.txt>
- ThreatFox export/autenticación/retención: <https://threatfox.abuse.ch/export/>
