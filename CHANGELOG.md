# Changelog

## Estado actual de pruebas

- La serie `v0.2.x` continúa en testeo; la primera versión estable prevista es `v1.0.0`.
- El ZIP original `v0.2.0-RC2` queda **descartado/roto** y no debe instalarse: la WebUI podía no encontrar la CLI en KernelSU Next.
- `v0.2.0-RC2.1` es un hotfix de prueba para la resolución de la CLI desde la WebUI.
- Desde RC2/hotfixes posteriores, BindHosts debe estar desactivado y el dispositivo reiniciado antes de instalar o habilitar DNSCrypt Manager. Ejecutarlos simultáneamente puede provocar superposición de reglas DNS, pérdida de conectividad y riesgo de bootloop.
- En KernelSU Next puede ser necesario habilitar Hybrid Mount y reiniciar para que la WebUI acceda al módulo.

Consultar `docs/RELEASE_STATUS.md` antes de instalar versiones candidatas.
