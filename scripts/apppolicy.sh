#!/system/bin/sh
# Politica experimental de firewall saliente por UID.
# Solo usa cadenas propias y requiere owner de iptables en IPv4 e IPv6.
AP_DIR="${DATA_DIR}/apppolicy"
AP_STATE="$AP_DIR/policies.tsv"
AP_CHAIN="DCM_APP_OUT"

ap_init() {
  mkdir -p "$AP_DIR" 2>/dev/null
  chmod 0700 "$AP_DIR" 2>/dev/null
  [ -f "$AP_STATE" ] || : > "$AP_STATE"
  chmod 0600 "$AP_STATE" 2>/dev/null
}

_ap_valid_package() {
  case "$1" in
    ""|.*|*.|*..*|*[!a-zA-Z0-9_.]*) return 1 ;;
    *.*) return 0 ;;
    *) return 1 ;;
  esac
}

_ap_valid_uid() {
  case "$1" in ""|*[!0-9]*) return 1 ;; esac
  [ "$1" -ge 10000 ] 2>/dev/null && [ "$1" -le 2147483647 ] 2>/dev/null
}

_ap_fw() {
  _ap_tool="$1"; shift
  "$_ap_tool" -w "$@" >/dev/null 2>&1
}

_ap_probe_tool() {
  _ap_tool="$1"; _ap_family="$2"
  command -v "$_ap_tool" >/dev/null 2>&1 || return 1
  "$_ap_tool" -m owner -h >/dev/null 2>&1 || return 1
  _ap_probe_chain="DCMAP$_ap_family$$"
  _ap_fw "$_ap_tool" -t filter -N "$_ap_probe_chain" || return 1
  _ap_probe_ok=0
  _ap_fw "$_ap_tool" -t filter -A "$_ap_probe_chain" -m owner --uid-owner 0 -j RETURN && _ap_probe_ok=1
  _ap_fw "$_ap_tool" -t filter -F "$_ap_probe_chain" >/dev/null 2>&1
  _ap_fw "$_ap_tool" -t filter -X "$_ap_probe_chain" >/dev/null 2>&1
  [ "$_ap_probe_ok" = 1 ]
}

_ap_hook_active() {
  _ap_tool="$1"
  _ap_fw "$_ap_tool" -t filter -C OUTPUT -j "$AP_CHAIN"
}

app_policy_support() {
  ap_init
  _ap_json=0
  [ "${1:-}" = "--json" ] && _ap_json=1

  _ap_v4=no
  _ap_v6=no
  if [ "${DNSCRYPT_TEST_MODE:-0}" = 1 ] && [ "${DCM_AP_TEST_OWNER+x}" = x ]; then
    [ "$DCM_AP_TEST_OWNER" = yes ] && _ap_v4=yes
  elif _ap_probe_tool iptables 4; then
    _ap_v4=yes
  fi
  if [ "${DNSCRYPT_TEST_MODE:-0}" = 1 ] && [ "${DCM_AP_TEST_IPV6_OWNER+x}" = x ]; then
    [ "$DCM_AP_TEST_IPV6_OWNER" = yes ] && _ap_v6=yes
  elif [ "${DNSCRYPT_TEST_MODE:-0}" = 1 ] && [ "${DCM_AP_TEST_OWNER+x}" = x ]; then
    [ "$DCM_AP_TEST_OWNER" = yes ] && _ap_v6=yes
  elif _ap_probe_tool ip6tables 6; then
    _ap_v6=yes
  fi

  _ap_supported=false
  [ "$_ap_v4" = yes ] && [ "$_ap_v6" = yes ] && _ap_supported=true
  _ap_active=false
  if [ "$_ap_supported" = true ] && _ap_hook_active iptables && _ap_hook_active ip6tables; then
    _ap_active=true
  fi
  _ap_count=0
  [ -f "$AP_STATE" ] && _ap_count=$(awk -F '\t' '$2=="block-internet" && $3 ~ /^[0-9]+$/ {u[$3]=1} END {for (x in u) n++; print n+0}' "$AP_STATE" 2>/dev/null)

  if [ "$_ap_json" = 1 ]; then
    printf '{"supported":%s,"active":%s,"ipv4_owner":%s,"ipv6_owner":%s,"blocked_uid_count":%s,"domain_filter_per_app":false,"backend":"iptables-owner"}\n' \
      "$_ap_supported" "$_ap_active" \
      "$([ "$_ap_v4" = yes ] && echo true || echo false)" \
      "$([ "$_ap_v6" = yes ] && echo true || echo false)" "$_ap_count"
  else
    echo "iptables_owner_ipv4 : $_ap_v4"
    echo "iptables_owner_ipv6 : $_ap_v6"
    echo "per_uid_network     : $_ap_supported"
    echo "active              : $_ap_active"
    echo "blocked_uid_count   : $_ap_count"
    echo "domain_filter_per_app: unsupported (el filtro DNS no atribuye cada consulta a una app)"
    echo "note                : bloqueo saliente IPv4/IPv6; las reglas quedan apagadas si no hay soporte en ambas familias."
  fi
  [ "$_ap_supported" = true ]
}

