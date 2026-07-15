# SECURITY_FEATURES.md — DNSCrypt Manager v0.2.0

Creado por **Skaymer AR**.

Capa de protección de navegación agregada en v0.2.0. Todo se opera desde la
WebUI (KernelSU / KernelSU Next / APatch) o por CLI (`dnscrypt-manager ...`).
La **CLI es la autoridad final**: valida y sanea todo antes de tocar nada.

## 1. Protección por categoría (blocklists)

Seis categorías de dominios bloqueados:

| Categoría      | Por defecto | Motivo del default |
|----------------|-------------|--------------------|
| Malware        | **Activada** | Riesgo alto, bajo falso positivo |
| Phishing       | **Activada** | Riesgo alto, bajo falso positivo |
| Estafas        | **Activada** | Riesgo alto, bajo falso positivo |
| Rastreadores   | Desactivada  | Puede afectar analítica embebida |
| Publicidad     | Desactivada  | Puede romper apps/páginas legítimas |
| Criptominería  | Desactivada  | Menos común; se activa a demanda |

```
dnscrypt-manager protection status
dnscrypt-manager protection enable malware
dnscrypt-manager protection disable ads
```

Las listas se integran a dnscrypt-proxy como `blocked_names_file`. La allowlist
tiene prioridad (se integra como `allowed_names_file`).

## 2. Actualización verificada de listas + rollback

Cada actualización sigue un pipeline estricto (16 pasos): descarga a temporal →
verifica HTTP → tamaño (min/max) → SHA-256 → que sea texto (rechaza binarios) →
sintaxis de dominios → rechaza IPs/URLs/comodines → dedupe → minúsculas → lista
final temporal → **prueba la config con `dnscrypt-proxy -check`** → backup de la
versión anterior → reemplazo atómico (`mv`) → reinicio → prueba DNS real → si
algo falla, **rollback automático** a la versión anterior.

Nunca queda una lista incompleta o vacía como activa. Límites: hasta 25 MB por
archivo y 500 000 dominios (evita agotar RAM/almacenamiento). Líneas de más de
512 caracteres se descartan.

```
dnscrypt-manager blocklists update            # todas las activas
dnscrypt-manager blocklists update malware --sha256 <hash>
dnscrypt-manager blocklists rollback malware
dnscrypt-manager blocklists validate
dnscrypt-manager blocklists sources
```

Fuentes documentadas en `BLOCKLIST_SOURCES.md`.

## 3. Allowlist

Dominios que nunca se bloquean. Validación estricta (misma clase en WebUI y CLI):
acepta `example.com` y `sub.example.com`; rechaza URLs con esquema, rutas,
comodines, IPs y cualquier cosa con metacaracteres de shell.

```
dnscrypt-manager allowlist add example.com
dnscrypt-manager allowlist remove example.com
dnscrypt-manager allowlist search ejemplo
dnscrypt-manager allowlist list
dnscrypt-manager allowlist import /sdcard/lista.txt   # ≤1 MB, ≤5000 líneas
dnscrypt-manager allowlist export /sdcard/backup.txt
dnscrypt-manager allowlist clear --confirmed
```

## 4. Desbloqueo temporal (sin cron)

Permitir un dominio por un rato sin sacarlo del bloqueo permanente. Duraciones:
`5m`, `15m`, `1h`, `boot` (hasta reiniciar), `perm` (= allowlist).

Se guarda dominio, expiración, hora de creación, origen (webui/cli) y motivo.
Las excepciones vencidas se eliminan solas mediante **barrido perezoso** (en cada
operación relevante y en el boot) más un temporizador desacoplado — **no depende
de cron** (Android puede no tenerlo). Hay protección ante cambios de reloj: una
excepción “creada en el futuro” se descarta.

```
dnscrypt-manager temporary-allow add example.com 15m --reason descarga
dnscrypt-manager temporary-allow list
dnscrypt-manager temporary-allow remove example.com
dnscrypt-manager temporary-allow sweep
```

## 5. Perfiles de seguridad

Tres perfiles que ajustan varias opciones a la vez, de forma **atómica** (snapshot
+ rollback si algo falla):

| Opción              | Equilibrado | Estricto | Privacidad |
|---------------------|-------------|----------|------------|
| Malware/Phishing/Estafas | ✔ | ✔ | ✔ |
| Rastreadores        | ✘ | ✔ | ✔ |
| Publicidad          | ✘ | opcional | opcional |
| Criptominería       | ✘ | ✔ | ✘ |
| DNSSEC requerido    | ✔ | ✔ | ✔ |
| Servidores sin logs preferidos | ✔ | — | ✔ (require_nolog) |
| Fail-closed         | ✘ (fail-open) | **✔** | ✘ (fail-open) |
| Historial           | Solo bloqueos | Bloqueos+errores | Reducido (1 día, 200) |

