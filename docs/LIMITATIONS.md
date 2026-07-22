# DNSCrypt Manager — Límites de diseño (v0.3.0-RC1)

DNSCrypt Manager es un **gestor y filtro DNS**. Estos límites son inherentes al
enfoque DNS y se documentan para no prometer lo que no puede cumplir.

## No hace (por diseño)
- No hace MITM ni instala una CA propia; no inspecciona HTTPS.
- No aplica filtros cosméticos ni inyecta JS; no bloquea por contenido visual.
- No bloquea por palabras dentro de HTTPS ni cierra todo el 443.
- No es una VPN; no garantiza anonimato absoluto.

## Consecuencias concretas
- **YouTube Ads**: best-effort. El filtrado DNS NO bloquea todos los anuncios
  (muchos se sirven desde los mismos dominios que el contenido).
- **Reglas ABP**: solo se convierten reglas de dominio inequívocas; la cobertura
  es parcial y se documenta. No se promete paridad con un bloqueador de navegador.
- **Atribución por app**: limitada. Se separan (A) política de red por UID, (B)
  atribución de consultas DNS y (C) filtrado por dominio. Solo se implementa lo que
  el kernel permite verificar (owner/skuid); si no hay soporte → "No compatible",
  sin aproximaciones que rompan la red.
- **ODoH**: depende del binario. El code path está presente (verificado), pero la
  ejecución/consulta real en Android no se verifica en entornos x86 → se reporta
  `not_verifiable` y NUNCA se marca activo sin prueba real.
- **Anonymized DNSCrypt**: reduce la exposición de la IP al resolver usando relays;
  NO es una VPN ni garantiza anonimato. Elegir relay y resolver de operadores
  distintos; más relays = más latencia.
- **Monitor**: heurístico. Señala patrones (entropía/DGA, subdominios largos,
  ráfagas); NUNCA afirma "malware confirmado". Todo local, sin telemetría.
- **Detección de bypass**: best-effort y multiseñal; reporta `no_verificable` en
  lugar de falsos positivos. La detección de DoH es por dominio conocido, no por
  puerto 443.
- **Portal cautivo**: la pausa de protección es temporal y acotada (techo 30 min)
  con restauración automática; nunca deja la protección desactivada de forma
  indefinida ni toca reglas de firewall ajenas.

## Operativos
- Sin descargas de listas durante el arranque; el catálogo canónico es inmutable
  en runtime (los resultados runtime van a archivos separados).
- `verified` de una fuente solo tras descarga+validación en el dispositivo, nunca
  desde CI.
- **BindHosts**: convivencia confirmada por el usuario en pruebas físicas (Motorola
  Edge 40 Pro, Android 16, KernelSU Next, Hybrid Mount, SELinux Enforcing) durante
  una semana, con Wi-Fi, datos móviles y hotspot, sin pérdida de DNS ni de
  conectividad ni bootloop. No se exige desactivarlo ni se bloquea. Esto es una
  prueba física en un dispositivo, NO una garantía de compatibilidad universal en
  cualquier equipo o versión. Nota práctica: ambos filtran por su cuenta, así que si
  un dominio aparece bloqueado y no está en tus listas, revisá también BindHosts.
- **KernelSU Next**: requiere Hybrid Mount para exponer la CLI a la WebUI.
- **PANIC** siempre disponible: retira redirección, detiene el proxy y restaura la
  red, limpiando solo lo propio.
- Resultados en Linux/x86 NO equivalen a Android; las pruebas en dispositivo son
  responsabilidad del usuario.
