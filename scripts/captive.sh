#!/system/bin/sh
# scripts/captive.sh  —  DNSCrypt Manager v0.3.0-RC1  (CHECKPOINT C.1)
#
# Portal cautivo OPT-IN. Permite iniciar sesión en Wi-Fi cautivo pausando SOLO lo
# mínimo (redirección/fail-closed) por un tiempo acotado, con restauración
# automática. NUNCA deja la protección desactivada indefinidamente; NUNCA borra
# reglas de firewall ajenas; PANIC siempre disponible. OFF por defecto.

CAP_DIR="${DATA_DIR}/captive"
CAP_STATE="$CAP_DIR/state.tsv"
CAP_DEFAULT_WINDOW=300   # segundos de pausa máxima por defecto

captive_init() { mkdir -p "$CAP_DIR" 2>/dev/null; chmod 0700 "$CAP_DIR" 2>/dev/null; [ -f "$CAP_STATE" ] || printf 'inactive\t0\t\n' > "$CAP_STATE"; chmod 0600 "$CAP_STATE" 2>/dev/null; }
_cap_event() { command -v log_msg >/dev/null 2>&1 && log_msg "captive: $1" 2>/dev/null; return 0; }

# Detección best-effort de conectividad limitada / posible portal cautivo.
# NO depende de una sola URL; usa señales locales. TEST override DCM_CAP_TEST_PORTAL.
captive_detect() {
  if [ "${DNSCRYPT_TEST_MODE:-0}" = 1 ] && [ -n "${DCM_CAP_TEST_PORTAL:-}" ]; then printf '%s' "$DCM_CAP_TEST_PORTAL"; return; fi
  # señal 1: ¿hay ruta por defecto? señal 2: ¿el proxy resuelve? Si hay red pero
  # el proxy no resuelve y el sistema tampoco, puede ser portal.
  _route=no; command -v ip >/dev/null 2>&1 && ip route 2>/dev/null | grep -q '^default' && _route=yes
  if [ "$_route" = no ]; then printf 'no_network'; return; fi
  printf 'possible_or_none'   # best-effort: no se afirma con certeza
}

captive_status() {
  captive_init
  _st=$(cut -f1 "$CAP_STATE" 2>/dev/null); _until=$(cut -f2 "$CAP_STATE" 2>/dev/null)
  _now=$(date +%s 2>/dev/null || echo 0)
  # auto-restauración si venció la ventana
  if [ "$_st" = "active" ] && [ -n "$_until" ] && [ "$_until" -gt 0 ] 2>/dev/null && [ "$_now" -ge "$_until" ] 2>/dev/null; then
    captive_restore >/dev/null 2>&1; _st=inactive
  fi
  echo "captive_pause     : $_st"
  [ "$_st" = active ] && echo "restore_at_epoch  : $_until  (auto-restauración)"
  echo "network_detect    : $(captive_detect)"
  echo "note              : la pausa es temporal y acotada; PANIC siempre disponible."
}

# captive enter [SECONDS] — pausa mínima con temporizador y respaldo del estado.
captive_enter() {
  captive_init
  _win="${1:-$CAP_DEFAULT_WINDOW}"
  case "$_win" in ''|*[!0-9]*) _win=$CAP_DEFAULT_WINDOW ;; esac
  [ "$_win" -gt 1800 ] 2>/dev/null && _win=1800   # techo duro: 30 min
  _now=$(date +%s 2>/dev/null || echo 0); _until=$(( _now + _win ))
  # Respaldar el estado previo de redirect/fail-closed para restaurar exacto.
  _rd=off; command -v redirect_is_active >/dev/null 2>&1 && redirect_is_active && _rd=on
  _fc=off; command -v fc_is_engaged >/dev/null 2>&1 && fc_is_engaged && _fc=on
  printf 'active\t%s\t%s;%s\n' "$_until" "$_rd" "$_fc" > "$CAP_STATE"
  # Pausar SOLO lo mínimo: quitar la redirección para permitir el login.
  if [ "$_rd" = on ] && command -v cmd_redirect >/dev/null 2>&1; then cmd_redirect off >/dev/null 2>&1; fi
  # fail-closed: si estaba on, aflojar SOLO durante la ventana (no indefinido).
  if [ "$_fc" = on ] && command -v cmd_set_flag >/dev/null 2>&1; then cmd_set_flag fail_closed 0 >/dev/null 2>&1; fi
  _cap_event "pausa de portal cautivo por ${_win}s (restore_at=$_until)"
  echo "captive=entered window_seconds=$_win restore_at_epoch=$_until"
  echo "note=NO hay daemon: la restauracion automatica ocurre cuando se vuelve a"
  echo "     consultar 'captive status' (o en el proximo arranque). Para volver ya"
  echo "     mismo, corre 'captive restore'. Si nada consulta el estado, la pausa"
  echo "     puede durar mas que la ventana; PANIC restaura todo en cualquier momento."
}

captive_restore() {
  captive_init
  _saved=$(cut -f3 "$CAP_STATE" 2>/dev/null)
  _rd=$(printf '%s' "$_saved" | cut -d';' -f1); _fc=$(printf '%s' "$_saved" | cut -d';' -f2)
  # Restaurar EXACTAMENTE el estado previo.
  if [ "$_rd" = on ] && command -v cmd_redirect >/dev/null 2>&1; then cmd_redirect on >/dev/null 2>&1; fi
  if [ "$_fc" = on ] && command -v cmd_set_flag >/dev/null 2>&1; then cmd_set_flag fail_closed 1 >/dev/null 2>&1; fi
  printf 'inactive\t0\t\n' > "$CAP_STATE"
  _cap_event "protección restaurada tras portal cautivo"
  echo "captive=restored redirect=$_rd fail_closed=$_fc"
}
