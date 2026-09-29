#!/system/bin/sh
# Politica experimental de firewall saliente por UID.
# Solo usa cadenas propias y requiere owner de iptables en IPv4 e IPv6.
AP_DIR="${DATA_DIR}/apppolicy"
AP_STATE="$AP_DIR/policies.tsv"
AP_TEMP_STATE="$AP_DIR/temporary.tsv"
AP_PROFILES_STATE="$AP_DIR/profiles.tsv"
AP_CHAIN="DCM_APP_OUT"

ap_init() {
  mkdir -p "$AP_DIR" 2>/dev/null
  chmod 0700 "$AP_DIR" 2>/dev/null
  [ -f "$AP_STATE" ] || : > "$AP_STATE"
  [ -f "$AP_TEMP_STATE" ] || : > "$AP_TEMP_STATE"
  [ -f "$AP_PROFILES_STATE" ] || : > "$AP_PROFILES_STATE"
  chmod 0600 "$AP_STATE" 2>/dev/null
  chmod 0600 "$AP_TEMP_STATE" 2>/dev/null
  chmod 0600 "$AP_PROFILES_STATE" 2>/dev/null
}

_ap_temp_remove() {
  _apt_pkg="$1"
  [ -f "$AP_TEMP_STATE" ] || return 0
  _apt_new="$AP_DIR/temporary.new.$$"
  awk -F '\t' -v p="$_apt_pkg" '$1 != p {print}' "$AP_TEMP_STATE" > "$_apt_new" || { rm -f "$_apt_new"; return 1; }
  chmod 0600 "$_apt_new" 2>/dev/null
  mv -f "$_apt_new" "$AP_TEMP_STATE"
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
  app_policy_sweep >/dev/null 2>&1 || true
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
      _ap_expires=$(awk -F '\t' -v p="$_ap_pkg" '$1==p && $2 ~ /^[0-9]+$/ {print $2; exit}' "$AP_TEMP_STATE" 2>/dev/null)
      case "$_ap_expires" in ''|*[!0-9]*) _ap_expires=0 ;; esac
      printf '{"package":"%s","policy":"%s","uid":%s,"expires_at":%s}' "$_ap_pkg" "$_ap_policy" "$_ap_uid" "$_ap_expires"
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
  _ap_temp_remove "$_aps_pkg" >/dev/null 2>&1 || true
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
    _ap_temp_remove "$_apc_pkg" >/dev/null 2>&1 || true
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
  _ap_temp_remove "$_apc_pkg" >/dev/null 2>&1 || true
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
  : > "$AP_TEMP_STATE"
  chmod 0600 "$AP_TEMP_STATE" 2>/dev/null
  echo "result=cleared_all"
}

_ap_now() {
  if [ "${DNSCRYPT_TEST_MODE:-0}" = 1 ] && [ "${DCM_AP_TEST_NOW:-}" -gt 0 ] 2>/dev/null; then
    echo "$DCM_AP_TEST_NOW"
  else
    date '+%s' 2>/dev/null
  fi
}

app_policy_temp_block() {
  _apt_pkg="$1"; _apt_duration="$2"
  _ap_valid_package "$_apt_pkg" || { echo "ERROR: package invalido" >&2; return 1; }
  case "$_apt_duration" in
    15m) _apt_seconds=900 ;;
    1h) _apt_seconds=3600 ;;
    8h) _apt_seconds=28800 ;;
    *) echo "ERROR: duracion invalida (usa 15m, 1h o 8h)" >&2; return 1 ;;
  esac
  _apt_now=$(_ap_now)
  case "$_apt_now" in ''|*[!0-9]*) echo "ERROR: no se pudo leer la hora del sistema" >&2; return 1 ;; esac
  _apt_expiry=$((_apt_now + _apt_seconds))
  app_policy_set "$_apt_pkg" block-internet || return 1
  _apt_new="$AP_DIR/temporary.new.$$"
  { awk -F '\t' -v p="$_apt_pkg" '$1 != p {print}' "$AP_TEMP_STATE" 2>/dev/null
    printf '%s\t%s\n' "$_apt_pkg" "$_apt_expiry"
  } > "$_apt_new" || { rm -f "$_apt_new"; app_policy_clear "$_apt_pkg" >/dev/null 2>&1; return 1; }
  chmod 0600 "$_apt_new" 2>/dev/null
  if ! mv -f "$_apt_new" "$AP_TEMP_STATE"; then
    rm -f "$_apt_new"
    app_policy_clear "$_apt_pkg" >/dev/null 2>&1
    echo "ERROR: no se pudo guardar el vencimiento" >&2
    return 1
  fi
  if [ "${DNSCRYPT_TEST_MODE:-0}" != 1 ]; then
    ( sleep "$_apt_seconds"; sh "$DCM_SELF" app-policy sweep >/dev/null 2>&1 ) >/dev/null 2>&1 &
  fi
  echo "result=applied_temporarily package=$_apt_pkg expires_at=$_apt_expiry"
}

