# Binario dnscrypt-proxy — estado y procedimiento

**DNSCrypt Manager — Creado por Skaymer AR**

## Estado en este arbol

**Binario presente e inyectado por `tools/inject-binary.sh`.**

## Registro (generado automaticamente por inject-binary.sh; no editado a mano)

| Campo | Valor |
|---|---|
| Version                      | desconocida (ni ejecucion ni strings la revelaron) |
| Metodo de verificacion       | no verificado por ejecucion + firma estatica de cadenas (paso 4) |
| Arquitectura                 | arm64 (EM_AARCH64, confirmado por cabecera ELF) |
| Archivo de origen (nombre)   | dnscrypt-proxy |
| Tamaño                       | 12618400 bytes |
| SHA-256                      | `940b650911cfa55cbc0544a9025ceb866101590a88031a90a7e1ca05f5781cbc` |
| Fecha de inyeccion           | 2026-07-14 06:53:11 UTC |
| Host que inyecto             | Linux runnervm5mmn9 6.17.0-1018-azure #18~24.04.1-Ubuntu SMP Thu May 28 16:39:11 UTC 2026 x86_64 x86_64 x86_64 GNU/Linux |

## Como reproducir esta verificacion

```sh
sha256sum "dnscrypt-proxy"
# Debe imprimir: 940b650911cfa55cbc0544a9025ceb866101590a88031a90a7e1ca05f5781cbc
```

Compara este hash contra el publicado en la pagina de releases oficial de
dnscrypt-proxy (https://github.com/DNSCrypt/dnscrypt-proxy/releases) antes
de confiar en este binario para un dispositivo real.

## Nota de compatibilidad

La CLI (`start`, `config validate`) ejecuta
`dnscrypt-proxy -config X -check` antes de arrancar: si esta version
cambio alguna clave del TOML por defecto, `-check` lo va a señalar con
el nombre exacto de la opcion afectada.
