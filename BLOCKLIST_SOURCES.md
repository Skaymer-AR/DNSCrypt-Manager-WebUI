# BLOCKLIST_SOURCES.md — DNSCrypt Manager

Creado por **Skaymer AR**.

## Catálogo actual de fuentes

El catálogo fuente de verdad está en `config/catalog/blocklists.json`; la CLI
consume su índice derivado `config/catalog/blocklists.index.tsv`. Tiene 252
entradas: el catálogo previo más las 197 definiciones de fuentes que referencia
el catálogo oficial de Rethink. Esas 197 conservan los grupos, subgrupos, packs,
formatos y URLs del upstream como metadata. Git contiene metadata y URLs, no
copias descargadas de los feeds. Las fuentes se descargan solo cuando el usuario
agrega/actualiza una fuente compatible; cada una se habilita de forma individual
con `dnscrypt-manager catalog enable <id>` y se deshabilita con
`dnscrypt-manager catalog disable <id>`.

En la WebUI, **Listas → Catálogo de listas** presenta acordeones cerrados al
entrar: **Seguridad**, **Privacidad**, **Control parental**, las fuentes propias
de DNSCrypt Manager y las fuentes de Rethink sin grupo. Al abrir un grupo, solo
se dibujan sus filas y hasta 15 por página. La búsqueda permite encontrar una
fuente en cualquier grupo. Las casillas preparan una selección; la fuente no se
descarga ni activa hasta pulsar **Agregar seleccionadas**. Cada fila conserva el
nombre y las etiquetas del origen, muestra su estado y permite desplegar las
URLs de procedencia.

El catálogo oficial declara 85 entradas `Privacy`, 44 `Security`, 67
`ParentalControl` y una sin grupo. La clasificación local no reemplaza esa
taxonomía. `LICENSE_UNKNOWN` aparece en la fila como información, pero no
impide descargarla directamente desde upstream mediante una acción explícita.
Las fuentes siguen apagadas por defecto y su contenido no se empaqueta dentro
del módulo. Las fuentes que combinan varias URLs o formatos no compatibles
todavía requieren revisión técnica antes de habilitarse.

Ejemplos representativos del catálogo (no son una recomendación para habilitar
todas a la vez):

| Fuente | Taxonomía local | URL upstream | Formato | Licencia declarada | Uso / nota |
|---|---|---|---|---|---|
| HaGeZi Multi Light | `ads`, `trackers` | `https://raw.githubusercontent.com/hagezi/dns-blocklists/main/wildcard/light.txt` | dominios wildcard DNSCrypt | GPL-3.0 | Menor cobertura; opt-in |
| HaGeZi Multi Pro | `ads`, `trackers`, `malvertising`, `telemetry` | `https://raw.githubusercontent.com/hagezi/dns-blocklists/main/wildcard/pro.txt` | dominios wildcard DNSCrypt | GPL-3.0 | Una lista general; no combinar con otra variante Multi sin revisar solapamiento |
| HaGeZi TIF Mini | `malware`, `phishing` | `https://raw.githubusercontent.com/hagezi/dns-blocklists/main/wildcard/tif.mini.txt` | dominios wildcard DNSCrypt | GPL-3.0 | Perfil de amenazas compacto |
| 1Hosts Lite | `ads`, `trackers` | `https://raw.githubusercontent.com/badmojr/1Hosts/master/Lite/domains.wildcards` | dominios wildcard DNSCrypt | MPL-2.0 | Ruta actual. `1Hosts Pro` quedó EOL y la entrada local se conserva como `broken`; no se migra automáticamente a Xtra |
| 1Hosts Xtra | `ads`, `trackers`, `malware` | `https://raw.githubusercontent.com/badmojr/1Hosts/master/Xtra/domains.wildcards` | dominios wildcard DNSCrypt | MPL-2.0 | Variante actual muy agresiva; requiere medir tamaño y revisar falsos positivos |
| OISD Small | `ads`, `mobile_ads` | `https://raw.githubusercontent.com/sjhgvr/oisd/main/domainswild_small.txt` | dominios wildcard DNSCrypt | GPL-3.0 | 56.940 entradas en el header consultado; actualización diaria según el autor |
| OISD Big | `ads`, `mobile_ads`, `phishing`, `malvertising`, `malware`, `spyware`, `ransomware`, `cryptojacking`, `telemetry`, `metrics`, `trackers` | `https://big.oisd.nl/domainswild` | dominios wildcard DNSCrypt | GPL-3.0 | Agregada, amplia y con bastante solapamiento con HaGeZi PRO; activar solo tras medir |
| URLhaus | `malware`, `badware_hosting` | `https://urlhaus.abuse.ch/downloads/hostfile/` | hosts | CC0-1.0 | Datos de distribución de malware |
| Phishing Army Extended | `phishing` | `https://phishing.army/download/phishing_army_blocklist_extended.txt` | dominios | CC-BY-NC-4.0 | Condiciones no comerciales y atribución |
| NoCoin hosts | `cryptojacking` | `https://raw.githubusercontent.com/hoshsadiq/adblock-nocoin-list/master/hosts.txt` | hosts | MIT | Lista pequeña de mineros JavaScript conocidos; fuente independiente, opt-in |
| r-a-y / AdGuard Mobile Spyware | `spyware`, `native_trackers` | `https://raw.githubusercontent.com/r-a-y/mobile-hosts/master/AdguardMobileSpyware.txt` | hosts | `LICENSE_UNKNOWN` | Agregado con términos upstream mixtos; disponible para opt-in manual y descarga directa al aplicar; no se incluye en el ZIP |