app_policy_sweep() {
  [ "${_AP_SWEEP_GUARD:-0}" != 1 ] || return 0
  _AP_SWEEP_GUARD=1
  ap_init
  _aps_now=$(_ap_now)
  case "$_aps_now" in ''|*[!0-9]*) unset _AP_SWEEP_GUARD; return 1 ;; esac
  [ -s "$AP_TEMP_STATE" ] || { unset _AP_SWEEP_GUARD; return 0; }
  _aps_expired="$AP_DIR/expired.$$"
  while IFS="$(printf '\t')" read -r _aps_sweep_pkg _aps_sweep_expiry; do
    _ap_valid_package "$_aps_sweep_pkg" || continue
    case "$_aps_sweep_expiry" in ''|*[!0-9]*) _aps_sweep_expiry=0 ;; esac
    if [ "$_aps_sweep_expiry" -le "$_aps_now" ] 2>/dev/null; then
      printf '%s\n' "$_aps_sweep_pkg" >> "$_aps_expired"
    fi
  done < "$AP_TEMP_STATE"
  if [ -s "$_aps_expired" ]; then
    while IFS= read -r _aps_sweep_pkg; do
      app_policy_clear "$_aps_sweep_pkg" >/dev/null 2>&1 || { rm -f "$_aps_expired"; unset _AP_SWEEP_GUARD; return 1; }
    done < "$_aps_expired"
    echo "result=expired_rules_cleared"
  fi
  rm -f "$_aps_expired" 2>/dev/null
  unset _AP_SWEEP_GUARD
}

_ap_valid_profile_name() {
  [ "${#1}" -ge 1 ] && [ "${#1}" -le 32 ] || return 1
  case "$1" in *"  "*) return 1 ;; esac
  [ "$(LC_ALL=C printf '%s' "$1" | tr -cd 'A-Za-z0-9 _-')" = "$1" ] || return 1
  case "$1" in " "*|*" ") return 1 ;; esac
  return 0
}

_ap_valid_package_csv() {
  _apvc_rest="$1"
  [ -n "$_apvc_rest" ] || return 0
  while [ -n "$_apvc_rest" ]; do
    case "$_apvc_rest" in *,*) _apvc_pkg=${_apvc_rest%%,*}; _apvc_rest=${_apvc_rest#*,} ;; *) _apvc_pkg=$_apvc_rest; _apvc_rest="" ;; esac
    _ap_valid_package "$_apvc_pkg" || return 1
  done
}

app_policy_profiles() {
  ap_init
  _app_sub="$1"; shift 2>/dev/null
  case "$_app_sub" in
    list)
      if [ "${1:-}" = "--json" ]; then
        printf '{"profiles":['; _app_first=1
        while IFS="$(printf '\t')" read -r _app_name _app_packages; do
          _ap_valid_profile_name "$_app_name" || continue
          [ "$_app_first" = 1 ] || printf ','; _app_first=0
          printf '{"name":"%s","packages":[' "$_app_name"
          _app_comma=; _app_rest="$_app_packages"
          while [ -n "$_app_rest" ]; do
            case "$_app_rest" in *,*) _app_pkg=${_app_rest%%,*}; _app_rest=${_app_rest#*,} ;; *) _app_pkg=$_app_rest; _app_rest="" ;; esac
            _ap_valid_package "$_app_pkg" || continue
            printf '%s"%s"' "$_app_comma" "$_app_pkg"; _app_comma=,
          done
          printf ']}'
        done < "$AP_PROFILES_STATE"
        printf ']}\n'
      else
        [ -s "$AP_PROFILES_STATE" ] && cat "$AP_PROFILES_STATE" || echo "(sin perfiles)"
      fi ;;
    save)
      _app_name="${1:-}"; _app_packages="${2:-}"
      _ap_valid_profile_name "$_app_name" || { echo "ERROR: nombre de perfil inválido" >&2; return 1; }
      _ap_valid_package_csv "$_app_packages" || { echo "ERROR: lista de paquetes inválida" >&2; return 1; }
      _app_new="$AP_DIR/profiles.new.$$"
      awk -F '\t' -v n="$_app_name" '$1 != n {print}' "$AP_PROFILES_STATE" > "$_app_new" || { rm -f "$_app_new"; return 1; }
      printf '%s\t%s\n' "$_app_name" "$_app_packages" >> "$_app_new"
      [ "$(wc -l < "$_app_new" | tr -d ' ')" -le 20 ] || { rm -f "$_app_new"; echo "ERROR: máximo 20 perfiles" >&2; return 1; }
      chmod 0600 "$_app_new" 2>/dev/null; mv -f "$_app_new" "$AP_PROFILES_STATE" || return 1
      echo "result=saved name=$_app_name" ;;
    remove)
      _app_name="${1:-}"
      _ap_valid_profile_name "$_app_name" || { echo "ERROR: nombre de perfil inválido" >&2; return 1; }
      _app_new="$AP_DIR/profiles.new.$$"
      awk -F '\t' -v n="$_app_name" '$1 != n {print}' "$AP_PROFILES_STATE" > "$_app_new" || { rm -f "$_app_new"; return 1; }
      chmod 0600 "$_app_new" 2>/dev/null; mv -f "$_app_new" "$AP_PROFILES_STATE" || return 1
      echo "result=removed name=$_app_name" ;;
    *) echo "Uso: app-policy profile list [--json]|save NAME PACKAGE[,PACKAGE...]|remove NAME" >&2; return 1 ;;
  esac
}

app_policy_reset() {
  ap_init
  app_policy_remove_rules
  _ap_remove_status=$?
  : > "$AP_STATE"
  : > "$AP_TEMP_STATE"
  chmod 0600 "$AP_STATE" 2>/dev/null
  chmod 0600 "$AP_TEMP_STATE" 2>/dev/null
  echo "result=reset"
  [ "$_ap_remove_status" = 0 ]
}
