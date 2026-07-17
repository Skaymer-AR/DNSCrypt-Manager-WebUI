# Estado de versiones y advertencias de prueba

> **Proyecto en testeo:** todas las versiones v0.2.x son candidatas de prueba. La primera versión considerada estable será **v1.0.0** después de completar la validación real en Android.

## Estado de versiones

| Versión | Estado | Nota |
|---|---|---|
| v0.1.0 | Estable heredada | Última release estable publicada. |
| v0.2.0-RC1 | Pruebas | Primera capa de protección ampliada. |
| v0.2.0-RC2 original | **Descartada / rota** | No usar el ZIP original: en KernelSU Next la WebUI podía no encontrar `/system/bin/dnscrypt-manager`. |
| v0.2.0-RC2.1 WebUI Hotfix | Pruebas | Corrige la resolución de la CLI desde la WebUI. En KernelSU Next puede requerir Hybrid Mount y reinicio. |
| v1.0.0 | Futura estable | Se publicará tras completar pruebas y correcciones. |

## Advertencia obligatoria sobre BindHosts

Desde RC2 y sus hotfixes, **BindHosts no debe permanecer habilitado al mismo tiempo que DNSCrypt Manager**.

Antes de instalar o activar DNSCrypt Manager v0.2.x:

1. Desactivar BindHosts.
2. Reiniciar el dispositivo.
3. Confirmar que BindHosts sigue desactivado.
4. Instalar o activar DNSCrypt Manager.

Ambos módulos pueden administrar hosts, DNS, hooks de arranque o reglas de red. Usarlos simultáneamente puede provocar superposición de reglas, pérdida de conectividad y **riesgo de bootloop**. No se considera una combinación soportada durante el periodo de pruebas.

## KernelSU Next

Si la WebUI muestra que `dnscrypt-manager` es inaccesible o no existe, activar **Hybrid Mount**, reiniciar el dispositivo y volver a abrir la WebUI. No alcanza con cambiar el ajuste sin reiniciar.

## Alcance del testeo

Hasta v1.0.0 deben considerarse pendientes las pruebas prolongadas de actualización, reinicios, Wi‑Fi/datos móviles, IPv4/IPv6, Private DNS, VPN, hotspot, listas grandes, cancelación, timeout, PANIC, consumo de RAM/batería y compatibilidad entre gestores root.