La WebUI muestra **literalmente** qué cambia antes de aplicar. El perfil
**Estricto** activa fail-closed y por eso **pide confirmación**:

> “Si DNSCrypt deja de funcionar, el teléfono puede quedarse sin resolución DNS
> hasta restaurar la red manualmente.”

```
dnscrypt-manager security-profile status
dnscrypt-manager security-profile balanced
dnscrypt-manager security-profile strict --confirmed
dnscrypt-manager security-profile privacy
```

## 6. Modo fail-closed (opcional, opt-in)

Por defecto el módulo es **fail-open**: si dnscrypt-proxy falla, se retiran las
reglas y vuelve el DNS normal (se conserva conectividad).

**Fail-closed** (opt-in) hace lo contrario: si el servicio falla, se bloquean las
consultas DNS externas (puerto 53 saliente) para que no haya *fallback* inseguro.
Garantías:

- Es **opt-in** y muestra advertencia; requiere confirmación.
- Se puede desactivar desde WebUI, CLI **y ADB**:
  `su -c dnscrypt-manager failclosed disable`.
- **El botón PANIC siempre restaura la red** (además fuerza el flag a 0).
- **Nunca** bloquea loopback (`lo`, `127.0.0.0/8`, `::1`) ni el propio proxy
  (su tráfico upstream es DoH/443, no puerto 53).
- Usa **cadenas/tabla propias** (`DNSCRYPT_FC` en la tabla filter; tabla nft
  `dnscrypt_manager_fc`, separada de la de redirección). No toca reglas ajenas.
- Todas las operaciones son **idempotentes**; sobrevive a reinicio; hay rollback
  si la configuración es inválida.

```
dnscrypt-manager failclosed status
dnscrypt-manager failclosed enable --confirmed
dnscrypt-manager failclosed disable
```

## 7. Detector de fugas DNS

Audita, por separado, listener local, resolución por el proxy, UDP/TCP 53 en
IPv4/IPv6, resolución del sistema, Private DNS de Android, VPN, hotspot, DNS de
la red y posible DoH del navegador. Estados: **protegido**, **posible_fuga**,
**no_verificable**, **conflicto**, **fallo**.

Nunca afirma lo que no puede comprobar. Para navegadores con DoH propio muestra:

> “Esta aplicación puede evitar la redirección DNS del sistema usando HTTPS.
> DNSCrypt Manager puede detectarlo parcialmente, pero no bloquear todos los
> servicios DoH sin afectar tráfico HTTPS legítimo.”

No bloquea el puerto 443 globalmente, no hace MITM y no instala certificados.

```
dnscrypt-manager leak-test
dnscrypt-manager leak-test --json
```

## 8. Panel “por qué fue bloqueado” + historial

Eventos recientes con dominio, categoría, lista que lo produjo, fecha/hora,
regla coincidente y si hay una excepción activa. Acciones por evento: permitir
5m/1h, agregar a allowlist, copiar dominio. No se atribuye el dominio a una app
(no hay forma fiable de conocer el UID/paquete) y no se inventan nombres.

Historial **local**, limitado y rotado (ver `PRIVACY.md`). Estadísticas: total,
por categoría, dominio más bloqueado, última actualización de listas, errores de
resolución.

```
dnscrypt-manager events            # o: events list --json
dnscrypt-manager events stats
dnscrypt-manager events clear
dnscrypt-manager events export /sdcard/eventos.tsv
```

## Seguridad de implementación

Sin `eval`; sin `source` de archivos modificables por el usuario; sin comandos
armados concatenando input; sin `chmod 777` ni directorios *world-writable*; sin
`curl|sh`; sin `pkill/killall/pgrep` ambiguos; sin *flush* de tablas ajenas; sin
tocar SELinux. Procesos: PID file + validación de `/proc/$PID/exe`/cmdline, se
mata solo el PID validado. Archivos: permisos mínimos, root, escritura atómica
(tmp+`mv`), backups limitados, rutas verificadas dentro del directorio esperado.
WebUI: `textContent` (sin `innerHTML` con datos), validación de JSON, timeout,
botones bloqueados durante cada operación (anti doble-toque).
