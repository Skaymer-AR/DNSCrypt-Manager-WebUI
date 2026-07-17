# DNSCrypt Manager WebUI

> ⚠️ **Estado de pruebas:** la serie `v0.2.x` todavía está en validación. La primera versión considerada estable será **v1.0.0**.
>
> **No usar el ZIP original `v0.2.0-RC2`: está descartado/roto.** En KernelSU Next la WebUI podía no encontrar la CLI del módulo. Usar únicamente una revisión hotfix posterior.
>
> **BindHosts debe estar desactivado y el teléfono reiniciado antes de instalar o habilitar RC2/hotfixes posteriores.** Mantener BindHosts y DNSCrypt Manager activos simultáneamente puede superponer hooks o reglas DNS, provocar pérdida de conectividad y generar riesgo de bootloop.
>
> En **KernelSU Next**, si la WebUI indica que `dnscrypt-manager` es inaccesible, activar **Hybrid Mount** y reiniciar.

Este repositorio contiene el desarrollo experimental de DNSCrypt Manager para Android root.

## Estado de las versiones

- `v0.1.0`: última release estable heredada.
- `v0.2.0-RC1`: candidata en pruebas.
- `v0.2.0-RC2` original: **descartada y no recomendada**.
- `v0.2.0-RC2.1` WebUI Hotfix: candidata en pruebas.
- `v1.0.0`: futura primera release estable después de completar validación real.

Ver [`docs/RELEASE_STATUS.md`](docs/RELEASE_STATUS.md) para el estado, las advertencias de BindHosts y los requisitos de KernelSU Next.

## Regla de seguridad antes de instalar RC2 o posteriores

1. Desactivar BindHosts.
2. Reiniciar el dispositivo.
3. Verificar que BindHosts continúe desactivado.
4. Instalar o activar DNSCrypt Manager.

No se admite ejecutar ambos módulos simultáneamente durante las pruebas por el riesgo de superposición de reglas DNS, pérdida de conectividad y bootloop.

## Compatibilidad objetivo

KernelSU, KernelSU Next, APatch y Magisk; Android 13–16; ARM64; SELinux Enforcing.

La compatibilidad definitiva no debe darse por cerrada hasta la publicación de v1.0.0.