NextDNS Native Tracking se investigó como referencia (licencia MIT), pero no se
incluyó como fuente del catálogo porque publica archivos por fabricante y no se
validó una variante para Motorola. HaGeZi Native Tracker permanece como entrada
histórica `broken`: el upstream ya no ofrece un feed genérico validado.

Las categorías son etiquetas de cobertura declaradas por el mantenedor; no son
un diagnóstico de cada dominio. Un dominio listado puede ser legítimo en algún
contexto. La lista `spyware` expresa el propósito atribuido al feed y no prueba
que cada entrada sea spyware. Los detalles de las fuentes encontradas en
Rethink, su taxonomía original, URLs directas, licencias y motivos de exclusión
están en [`docs/RETHINK_BLOCKLIST_AUDIT_ES.md`](docs/RETHINK_BLOCKLIST_AUDIT_ES.md).

Las licencias pertenecen a cada upstream. La licencia del generador o del
catálogo de Rethink no concede derechos sobre sus feeds externos. `LICENSE_UNKNOWN`
indica que la licencia individual no se verificó; esas fuentes pueden descargarse
directamente del origen mediante una acción explícita y no se incluyen en el
módulo. Descargar prepara la caché, pero no activa la fuente. El módulo no
certifica los términos de los proyectos upstream.

Las fuentes incorporadas que ya estuvieran activas en una instalación previa
no se desactivan silenciosamente: permanecen así hasta que el usuario las
deshabilite. La marca `LICENSE_UNKNOWN` no cambia ese estado: una activación
nueva requiere selección y confirmación explícitas del usuario.

### Actualizar, revisar y volver atrás

```sh
dnscrypt-manager catalog list --json
dnscrypt-manager catalog info hagezi_multi_pro
dnscrypt-manager catalog download-all --confirmed
dnscrypt-manager catalog download-all status --json
dnscrypt-manager catalog update enabled
dnscrypt-manager catalog manifest
dnscrypt-manager catalog provenance
dnscrypt-manager catalog rollback hagezi_multi_pro
dnscrypt-manager allowlist add example.org
```

`blocklists-manifest.json` guarda timestamp, URL, revisión cuando existe,
SHA-256 crudo y normalizado, cantidades, estado y checksum de los artefactos
compilados. `source-provenance.tsv` vincula cada dominio de las fuentes activas
del catálogo con su identificador de fuente y categorías; no pretende atribuir
las entradas legacy ni los nueve controles por servicio. Las cachés válidas se guardan por fuente;
una respuesta HTTP/HTML/JSON vacía o anómala no las reemplaza. El compilador
rechaza descensos mayores al 50% frente a una caché previa de al menos 20
dominios, limita feeds a 256 MiB y 5.000.000 de dominios válidos por fuente,
las fuentes activas del catálogo a 10.000.000 de entradas normalizadas/1 GiB,
la unión deduplicada a 5.000.000 de dominios y el archivo DNS final a 5.000.000
de dominios tras fusionar fuentes legacy y controles. La compilación requiere al
menos 512 MiB libres para staging/rollback. `catalog rollback <id>`
recupera la caché validada anterior.

**Descargar todas las fuentes** recorre en segundo plano las fuentes compatibles
del catálogo y valida cada feed. Si una descarga falla o viola los sanity checks,
se conserva la caché válida anterior. Las fuentes rotas, archivadas o con
formatos/transportes que requieren revisión se omiten; `catalog download-all
status --json` expone el progreso. El proceso descarga hasta cuatro fuentes en
paralelo, ajusta el número al espacio disponible, usa prioridad de CPU reducida
y reconstruye el manifiesto una sola vez al terminar. Conserva 512 MiB libres
como reserva. Esta acción no activa listas. Después podés seleccionar fuentes por
categoría o una por una. El límite de 5.000 líneas aplica solo a la importación
de allowlist, no al máximo de dominios bloqueados.

