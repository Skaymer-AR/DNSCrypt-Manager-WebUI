# ANDROID_TEST_PLAN_v0.2.0.md — DNSCrypt Manager

Creado por **Skaymer AR**.

Plan de pruebas **manuales en dispositivo real** para v0.2.0. Estas pruebas
**no pueden ejecutarse en GitHub Actions ni en el sandbox de CI**: dependen de
red real, netd, SELinux enforcing, IPv6, VPN, hotspot, cambios Wi-Fi↔datos y del
binario oficial dnscrypt-proxy corriendo (bionic/ARM64). Las suites automáticas
(`smoke-test-*.sh`, `run-syntax-checks.sh`) cubren la lógica; esto cubre el
comportamiento en el teléfono.

Dispositivo de referencia: **Motorola Edge 40 Pro, Android 16, KernelSU /
KernelSU Next, Zygisk Next, LSPosed**. Repetir lo relevante en Magisk y APatch.

> Marcá cada casilla al validar. Ante cualquier pérdida de conectividad que no
> se recupere sola, ejecutá `su -c dnscrypt-manager panic`.

## A. Conectividad base (no romper lo que ya funciona)

- [ ] **1. Wi-Fi**: con el servicio activo y redirección OFF, navegar normal.
- [ ] **2. Red móvil**: ídem sobre datos.
- [ ] **3. Cambio Wi-Fi → datos**: la conectividad se mantiene.
- [ ] **4. Cambio datos → Wi-Fi**: la conectividad se mantiene.
- [ ] **5. Modo avión** ON y OFF: al volver, DNS resuelve.
- [ ] **6. Reinicio** del teléfono: el módulo arranca sin bootloop.
- [ ] **7. Reinicio con redirección DESACTIVADA**: solo corre el proxy.
- [ ] **8. Reinicio con redirección ACTIVADA** (`boot_redirect=1`): se aplica y
      la prueba DNS pasa; si fallara, el watchdog restaura la red.

## B. Fail-open / Fail-closed / PANIC

- [ ] **9. Fail-open (default)**: matar dnscrypt-proxy → se retiran reglas y
      vuelve el DNS normal (sigue habiendo Internet).
- [ ] **10. Fail-closed** (`failclosed enable --confirmed`): matar el proxy →
      las consultas DNS externas se bloquean; la recuperación root sigue
      disponible. Reactivar el proxy → el bloqueo se suelta solo.
- [ ] **11. PANIC**: con fail-closed activo y redirección puesta, `panic`
      restaura la red, deshabilita el módulo y deja `failclosed=0`.
- [ ] **12. Desactivar fail-closed por ADB**: `adb shell su -c
      'dnscrypt-manager failclosed disable'` funciona sin la WebUI.

## C. IPv4 / IPv6 / red

- [ ] **13. IPv4**: con redirección, `nslookup` sale por el proxy.
- [ ] **14. IPv6**: en modo `redirect`, IPv6 también pasa por el proxy; en modo
      `block`, las consultas DNS por IPv6 se cortan (sin romper el resto de IPv6).
- [ ] **15. VPN activa**: el detector de fugas la reporta como *conflicto* (la
      VPN puede usar su propio DNS); documentar el comportamiento observado.
- [ ] **16. Hotspot/tethering**: `leak-test` lo detecta; con `prerouting=1` los
      clientes del hotspot también se redirigen.
- [ ] **17. Portal cautivo** (Wi-Fi público): el portal carga; tras autenticar,
      DNS resuelve por el proxy.

## D. Proveedores

- [ ] **18. NextDNS** (Configuration ID): aplicar, reiniciar, resolver.
- [ ] **19. Cloudflare**: aplicar, reiniciar, resolver.
- [ ] **20. Quad9**: aplicar, reiniciar, resolver.
- [ ] **21. AdGuard**: aplicar, reiniciar, resolver.
- [ ] **22. Mullvad**: aplicar, reiniciar, resolver.

## E. Listas, allowlist, excepciones

- [ ] **23. Lista corrupta**: forzar una fuente inválida → la actualización la
      rechaza y la lista activa no cambia.
- [ ] **24. Rollback**: tras una actualización buena, `blocklists rollback
      <cat>` vuelve a la versión anterior.
- [ ] **25. Dominio bloqueado**: con malware activo y lista descargada, un
      dominio de la lista no resuelve; aparece en *Eventos*.
- [ ] **26. Allowlist**: agregar un dominio previamente bloqueado → vuelve a
      resolver.
- [ ] **27. Excepción temporal**: permitir un dominio 5m → resuelve; tras
      expirar (o `temporary-allow sweep`), vuelve a bloquearse.

## F. Robustez del servicio

- [ ] **28. Pérdida del proceso dnscrypt-proxy**: matarlo y verificar el
      comportamiento según fail-open/closed configurado (casos 9–10).
- [ ] **29. Puerto ocupado**: ocupar el puerto del listener y arrancar → el
      módulo reporta el fallo sin dejar el teléfono sin DNS.

## G. Private DNS de Android

- [ ] **Private DNS automático**: `leak-test` lo reporta como *posible_fuga*
      (DoT oportunista).
- [ ] **Private DNS con hostname**: `leak-test` lo reporta como *conflicto* y
      sugiere ponerlo en Automático/Off.

## Checklist de cierre

- [ ] No hubo pérdida de Wi-Fi, red móvil ni conectividad en ningún caso.
- [ ] SELinux siguió en **enforcing** (no se ejecutó `setenforce 0`).
- [ ] No se escribió en `/system` ni `/vendor`.
- [ ] La redirección global permaneció **OFF por defecto**.
- [ ] Fail-closed permaneció **OFF por defecto**.
- [ ] PANIC restauró la red en todos los escenarios probados.
