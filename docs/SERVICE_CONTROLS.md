# Controles de privacidad por servicio (v0.2.0-RC2)

Motor **separado** de las blocklists. En RC2 hay **un** control comprobado:
`youtube_no_history`.

```
dnscrypt-manager service list [--json]
dnscrypt-manager service info <id>
dnscrypt-manager service set <id> <normal|15m|1h|boot|perm>
dnscrypt-manager service conflicts
```

## YouTube — No registrar reproducciones
- **Bloquea** `s.youtube.com`. Modos: `normal` (sin bloquear), `15m`, `1h`,
  `boot` (hasta reiniciar), `perm` (permanente).
- **Texto obligatorio** que se muestra al activar:
  > "Control experimental de mejor esfuerzo. DNSCrypt Manager no puede garantizar que
  > YouTube no utilice otros dominios o endpoints para registrar actividad."
- Puede afectar: **historial, recomendaciones, algoritmo, progreso y
  sincronización**. **No** es un modo incógnito perfecto.

## Estado propio, sin tocar datos del usuario
El control mantiene su **propio estado persistente** (`service-state.tsv`). No
escribe en la blacklist ni en la allowlist manual del usuario. La lista compilada
final puede incorporar el bloqueo, pero:
- `normal` **no** borra ninguna entrada manual;
- los modos temporales **expiran** correctamente (por reloj);
- `boot` desaparece al siguiente arranque (por `boot_id`);
- `perm` persiste.

## Conflicto con allowlist
Si `s.youtube.com` está simultáneamente en la allowlist **y** bloqueado por este
control, se **reporta un conflicto** y se explica que la allowlist gana. **No** se
resuelve silenciosamente modificando datos del usuario; se exige una conducta
coherente (quitarlo de la allowlist o no usar el control).

## Predeterminado
Los controles de servicio vienen **apagados** (`normal`).