_ap_remove_family() {
  _ap_tool="$1"
  command -v "$_ap_tool" >/dev/null 2>&1 || return 0
  _ap_removed=0
  while _ap_fw "$_ap_tool" -t filter -C OUTPUT -j "$AP_CHAIN"; do
    _ap_fw "$_ap_tool" -t filter -D OUTPUT -j "$AP_CHAIN" || { _ap_removed=1; break; }
  done
  if ! _ap_fw "$_ap_tool" -t filter -F "$AP_CHAIN"; then
    return "$_ap_removed"
  fi
  _ap_fw "$_ap_tool" -t filter -X "$AP_CHAIN" || _ap_removed=1
  [ "$_ap_removed" = 0 ]
}

app_policy_remove_rules() {
  _ap_remove_family iptables
  _ap_r4=$?
  _ap_remove_family ip6tables
  _ap_r6=$?
  [ "$_ap_r4" = 0 ] && [ "$_ap_r6" = 0 ]
}

_ap_apply_family() {
  _ap_tool="$1"; _ap_uids="$2"
  if [ ! -s "$_ap_uids" ]; then
    _ap_remove_family "$_ap_tool"
    return $?
  fi
  if ! _ap_fw "$_ap_tool" -t filter -N "$AP_CHAIN"; then
    _ap_fw "$_ap_tool" -t filter -F "$AP_CHAIN" || return 1
  fi
  _ap_fw "$_ap_tool" -t filter -F "$AP_CHAIN" || return 1
  _ap_fw "$_ap_tool" -t filter -A "$AP_CHAIN" -o lo -j RETURN || return 1
  while IFS= read -r _ap_uid; do
    _ap_valid_uid "$_ap_uid" || continue
    _ap_fw "$_ap_tool" -t filter -A "$AP_CHAIN" -m owner --uid-owner "$_ap_uid" -j REJECT || return 1
  done < "$_ap_uids"
  _ap_fw "$_ap_tool" -t filter -A "$AP_CHAIN" -j RETURN || return 1
  if ! _ap_fw "$_ap_tool" -t filter -C OUTPUT -j "$AP_CHAIN"; then
    _ap_fw "$_ap_tool" -t filter -I OUTPUT 1 -j "$AP_CHAIN" || return 1
  fi
  return 0
}

_ap_apply_state() {
  _ap_state_file="$1"
  if [ -f "$DISABLE_FLAG" ]; then
    app_policy_remove_rules
    return $?
  fi

  _ap_uids="$AP_DIR/blocked-uids.$$"
  : > "$_ap_uids"
  while IFS="$(printf '\t')" read -r _ap_pkg _ap_policy _ap_uid; do
    [ "$_ap_policy" = block-internet ] || continue
    _ap_valid_uid "$_ap_uid" && printf '%s\n' "$_ap_uid" >> "$_ap_uids"
  done < "$_ap_state_file"
  sort -u "$_ap_uids" > "$_ap_uids.sorted" 2>/dev/null && mv -f "$_ap_uids.sorted" "$_ap_uids"

  if _ap_apply_family iptables "$_ap_uids" && _ap_apply_family ip6tables "$_ap_uids"; then
    rm -f "$_ap_uids" "$_ap_uids.sorted" 2>/dev/null
    return 0
  fi
  # Si una familia no puede aplicarse, se retiran ambas cadenas propias para
  # evitar un bloqueo parcial y devolver conectividad en vez de dejar media regla.
  app_policy_remove_rules >/dev/null 2>&1
  rm -f "$_ap_uids" "$_ap_uids.sorted" 2>/dev/null
  return 1
}

_ap_uid_for_package() {
  _ap_pkg="$1"
  if [ "${DNSCRYPT_TEST_MODE:-0}" = 1 ] && [ -n "${DCM_AP_TEST_UID:-}" ]; then
    printf '%s\n' "$DCM_AP_TEST_UID"
    return 0
  fi
  command -v pm >/dev/null 2>&1 || return 1
  pm list packages -U 2>/dev/null | awk -v wanted="package:$_ap_pkg" '
    $1 == wanted {
      for (i=2; i<=NF; i++) if ($i ~ /^uid:[0-9]+$/) {
        sub(/^uid:/, "", $i); print $i; exit
      }
    }'
}