La allowlist personal tiene precedencia sobre los filtros de nombres de
DNSCrypt Proxy y se conserva independientemente de las blocklists. Para más
detalles de los límites y de lo que el bloqueo DNS no puede garantizar, ver
`README.md` y `SECURITY_FEATURES.md`.

## Fuentes legacy por categoría

La sección siguiente documenta el motor anterior de categorías (`.src`),
conservado para compatibilidad. No describe el catálogo nuevo.

Fuentes públicas, reputadas y documentadas usadas por la protección por
categoría. Los metadatos viven en `config/blocklist-sources/<categoria>.src`
(formato `clave=valor`). Se copian a `/data/adb/dnscrypt-manager/security/
blocklists/sources.d/` en la primera migración y **no se pisan** si vos las
editás.

No se usan listas anónimas, URLs acortadas, mirrors dudosos ni archivos
modificados por terceros sin verificación. Cada descarga se valida (tamaño,
SHA-256, sintaxis) antes de aplicarse; ver `SECURITY_FEATURES.md` §2.

## Fuentes por categoría

| Categoría | Fuente | Formato | Licencia | Por defecto |
|-----------|--------|---------|----------|-------------|
| Malware | URLhaus (abuse.ch) hostfile | hosts | CC0-1.0 | Activada |
| Phishing | Phishing Army — Extended Blocklist | domains | CC-BY-NC-4.0 | Activada |
| Estafas | durablenapkin Scam Blocklist | hosts | MIT | Activada |
| Rastreadores | The Firebog — EasyPrivacy | domains | GPL-3.0 | Desactivada |
| Publicidad | StevenBlack hosts (unificada) | hosts | MIT | Desactivada |
| Criptominería | ZeroDot1 CoinBlockerLists | domains | GPL-3.0 | Desactivada |

## URLs oficiales

- **Malware** — URLhaus: `https://urlhaus.abuse.ch/downloads/hostfile/`
  (home: https://urlhaus.abuse.ch/)
- **Phishing** — Phishing Army:
  `https://phishing.army/download/phishing_army_blocklist_extended.txt`
  (home: https://phishing.army/)
- **Estafas** — durablenapkin:
  `https://raw.githubusercontent.com/durablenapkin/scamblocklist/master/hosts.txt`
  (home: https://github.com/durablenapkin/scamblocklist)
- **Rastreadores** — EasyPrivacy vía Firebog:
  `https://v.firebog.net/hosts/Easyprivacy.txt` (home: https://firebog.net/)
- **Publicidad** — StevenBlack:
  `https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts`
  (home: https://github.com/StevenBlack/hosts)
- **Criptominería** — ZeroDot1:
  `https://raw.githubusercontent.com/ZeroDot1/CoinBlockerLists/master/list.txt`
  (home: https://gitlab.com/ZeroDot1/CoinBlockerLists)

## Metadatos que guarda el módulo por lista

Tras cada actualización, en `security/blocklists/cache/<categoria>.meta`:

- Nombre y categoría de la fuente, URL oficial, licencia.
- **SHA-256 del archivo crudo** descargado.
- **SHA-256 de la lista final** (ya parseada y normalizada).
- Tamaño en bytes, cantidad de dominios válidos.
- Estado de validación (`ok`) y fecha/hora de la actualización.

Consultables con `dnscrypt-manager blocklists status` (o `--json`) y
`dnscrypt-manager blocklists sources`.

## Cambiar o agregar una fuente

Editá el `.src` correspondiente en `sources.d/`. Claves reconocidas: `name`,
`category`, `url` (solo `https://`), `format` (`hosts` o `domains`), `license`,
`min_bytes`, `max_bytes`, `min_domains`. Tras editar:

```
dnscrypt-manager blocklists update <categoria>
```

Si la fuente entrega dominios uno por línea, usá `format=domains`. Si entrega
formato hosts (`0.0.0.0 dominio`), usá `format=hosts`. El módulo rechaza IPs,
URLs, comodines y entradas inválidas automáticamente.

## Licencias

Respetá las licencias de cada fuente. Varias (CC-BY-NC, GPL) tienen condiciones
de uso/atribución; este módulo solo las **descarga para uso local** en tu propio
dispositivo y no las redistribuye. Los `.src` incluidos apuntan a las URLs
oficiales; no se incluye ninguna lista pre-descargada en el paquete.
