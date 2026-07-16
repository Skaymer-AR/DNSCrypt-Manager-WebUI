# Importación desde BindHosts (v0.2.0-RC2)

Analiza un directorio de BindHosts y **propone** cambios. El **dry-run no modifica
nada**.

```
dnscrypt-manager import-bindhosts <directorio> --dry-run     # analiza, no aplica
dnscrypt-manager import-bindhosts <directorio> --confirmed   # aplica (atómico)
```

## Archivos procesados
- `sources.txt` — se cotejan por URL contra el catálogo. Se detectan:
  **StevenBlack duplicado**, URL partida de DandelionSprout (corregida en catálogo),
  URL incompleta/insegura (**rota**), fuente **archivada** (p.ej. antipopads-re).
  Las no reconocidas se encolan como personalizadas (**sin activar** automáticamente).
- `blacklist.txt` — dominios válidos → blacklist manual. Las formas URL se
  **normalizan** (`https://click.redditmail.com` → `click.redditmail.com`).
- `whitelist.txt` — dominios válidos → allowlist (revalidada). Las **URLs se
  rechazan** (p.ej. `https://dns.nextdns.io/83d4a9` no se importa como regla hosts).
- `custom.txt` — pares `0.0.0.0`/`127.0.0.1` → blacklist. Los mapeos a IP real se
  **ignoran**.

## Clasificación de dominios
- **ok**: dominio válido.
- **entrada de ejemplo**: TLDs reservados (`.example`, `.test`, `.invalid`,
  `.localhost`, `.local`) → no se importan.
- **sospechoso**: dominio "envuelto" tipo `s.youtube.com.domain.name` → se **marca**
  y **nunca** se importa automáticamente. En cambio `s.youtube.com` se reconoce como
  dominio válido.
- **inválido**: malformado o con posible **inyección shell** (p.ej. `evil.net; rm`).

## Resumen previo (dry-run) y aplicación
El dry-run muestra: fuentes reconocidas, personalizadas, duplicadas, archivadas,
rotas, blacklist válida, allowlist válida, entradas de ejemplo, sospechosas,
inválidas e ignoradas. Al **confirmar**: escritura atómica + recompilación; se
conserva la última lista válida si algo falla.
