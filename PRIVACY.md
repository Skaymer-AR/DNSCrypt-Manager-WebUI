# PRIVACY.md — DNSCrypt Manager

Creado por **Skaymer AR**.

Este documento explica, sin vueltas, qué guarda DNSCrypt Manager, dónde, por
cuánto tiempo y cómo borrarlo. La regla de fondo es simple: **todo es local y
nada sale del teléfono.**

## Qué se guarda

DNSCrypt Manager puede guardar, únicamente en el almacenamiento del módulo:

- **Configuración** de dnscrypt-proxy (proveedor elegido, Configuration ID de
  NextDNS, modo IPv6, si la redirección arranca en el boot).
- **Listas de bloqueo** descargadas (dominios de malware/phishing/etc.) y sus
  metadatos (nombre de la fuente, licencia, SHA-256, cantidad de dominios,
  fecha de actualización).
- **Allowlist** y **excepciones temporales** que vos mismo cargás.
- **Historial de bloqueos** (opcional): cuándo se bloqueó qué dominio.
- **Logs** técnicos del daemon y del módulo (para diagnóstico).

## Historial de bloqueos: valor por defecto

- Modo: **Solo bloqueos** (no se registran todas las consultas DNS, solo las que
  el filtro bloqueó).
- Retención: **3 días**.
- Máximo: **1000 eventos** (rotación automática; nunca crece sin límite).

Podés cambiarlo desde *Privacidad e historial* en la WebUI, o por CLI:

```
dnscrypt-manager set-flag hist_mode {off|blocked|blocked_errors|diag}
dnscrypt-manager set-flag hist_days {1|3|7}
dnscrypt-manager set-flag hist_max  {50..10000}
```

El modo **diag** (diagnóstico) es temporal: se revierte solo a *Solo bloqueos*
a las 24 horas.

## Dónde se guarda

Todo vive bajo `/data/adb/dnscrypt-manager/` (persistente, solo accesible por
root). El historial de eventos está en
`/data/adb/dnscrypt-manager/security/events/blocked.log`. Los archivos sensibles
tienen permisos `0600` y pertenecen a root.

## Cómo borrarlo

- **Historial de eventos**: botón *Borrar historial* en la WebUI, o
  `dnscrypt-manager events clear`.
- **Pausar el registro**: *Pausar* en la WebUI, o `dnscrypt-manager events pause`.
- **Allowlist**: `dnscrypt-manager allowlist clear --confirmed`.
- **Todo el módulo**: desinstalá el módulo desde tu gestor (KernelSU/APatch/
  Magisk); el directorio de datos se elimina con la desinstalación.

## No hay telemetría

DNSCrypt Manager **no envía nada a ningún servidor externo**: no hay analítica,
ni cuentas, ni nube, ni “envío de consultas para análisis”. El único tráfico de
red que genera es (a) la resolución DNS cifrada que hace dnscrypt-proxy hacia el
resolver que vos elegiste, y (b) cuando vos pedís actualizar las listas, la
descarga desde las fuentes públicas documentadas en `BLOCKLIST_SOURCES.md`.

## Aclaraciones importantes (leelas)

- **El historial DNS puede ser sensible.** Los dominios que visitás dicen mucho
  de vos. Por eso el historial es local, limitado y borrable, y por defecto solo
  registra bloqueos.
- **DNS cifrado no es una VPN.** DNSCrypt/DoH cifran *las consultas DNS*, no todo
  tu tráfico. Tu IP sigue siendo visible para los sitios y tu operador sigue
  viendo a qué IPs te conectás.
- **DNSSEC no vuelve segura una página.** DNSSEC valida que la respuesta DNS no
  fue alterada; no dice nada sobre si el sitio es confiable o si su contenido es
  seguro.
- **Bloquear dominios no reemplaza a un antivirus.** Las blocklists reducen el
  riesgo cortando el acceso a dominios maliciosos conocidos, pero no detectan
  archivos infectados, exploits ni amenazas que usen dominios nuevos o IPs
  directas.
