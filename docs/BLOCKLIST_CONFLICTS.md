# Redundancias y conflictos entre fuentes (v0.2.0-RC2)

El análisis automático usa **solo metadatos** (y estadísticas de la última
compilación). **No** ejecuta comparación O(N²) del catálogo. La comparación exacta
entre dos fuentes es **bajo demanda**.

## Relaciones (una sola advertencia canónica por relación)
- **`contained_by`** → *[redundante]*: la fuente ya está contenida en otra activa.
  Se puede desactivar la contenida. **Redundante ≠ incompatible.**
- **`supersedes`** → *[sustitución]*: una fuente hace redundante a otra activa. Se
  aclara explícitamente que **no son incompatibles**; gran parte del contenido ya
  está incluido. Para no duplicar el aviso, si la otra ya declara `contained_by`, la
  relación se reporta una sola vez desde ese lado.
- **`overlaps_with`** → *[superposición]*: solapamiento parcial. Relación simétrica;
  se reporta **una sola vez por par** (`id < otro`), evitando el dual A↔B.
- **`conflicts_with`** → *[conflicto]* / *[conflicto funcional]*: incompatibilidad
  real (p.ej. una lista contra un control de servicio `_service*`). Simétrica: una
  vez por par.
- **`[archivada]`** / **`[rota]`**: la fuente activa tiene upstream archivado/roto.
- **`[sin datos]`**: la última descarga de una fuente activa falló
  (`download_failed`/`validation_failed`); se usa la última copia válida si existe.
- **`[formato parcial]`**: fuente ABP activa → cobertura DNS parcial.
- **`[allowlist neutraliza]`**: un dominio está en la allowlist **y** bloqueado por
  un control de servicio; la allowlist gana (el bloqueo no aplica a ese dominio). No
  se resuelve silenciosamente modificando datos del usuario: se **reporta**.

## Comparación exacta bajo demanda
```
dnscrypt-manager catalog overlap FUENTE_A FUENTE_B
```
Requiere que ambas estén descargadas (usa `comm`/`sort` por lotes). Informa
dominios en común y el porcentaje respecto de A.
