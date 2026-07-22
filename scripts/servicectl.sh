#!/system/bin/sh
# scripts/servicectl.sh — v0.3.0-RC1 (D.1). Service-controls DECLARATIVOS.
# Lee config/service-controls/*.json (no hardcodea logica por empresa). OFF por
# defecto; no borra listas manuales; muestra conflictos con allowlist y efectos.
SC_DIR="${MODDIR}/config/service-controls"
SC_STATE="${DATA_DIR}/service-controls/state.tsv"
sc_init() { mkdir -p "${DATA_DIR}/service-controls" 2>/dev/null; chmod 0700 "${DATA_DIR}/service-controls" 2>/dev/null; [ -f "$SC_STATE" ] || : > "$SC_STATE"; chmod 0600 "$SC_STATE" 2>/dev/null; }
_sc_json() {
  # extrae el valor de "clave": limpia espacios y comillas (soporta string y bool)
  grep -o "\"$2\"[[:space:]]*:[[:space:]]*[^,}]*" "$1" 2>/dev/null | head -1 \
    | sed 's/^"[^"]*"[[:space:]]*:[[:space:]]*//; s/^"//; s/"[[:space:]]*$//'
}
sc_mode_of() { sc_init; grep -m1 "^$1	" "$SC_STATE" 2>/dev/null | cut -f2; }
# Modo EFECTIVO respetando expiracion: si 15m/1h ya vencio -> off.
sc_effective_mode() {
  sc_init; _l=$(grep -m1 "^$1	" "$SC_STATE" 2>/dev/null)
  [ -n "$_l" ] || { echo off; return; }
  _m=$(printf '%s' "$_l" | cut -f2); _exp=$(printf '%s' "$_l" | cut -f3)
  case "$_exp" in
    ''|0) echo "$_m" ;;                                   # until_reboot/permanent/sin expiry
    *[!0-9]*) echo "$_m" ;;
    *) if [ "$_exp" -gt "$(date +%s 2>/dev/null || echo 0)" ] 2>/dev/null; then echo "$_m"; else echo off; fi ;;
  esac
}
# Extrae los dominios del control (soporta arrays JSON multilinea).
_sc_domains() {
  awk 'BEGIN{f=0} /"domains"[[:space:]]*:/{f=1} f==1{print; if($0 ~ /\]/){exit}}' "$1" 2>/dev/null \
    | grep -oE '"[A-Za-z0-9_.*-]+"' | sed 's/"//g' | grep -v '^domains$'
}
# HOOK para el merge: dominios de TODOS los controles declarativos activos.
# Emite dominios validos (una lista plana); el llamador hace sort -u y resta la
# allowlist. Respeta expiracion (sc_effective_mode).
sc_append_active() {
  _dest="$1"; sc_init
  [ -d "$SC_DIR" ] || return 0
  for _f in "$SC_DIR"/*.json; do
    [ -f "$_f" ] || continue
    _id=$(basename "$_f" .json)
    _m=$(sc_effective_mode "$_id")
    [ "$_m" = off ] && continue
    _sc_domains "$_f" | grep -E '^[a-z0-9.*-]+$' >> "$_dest" 2>/dev/null
  done
  return 0
}
service_list() {
  sc_init
  [ -d "$SC_DIR" ] || { echo "(sin controles)"; return; }
  for f in "$SC_DIR"/*.json; do
    [ -f "$f" ] || continue
    _id=$(basename "$f" .json); _name=$(_sc_json "$f" name); _cat=$(_sc_json "$f" category)
    _m=$(sc_mode_of "$_id"); [ -n "$_m" ] || _m=off
    printf '%s\t%s\t[%s]\tmode=%s\n' "$_id" "$_name" "$_cat" "$_m"
  done
}
service_info() {
  sc_init; _f="$SC_DIR/$1.json"
  [ -f "$_f" ] || { echo "ERROR: control desconocido: $1" >&2; return 1; }
  echo "id          : $1"
  echo "name        : $(_sc_json "$_f" name)"
  echo "category    : $(_sc_json "$_f" category)"
  echo "description : $(_sc_json "$_f" description)"
  echo "experimental: $(_sc_json "$_f" experimental)"
  echo "mode        : $(sc_mode_of "$1" 2>/dev/null || echo off)"
  echo "domains     :"; _sc_domains "$_f" | sed 's/^/  - /'
  echo "warning     : $(_sc_json "$_f" warning)"
  echo "limitations :"; grep -o '"limitations":\[[^]]*\]' "$_f" 2>/dev/null | sed 's/"limitations"://; s/[][]//g; s/","/\n/g; s/"//g' | sed 's/^/  - /'
}
# service_set ID MODE
service_set() {
  sc_init; _id="$1"; _mode="$2"; _f="$SC_DIR/$_id.json"
  case "$_id" in *[!a-zA-Z0-9_]*) echo "ERROR: id invalido" >&2; return 1 ;; esac
  [ -f "$_f" ] || { echo "ERROR: control desconocido: $_id" >&2; return 1; }
  case "$_mode" in off|15m|1h|until_reboot|permanent) : ;; *) echo "ERROR: modo invalido (off|15m|1h|until_reboot|permanent)" >&2; return 1 ;; esac
  # expiry
  _now=$(date +%s 2>/dev/null || echo 0); _exp=0
  case "$_mode" in 15m) _exp=$((_now+900)) ;; 1h) _exp=$((_now+3600)) ;; esac
  # persistir estado (sin borrar otros)
  grep -v "^$_id	" "$SC_STATE" 2>/dev/null > "$SC_STATE.new" || true; mv -f "$SC_STATE.new" "$SC_STATE" 2>/dev/null
  [ "$_mode" != off ] && printf '%s\t%s\t%s\n' "$_id" "$_mode" "$_exp" >> "$SC_STATE"
  # conflicto con allowlist: si algun dominio del control esta en allowlist del usuario
  _al="${DATA_DIR}/security/allowlist.txt"
  if [ -f "$_al" ]; then
    _sc_domains "$_f" | while read -r _d; do
      [ -n "$_d" ] && grep -qxF "$_d" "$_al" 2>/dev/null && echo "CONFLICTO: '$_d' esta en tu allowlist (el control quedara neutralizado para ese dominio)"
    done
  fi
  command -v log_msg >/dev/null 2>&1 && log_msg "service $_id -> $_mode" 2>/dev/null
  # APLICAR DE VERDAD: recompilar blocked-names por el camino atomico con rollback.
  # (sec_regen_and_reload: merge -> -check -> mv atomico -> restart -> rollback).
  _applied=no
  if command -v sec_regen_and_reload >/dev/null 2>&1; then
    if sec_regen_and_reload >/dev/null 2>&1; then _applied=yes; else _applied=failed; fi
  fi
  echo "service=$_id mode=$_mode expiry_epoch=$_exp applied=$_applied"
  echo "note=OFF por defecto; no se borran tus listas manuales."
  [ "$_applied" = failed ] && { echo "WARN: la recompilacion fallo; el estado quedo guardado pero la lista activa no cambio (rollback)." >&2; return 1; }
  return 0
}
