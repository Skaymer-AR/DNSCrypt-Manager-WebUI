# BLOCKLIST_SOURCES.md — DNSCrypt Manager v0.2.0

Creado por **Skaymer AR**.

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