_ap_normalize_state() {
  _ap_source="$1"; _ap_dest="$2"
  _ap_package_map="$AP_DIR/packages.$$"
  : > "$_ap_package_map"
  if [ "${DNSCRYPT_TEST_MODE:-0}" = 1 ] && [ -n "${DCM_AP_TEST_UID:-}" ]; then
    while IFS="$(printf '\t')" read -r _ap_p _ap_pol _ap_olduid; do
      _ap_valid_package "$_ap_p" && printf '%s\t%s\n' "$_ap_p" "$DCM_AP_TEST_UID" >> "$_ap_package_map"
    done < "$_ap_source"
  elif command -v pm >/dev/null 2>&1; then
    pm list packages -U 2>/dev/null | awk '
      $1 ~ /^package:/ {
        p=$1; sub(/^package:/,"",p)
        for (i=2; i<=NF; i++) if ($i ~ /^uid:[0-9]+$/) {
          sub(/^uid:/,"",$i); print p "\t" $i; break
        }
      }' > "$_ap_package_map"
  fi

  : > "$_ap_dest"
  while IFS="$(printf '\t')" read -r _ap_pkg _ap_policy _ap_uid; do
    _ap_valid_package "$_ap_pkg" || continue
    case "$_ap_policy" in
      default|force-through-manager|allow-direct|block-external-dns|exempt-from-redirect|monitor-only|block-internet) : ;;
      *) continue ;;
    esac
    _ap_valid_uid "$_ap_uid" || continue
    if [ "$_ap_policy" = block-internet ]; then
      _ap_actual_uid=$(awk -F '\t' -v p="$_ap_pkg" '$1==p {print $2; exit}' "$_ap_package_map")
      [ "$_ap_actual_uid" = "$_ap_uid" ] || continue
    fi
    printf '%s\t%s\t%s\n' "$_ap_pkg" "$_ap_policy" "$_ap_uid" >> "$_ap_dest"
  done < "$_ap_source"
  chmod 0600 "$_ap_dest" 2>/dev/null
  rm -f "$_ap_package_map" 2>/dev/null
}

app_policy_restore() {
  ap_init
  if [ -f "$DISABLE_FLAG" ]; then
    app_policy_remove_rules
    return $?
  fi
  _ap_pending_count=$(awk -F '\t' '$2=="block-internet" {n++} END {print n+0}' "$AP_STATE" 2>/dev/null)
  if [ "${_ap_pending_count:-0}" = 0 ]; then
    app_policy_remove_rules
    return $?
  fi
  app_policy_support >/dev/null 2>&1 || {
    app_policy_remove_rules >/dev/null 2>&1 || true
    echo "result=unsupported"
    echo "note=No se aplicaron reglas: hacen falta owner-match verificado en IPv4 e IPv6."
    return 1
  }
  _ap_normalized="$AP_DIR/policies.normalized.$$"
  _ap_normalize_state "$AP_STATE" "$_ap_normalized"
  if ! _ap_apply_state "$_ap_normalized"; then
    rm -f "$_ap_normalized" 2>/dev/null
    echo "result=apply_failed"
    echo "note=Se retiraron las cadenas propias para conservar conectividad."
    return 1
  fi
  mv -f "$_ap_normalized" "$AP_STATE" 2>/dev/null || {
    rm -f "$_ap_normalized" 2>/dev/null
    return 1
  }
  echo "result=restored"
}

app_policy_list() {
  ap_init
  app_policy_restore >/dev/null 2>&1 || true
  if [ "${1:-}" = "--json" ]; then
    printf '{"policies":['
    _ap_first=1
    while IFS="$(printf '\t')" read -r _ap_pkg _ap_policy _ap_uid; do
      _ap_valid_package "$_ap_pkg" || continue
      case "$_ap_policy" in default|force-through-manager|allow-direct|block-external-dns|exempt-from-redirect|monitor-only|block-internet) : ;; *) continue ;; esac
      _ap_valid_uid "$_ap_uid" || continue
      [ "$_ap_first" = 1 ] || printf ','
      _ap_first=0
      printf '{"package":"%s","policy":"%s","uid":%s}' "$_ap_pkg" "$_ap_policy" "$_ap_uid"
    done < "$AP_STATE"
    printf ']}\n'
  else
    [ -s "$AP_STATE" ] && { echo "package	policy	uid"; cat "$AP_STATE"; } || echo "(sin politicas)"
  fi
}

