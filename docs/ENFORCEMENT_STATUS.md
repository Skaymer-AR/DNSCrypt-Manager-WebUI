> **v1.0.0**: Anonymized DNSCrypt y ODoH quedaron FUERA del alcance estable; se
> retiraron de la WebUI y no se inicializan. Este documento describe su estado
> interno/experimental y el resto de las funciones.

# ENFORCEMENT STATUS — v0.3.0-RC1 (qué es real y qué no)

Toda la suite corre en x86 contra un binario dnscrypt-proxy de prueba y hooks
TEST_MODE. Esta tabla dice, por función, qué nivel de verificación tiene REALMENTE.
Leela antes de confiar en un checkmark.

Niveles:
- **REAL/x86**: el código de enforcement corre de verdad y se verifica en x86 (sin
  hook en el camino crítico).
- **REAL/device-pending**: el enforcement está implementado pero solo puede
  verificarse en Android (ejecución ARM64 / netd / kernel). En x86 se prueba el
  plumbing, no el efecto.
- **RECORDED-ONLY**: hoy solo guarda estado/intención; el enforcement todavía NO
  está implementado. No finge aplicarlo.
- **NOT_VERIFIABLE**: depende del binario/entorno; nunca se marca activo sin prueba
  real.

| Función | Nivel | Nota |
|---|---|---|
| `dcm_fetch_url` (descarga/clasificación) | **REAL/x86** | clasificación corre de verdad; solo el fetch de red está hookeado |
| `source doctor` | **REAL/x86** | resolución/self-block/última-copia reales; fetch hookeado |
| **service-controls (bloqueo de dominios)** | **REAL/x86** | los dominios llegan a `blocked-names.txt` por el merge real; allowlist neutraliza vía `allowed-names`; verificado en `smoke-test-service-enforcement` |
| migración schema 2→3 (init + defaults OFF) | **REAL/x86** | rollback ante fallo: probado el happy path; el fallo parcial real es device-pending |
| environment / Hybrid Mount / CLI resolver | **REAL/x86** | resuelve bugs de campo reales |
| auditoría DNS `not_verifiable` | **REAL/x86** | lógica de decisión multiseñal verificada |
| catálogo / compilación / fuga de procesos | **REAL/x86** | fix de fuga con reproducción real |
| transport: apply atómico + rollback | **REAL/device-pending** | el `-check`/instancia aislada/restart/verify NO corrió en ARM64; el TOML `[anonymized_dns]` generado no fue validado contra el `-check` real |
| Anonymized DNSCrypt (efecto de red) | **REAL/device-pending** | construye routes; el efecto anónimo real es device-pending |
| **ODoH (consulta real)** | **NOT_VERIFIABLE** | code path presente (strings); consulta Android no verificable en x86; nunca activo sin prueba |
| **app-policy (reglas por UID)** | **RECORDED-ONLY** | registra la política + valida UID; la construcción de la cadena iptables/nft NO está implementada; no toca firewall |
| captive (auto-restore) | **PARCIAL** | pausa/backup/restore reales; NO hay daemon: el auto-restore ocurre al consultar `status` o en el próximo boot |
| bypass (detección) | **REAL/x86 parcial** | señales best-effort; puertos 53/853/IPv6 reportan `no_verificable` salvo señal explícita (device-pending) |
| monitor (heurísticas) | **REAL/x86** | clasificación corre de verdad; alimentación desde historial real es device-pending |

## Lo que NO está en la WebUI (solo CLI en RC1)
transporte, anonymized, ODoH, captive, bypass, monitor, service-controls y
app-policy son **CLI-only**. La SPA tiene status/dns/lists/activity/settings +
source doctor + environment, pero no expone la configuración de estas features.

## Conclusión honesta
El andamiaje, los defaults seguros, las rutas no-destructivas y la disciplina de
seguridad son sólidos y están probados. El enforcement de red real
(transport/ODoH/app-policy) y varias UI están **sin ejecución real en dispositivo**.
Esto es más un **feature-preview verificado en plumbing** que un RC "maduro":
apto para probar en el dispositivo empezando por instalar sin bootloop, migrar,
`environment status`, y `anonymized test` contra el binario real (primer choque con
la realidad). No confíes en los checkmarks para lo marcado device-pending/RECORDED.
