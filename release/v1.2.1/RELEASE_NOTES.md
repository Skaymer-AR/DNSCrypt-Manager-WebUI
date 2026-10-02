# DNSCrypt Manager v1.2.1 estable — Android 0.4.3

- Nuevo icono: escudo verde menta sobre fondo oscuro, inspirado en el estado DNS protegido.
- Al tocar un dominio en Actividad, se puede elegir Permitir o Bloquear.
- Permitir guarda el dominio en la allowlist y quita su bloqueo manual.
- Bloquear agrega una regla manual y quita el permiso permanente y la excepción temporal del mismo dominio.
- El módulo aplica la regla mediante el pipeline de listas DNS y restaura las entradas previas si falla la actualización.

Versiones: Android 0.4.3 (versionCode 11); módulo v1.2.1 (versionCode 12004).

Instalá el ZIP del módulo y reiniciá el teléfono; luego instalá el APK. El APK por sí solo no agrega el comando del módulo. Si la firma de tu app anterior difiere, Android requiere desinstalar solo esa app antes de instalar el APK nuevo; esto elimina los datos privados de la app y conserva el módulo y su configuración.

Verificá cada archivo con el SHA-256 que lo acompaña. La compilación y la integridad de los paquetes no sustituyen una prueba en el teléfono.

## Validación y archivos publicados

El 2 de octubre de 2026, el usuario informó que probó esta entrega, que le gustó el resultado y que quería publicarla como v1.2.1 estable. No se comunicaron tiempos de rendimiento ni una batería exhaustiva de escenarios.

La release conserva exactamente el APK y el ZIP entregados en Drive. Se comprobaron la compilación Android, la firma y alineación del APK, la sintaxis de los scripts modificados, la arquitectura ARM64 del binario y la estructura, permisos e integridad del ZIP. No se ejecutaron pruebas funcionales automáticas durante la compilación de estos archivos.

La firma del APK 0.4.3 difiere de la del APK 0.4.2 entregado anteriormente. Para pasar desde aquel APK, hay que desinstalar solo la app; la configuración DNS del módulo se conserva. Si ya instalaste el APK 0.4.3 de Drive, el APK de esta release es idéntico.

Los archivos .sha256 corresponden a estos paquetes exactos. La evidencia de compilación y el reporte del usuario están registrados en ARTIFACTS.json.

---

# DNSCrypt Manager v1.2.1 stable — Android 0.4.3

- New icon: mint shield on a dark background, inspired by the protected DNS status.
- Tap a domain in Activity to choose Allow or Block.
- Allow adds the domain to the allowlist and removes its manual block.
- Block adds a manual rule and removes the permanent allowance and temporary exception for the same domain.
- The module applies the rule through the DNS list pipeline and restores previous inputs if the update fails.

Versions: Android 0.4.3 (versionCode 11); module v1.2.1 (versionCode 12004).

Install the module ZIP and restart the phone, then install the APK. The APK alone does not add the module command. If the previous app uses a different signing certificate, Android requires uninstalling only that app before installing the new APK; this clears the app's private data and preserves the module and its configuration.

Verify each file against its accompanying SHA-256. Compilation and package integrity checks do not replace testing on the phone.

## Validation and published files

On October 2, 2026, the user reported testing this delivery, liking the result, and wanting it published as stable v1.2.1. No performance timings or exhaustive scenario coverage were reported.

The release preserves the exact APK and ZIP delivered through Drive. Checks covered the Android build, APK signature and alignment, modified shell script syntax, the binary's ARM64 architecture, and the ZIP's structure, permissions, and integrity. Automated functional tests were not run while building these files.

The APK 0.4.3 certificate differs from the previously delivered APK 0.4.2. Upgrading from that APK requires uninstalling only the app; the module's DNS configuration is preserved. If you already installed APK 0.4.3 from Drive, this release's APK is identical.

The .sha256 files match these exact packages. Build evidence and the user report are recorded in ARTIFACTS.json.