app_policy_set() {
  ap_init
  _aps_pkg="$1"; _aps_policy="$2"
  _ap_valid_package "$_aps_pkg" || { echo "ERROR: package invalido" >&2; return 1; }
  [ "$_aps_policy" = block-internet ] || { echo "ERROR: politica invalida" >&2; return 1; }
  [ ! -f "$DISABLE_FLAG" ] || { echo "result=module_disabled"; echo "note=Activá el módulo antes de aplicar el firewall."; return 1; }
  app_policy_support >/dev/null 2>&1 || { echo "result=unsupported"; echo "note=Se requieren reglas owner verificadas en IPv4 e IPv6."; return 1; }
  _aps_uid=$(_ap_uid_for_package "$_aps_pkg")
  _ap_valid_uid "$_aps_uid" || { echo "result=uid_unresolved"; echo "note=No se resolvió un UID de aplicación válido."; return 1; }
  app_policy_restore >/dev/null 2>&1 || { echo "result=restore_failed"; return 1; }

  _aps_new="$AP_DIR/policies.new.$$"
  awk -F '\t' -v p="$_aps_pkg" '$1 != p {print}' "$AP_STATE" > "$_aps_new"
  printf '%s\tblock-internet\t%s\n' "$_aps_pkg" "$_aps_uid" >> "$_aps_new"
  chmod 0600 "$_aps_new" 2>/dev/null
  if ! _ap_apply_state "$_aps_new"; then
    rm -f "$_aps_new" 2>/dev/null
    _ap_apply_state "$AP_STATE" >/dev/null 2>&1 || app_policy_remove_rules >/dev/null 2>&1
    echo "result=apply_failed"
    echo "note=No se aplicó el cambio; se restauró la regla anterior o se retiraron las cadenas propias."
    return 1
  fi
  if ! mv -f "$_aps_new" "$AP_STATE" 2>/dev/null; then
    _ap_apply_state "$AP_STATE" >/dev/null 2>&1 || app_policy_remove_rules >/dev/null 2>&1
    echo "result=state_write_failed"
    return 1
  fi
  command -v log_msg >/dev/null 2>&1 && log_msg "app-policy block-internet $_aps_pkg uid=$_aps_uid (applied)" 2>/dev/null
  echo "result=applied package=$_aps_pkg uid=$_aps_uid"
}

app_policy_clear() {
  ap_init
  _apc_pkg="$1"
  _ap_valid_package "$_apc_pkg" || { echo "ERROR: package invalido" >&2; return 1; }
  app_policy_restore >/dev/null 2>&1 || true
  _apc_new="$AP_DIR/policies.new.$$"
  awk -F '\t' -v p="$_apc_pkg" '$1 != p {print}' "$AP_STATE" > "$_apc_new"
  chmod 0600 "$_apc_new" 2>/dev/null
  if ! app_policy_support >/dev/null 2>&1; then
    app_policy_remove_rules >/dev/null 2>&1 || {
      rm -f "$_apc_new" 2>/dev/null
      echo "result=clear_failed"
      echo "note=No se confirmó la retirada de las reglas propias del firewall."
      return 1
    }
    mv -f "$_apc_new" "$AP_STATE" 2>/dev/null || { rm -f "$_apc_new" 2>/dev/null; return 1; }
    echo "cleared=$_apc_pkg"
    echo "note=Sin soporte IPv4 e IPv6, las reglas activas propias se retiraron."
    return 0
  fi
  if ! _ap_apply_state "$_apc_new"; then
    rm -f "$_apc_new" 2>/dev/null
    _ap_apply_state "$AP_STATE" >/dev/null 2>&1 || app_policy_remove_rules >/dev/null 2>&1
    echo "result=clear_failed"
    echo "note=No se pudo modificar la regla; las cadenas propias se retiraron para conservar conectividad."
    return 1
  fi
  mv -f "$_apc_new" "$AP_STATE" 2>/dev/null || { _ap_apply_state "$AP_STATE" >/dev/null 2>&1; return 1; }
  echo "cleared=$_apc_pkg"
}

app_policy_clear_all() {
  ap_init
  _apca_new="$AP_DIR/policies.empty.$$"
  : > "$_apca_new"
  chmod 0600 "$_apca_new" 2>/dev/null
  if ! _ap_apply_state "$_apca_new"; then
    rm -f "$_apca_new" 2>/dev/null
    _ap_apply_state "$AP_STATE" >/dev/null 2>&1 || app_policy_remove_rules >/dev/null 2>&1
    echo "result=clear_failed"
    echo "note=Se retiraron las cadenas propias para devolver conectividad."
    return 1
  fi
  mv -f "$_apca_new" "$AP_STATE" 2>/dev/null || return 1
  echo "result=cleared_all"
}

app_policy_reset() {
  ap_init
  app_policy_remove_rules
  _ap_remove_status=$?
  : > "$AP_STATE"
  chmod 0600 "$AP_STATE" 2>/dev/null
  echo "result=reset"
  [ "$_ap_remove_status" = 0 ]
}
