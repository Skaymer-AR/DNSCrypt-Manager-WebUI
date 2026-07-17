# DNSCrypt Manager WebUI

> ⚠️ **Estado de pruebas:** la serie `v0.2.x` todavía está en validación. La primera versión considerada estable será **v1.0.0**.
>
> **No usar el ZIP original `v0.2.0-RC2`: está descartado/roto.** En KernelSU Next la WebUI podía no encontrar la CLI del módulo. Usar únicamente una revisión hotfix posterior.
>
> **BindHosts debe estar desactivado y el teléfono reiniciado antes de instalar o habilitar RC2/hotfixes posteriores.** Mantener BindHosts y DNSCrypt Manager activos simultáneamente puede superponer hooks o reglas DNS, provocar pérdida de conectividad y generar riesgo de bootloop.
>
> En **KernelSU Next**, si la WebUI indica que `dnscrypt-manager` es inaccesible, activar **Hybrid Mount** y reiniciar.

Gestor de `dnscrypt-proxy` para Android root con CLI, WebUI, redirección DNS opcional, blocklists, rollback y herramientas de diagnóstico.

## Estado publicado

- `v0.1.0`: release estable heredada.
- `v0.2.0-RC1`: candidata de prueba.
- `v0.2.0-RC2` original: **descartada; no instalar**.
- `v0.2.0-RC2.1` WebUI Hotfix: candidata de prueba; puede requerir Hybrid Mount en KernelSU Next.
- `v1.0.0`: futura primera release estable.

La explicación completa está en [`docs/RELEASE_STATUS.md`](docs/RELEASE_STATUS.md).

## Instalación segura de v0.2.x

1. Desactivar BindHosts.
2. Reiniciar el dispositivo.
3. Confirmar que BindHosts sigue desactivado.
4. Instalar o actualizar DNSCrypt Manager.
5. Mantener redirección global y fail-closed apagados hasta comprobar conectividad.
6. Conservar acceso a `PANIC` y `restore-network` durante las pruebas.

## Compatibilidad objetivo

- KernelSU / KernelSU Next / APatch / Magisk.
- Android 13–16.
- ARM64.
- SELinux Enforcing.

La compatibilidad final no debe darse por cerrada hasta completar el plan de pruebas en Android y publicar v1.0.0.
