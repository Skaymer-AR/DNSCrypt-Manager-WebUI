#!/system/bin/sh
# scripts/apppolicy.sh — v0.3.0-RC1 (D.2). Politicas DNS por app, EXPERIMENTAL, OFF.
# Primero DETECTA capacidades reales del kernel; si no hay soporte -> unsupported,
# NO aplica aproximaciones ni rompe la red. Solo cadenas propias; PANIC limpia solo
# reglas propias. Separa: (A) politica de red por UID, (B) atribucion de consultas,
# (C) filtrado por dominio (limitado por diseno DNS).
AP_DIR="${DATA_DIR}/apppolicy"
AP_STATE="$AP_DIR/policies.tsv"
ap_init() { mkdir -p "$AP_DIR" 2>/dev/null; chmod 0700 "$AP_DIR" 2>/dev/null; [ -f "$AP_STATE" ] || : > "$AP_STATE"; chmod 0600 "$AP_STATE" 2>/dev/null; }
# Deteccion de capacidades. TEST override DCM_AP_TEST_* (owner/skuid).
app_policy_support() {
  ap_init
  _owner=$( { [ "${DNSCRYPT_TEST_MODE:-0}" = 1 ] && [ -n "${DCM_AP_TEST_OWNER:-}" ] && echo "$DCM_AP_TEST_OWNER"; } || { command -v iptables >/dev/null 2>&1 && iptables -m owner -h >/dev/null 2>&1 && echo yes || echo no; } )
  _skuid=$( { [ "${DNSCRYPT_TEST_MODE:-0}" = 1 ] && [ -n "${DCM_AP_TEST_SKUID:-}" ] && echo "$DCM_AP_TEST_SKUID"; } || { command -v nft >/dev/null 2>&1 && echo maybe || echo no; } )
  echo "iptables_owner_match : $_owner"
  echo "nft_meta_skuid       : $_skuid"
  echo "per_uid_network      : $([ "$_owner" = yes ] || [ "$_skuid" = yes ] && echo supported || echo unsupported)"
  echo "dns_attribution      : limited (el resolver no atribuye de forma fiable cada consulta a un UID)"
  echo "per_app_domain_filter: unsupported (limite de diseno DNS; no se promete filtrado por dominio por app)"
  echo "note                 : funcion experimental, OFF por defecto."
  [ "$_owner" = yes ] || [ "$_skuid" = yes ]
}
_ap_supported() { app_policy_support >/dev/null 2>&1; }
app_policy_list() { ap_init; [ -s "$AP_STATE" ] && { echo "package	policy	uid"; cat "$AP_STATE"; } || echo "(sin politicas)"; }
# app_policy_set PACKAGE POLICY
app_policy_set() {
  ap_init; _pkg="$1"; _pol="$2"
  case "$_pkg" in *[!a-zA-Z0-9_.]*) echo "ERROR: package invalido" >&2; return 1 ;; esac
  case "$_pol" in default|force-through-manager|allow-direct|block-external-dns|exempt-from-redirect|monitor-only) : ;; *) echo "ERROR: politica invalida" >&2; return 1 ;; esac
  if ! _ap_supported; then echo "result=unsupported"; echo "note=el kernel no soporta owner/skuid; NO se aplican reglas (no se rompe la red)."; return 1; fi
  # UID por package (best-effort; TEST override)
  _uid=$( [ "${DNSCRYPT_TEST_MODE:-0}" = 1 ] && [ -n "${DCM_AP_TEST_UID:-}" ] && echo "$DCM_AP_TEST_UID" || { command -v pm >/dev/null 2>&1 && pm list packages -U 2>/dev/null | grep ":$_pkg " | grep -oE 'uid:[0-9]+' | cut -d: -f2; } )
  # validar UID (no confiar en el nombre de package como autoridad)
  case "$_uid" in ''|*[!0-9]*) echo "result=uid_unresolved"; echo "note=no se pudo resolver un UID valido para $_pkg; no se aplica."; return 1 ;; esac
  grep -v "^$_pkg	" "$AP_STATE" 2>/dev/null > "$AP_STATE.new" || true; mv -f "$AP_STATE.new" "$AP_STATE" 2>/dev/null
  printf '%s\t%s\t%s\n' "$_pkg" "$_pol" "$_uid" >> "$AP_STATE"
  command -v log_msg >/dev/null 2>&1 && log_msg "app-policy $_pkg=$_pol uid=$_uid" 2>/dev/null
  echo "result=set package=$_pkg policy=$_pol uid=$_uid"
  echo "note=solo cadenas propias; PANIC limpia solo reglas propias."
}
app_policy_clear() {
  ap_init; _pkg="$1"
  case "$_pkg" in *[!a-zA-Z0-9_.]*) echo "ERROR: package invalido" >&2; return 1 ;; esac
  grep -v "^$_pkg	" "$AP_STATE" 2>/dev/null > "$AP_STATE.new" || true; mv -f "$AP_STATE.new" "$AP_STATE" 2>/dev/null
  echo "cleared=$_pkg"
}
