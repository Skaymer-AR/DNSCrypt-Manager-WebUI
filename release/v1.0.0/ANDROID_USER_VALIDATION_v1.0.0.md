# Validación en Android real — DNSCrypt Manager v1.0.0

Estas pruebas **las realizó el usuario en su dispositivo físico** durante el
desarrollo y el uso diario. No son tests automatizados ni pruebas de laboratorio.

**Dispositivo:** Motorola Edge 40 Pro · **Android 16** · **KernelSU Next** ·
**Hybrid Mount** · **SELinux Enforcing** · ROM stock.

## Tested by user on physical Android device
| Caso | Resultado |
|---|---|
| Instalación y funcionamiento del módulo | funciona |
| DNSCrypt operativo en el dispositivo | funciona |
| Wi-Fi | funciona |
| Datos móviles | funciona |
| Hotspot | funciona |
| Cambio entre Wi-Fi / datos / hotspot sin perder DNSCrypt | funciona |
| Conservación de configuración y datos al actualizar | funciona |
| WebUI con KernelSU Next | funciona |
| WebUI mediante Hybrid Mount | funciona |
| Uso continuado durante la evolución del módulo | funciona |
| **Convivencia con BindHosts activo (1 semana)** | sin pérdida de DNS, sin pérdida de conectividad, sin bootloop |

### IPv4 / IPv6 (registro honesto)
El usuario confirmó **estabilidad general con IPv4 forzado**, y con IPv4 habilitado
DNSCrypt se mantiene estable al cambiar entre Wi-Fi, datos móviles y hotspot sin
perder el servicio. En algunas redes no observó fugas IPv6, pero **prefiere IPv4**
para evitar comportamientos variables. El comportamiento **IPv6 depende de la red y
NO fue validado exhaustivamente** en todas las redes y escenarios; tampoco se afirma
que IPv6 esté roto universalmente.

### Alcance de esta validación
Es una prueba física **en un dispositivo concreto**. No implica compatibilidad
universal con cualquier equipo, ROM, kernel o versión de Android.

## No confirmado específicamente (fuera del alcance de v1.0.0 o pendiente)
| Caso | Estado |
|---|---|
| Anonymized DNSCrypt real | **fuera del alcance de v1.0.0** (retirado de la UI) |
| ODoH real | **fuera del alcance de v1.0.0** (retirado de la UI) |
| Enforcement real de app-policy | no implementado (recorded-only, sin exponer) |
| Rollback físico forzando un fallo grave | pendiente, no bloqueante |
| Consumo prolongado de batería | pendiente, sin mediciones (no se inventan) |
| Consumo prolongado de RAM | pendiente, sin mediciones (no se inventan) |

## Niveles de prueba usados en este proyecto
1. **CI/x86 con mocks**: binario de prueba + hooks TEST (no sustituye Android).
2. **Lógica real en Linux**: p. ej. el enforcement de service-controls verifica que los
   dominios llegan realmente a `blocked-names.txt` por el merge real.
3. **Probado por el usuario en Android real**: la tabla de arriba.
4. **No probado / no verificable**: declarado como tal, nunca simulado.
