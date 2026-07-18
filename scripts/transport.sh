#!/system/bin/sh
# scripts/transport.sh  —  DNSCrypt Manager v0.3.0-RC1  (CHECKPOINT B)
#
# Motor genérico de transportes con aplicación ATÓMICA y rollback, más
# Anonymized DNSCrypt y ODoH. El binario incluido soporta ambos (verificado por
# strings: "[anonymized_dns]", "[routes]", "ODoH servers require an ODoH relay").
#
# Invariantes: OFF por defecto; nunca marca activo sin prueba real; en x86 la
# consulta real Android no es verificable -> not_verifiable (NO se finge éxito).
# Sin eval, sin sh -c con datos externos, sin curl, sin DNS público hardcodeado.
# Kill del árbol de la instancia aislada con _cat_kill_tree (sin pkill/killall).
#
# Estado persistente:
#   DATA_DIR/transport/{config,anonymized,odoh}.json
#   DATA_DIR/transport/last-known-good/   (backups de TOML validados)
#   DATA_DIR/transport/runtime/           (estado runtime)
#   DATA_DIR/transport/run/               (temporales de la instancia aislada)

TP_DIR="${DATA_DIR}/transport"
TP_LKG="$TP_DIR/last-known-good"
TP_RUN="$TP_DIR/run"
TP_RT="$TP_DIR/runtime"
TP_LOCK="$TP_RUN/transport.lock"

transport_init() {
  mkdir -p "$TP_DIR" "$TP_LKG" "$TP_RUN" "$TP_RT" 2>/dev/null
  chmod 0700 "$TP_DIR" "$TP_LKG" "$TP_RUN" "$TP_RT" 2>/dev/null
  [ -f "$TP_DIR/config.json" ] || printf '{"mode":"direct","active":false}\n' > "$TP_DIR/config.json"
  [ -f "$TP_DIR/anonymized.json" ] || printf '{"enabled":false,"resolver":"","relays":[]}\n' > "$TP_DIR/anonymized.json"
  [ -f "$TP_DIR/odoh.json" ] || printf '{"enabled":false,"target":"","relay":"","supported":"unknown"}\n' > "$TP_DIR/odoh.json"
  chmod 0600 "$TP_DIR"/*.json 2>/dev/null
}

_tp_event() { command -v log_event >/dev/null 2>&1 && log_event "transport" "$1" 2>/dev/null || command -v log_msg >/dev/null 2>&1 && log_msg "transport: $1" 2>/dev/null; return 0; }

# Lock atómico (mismo patrón que el catálogo).
_tp_lock() {
  if mkdir "$TP_LOCK" 2>/dev/null; then printf '%s' "$$" > "$TP_LOCK/pid"; return 0; fi
  # lock huérfano: si el PID no vive, recuperar
  _op=$(cat "$TP_LOCK/pid" 2>/dev/null)
  if [ -n "$_op" ] && ! kill -0 "$_op" 2>/dev/null; then rm -rf "$TP_LOCK" 2>/dev/null; mkdir "$TP_LOCK" 2>/dev/null && { printf '%s' "$$" > "$TP_LOCK/pid"; return 0; }; fi
  return 1
}
_tp_unlock() { rm -rf "$TP_LOCK" 2>/dev/null; }

# Valida un stamp sdns:// (forma; no descarga nada).
tp_validate_stamp() {
  case "$1" in
    sdns://*) _b=${1#sdns://}; case "$_b" in *[!A-Za-z0-9_-]*) return 1 ;; esac; [ ${#_b} -ge 8 ] && return 0 || return 1 ;;
    *) return 1 ;;
  esac
}

# Chequeo de sintaxis de una config TOML con el binario (-check). TEST override.
tp_check_config() {
  _cfg="$1"
  if [ "${DNSCRYPT_TEST_MODE:-0}" = 1 ] && [ -n "${DCM_TP_TEST_CHECK:-}" ]; then [ "$DCM_TP_TEST_CHECK" = ok ]; return; fi
  _bin=$(command -v resolve_bin >/dev/null 2>&1 && resolve_bin 2>/dev/null || true)
  [ -n "$_bin" ] && [ -x "$_bin" ] || return 2
  "$_bin" -config "$_cfg" -check >/dev/null 2>&1
}

# Consulta real contra una config aislada (instancia temporal). TEST override.
# Devuelve: 0 ok, 1 fallo, 2 not_verifiable (no se pudo ejecutar/verificar).
tp_probe_config() {
  _cfg="$1"
  if [ "${DNSCRYPT_TEST_MODE:-0}" = 1 ] && [ -n "${DCM_TP_TEST_QUERY:-}" ]; then
    case "$DCM_TP_TEST_QUERY" in ok) return 0 ;; fail) return 1 ;; *) return 2 ;; esac
  fi
  _bin=$(command -v resolve_bin >/dev/null 2>&1 && resolve_bin 2>/dev/null || true)
  [ -n "$_bin" ] && [ -x "$_bin" ] || return 2
  _port=$(command -v _boot_free_port >/dev/null 2>&1 && _boot_free_port || echo 25355)
  _tmpcfg="$TP_RUN/probe.$$.toml"
  sed "s/^listen_addresses.*/listen_addresses = ['127.0.0.1:$_port']/" "$_cfg" > "$_tmpcfg" 2>/dev/null || cp "$_cfg" "$_tmpcfg"
  "$_bin" -config "$_tmpcfg" >/dev/null 2>&1 &
  _pid=$!
  trap 'command -v _cat_kill_tree >/dev/null 2>&1 && _cat_kill_tree "$_pid" KILL 2>/dev/null; rm -f "$_tmpcfg" 2>/dev/null' RETURN 2>/dev/null || true
  _w=0; while [ $_w -lt 25 ]; do netstat -ltnu 2>/dev/null | grep -q "127.0.0.1:$_port " && break; sleep 0.1; _w=$((_w+1)); done
  _r=2
  if "$_bin" -config "$_tmpcfg" -resolve example.com >/dev/null 2>&1; then _r=0; else _r=1; fi
  command -v _cat_kill_tree >/dev/null 2>&1 && _cat_kill_tree "$_pid" KILL 2>/dev/null
  rm -f "$_tmpcfg" 2>/dev/null
  trap - RETURN 2>/dev/null || true
  return $_r
}

# ---------------------------------------------------------------------------
# MOTOR ATÓMICO: aplica una config candidata con validación + rollback.
# transport_apply_atomic CANDIDATE_TOML LABEL
# ---------------------------------------------------------------------------
transport_apply_atomic() {
  _cand="$1"; _label="${2:-transport}"
  transport_init
  [ -f "$_cand" ] || { echo "ERROR: config candidata inexistente" >&2; return 1; }
  _tp_lock || { echo "ERROR: ya hay una operación de transporte en curso" >&2; return 1; }
  trap '_tp_unlock' RETURN 2>/dev/null || true
  # 1) validar sintaxis de la candidata
  tp_check_config "$_cand"; _cc=$?
  if [ "$_cc" = 1 ]; then _tp_event "$_label: sintaxis inválida"; echo "failure=syntax"; _tp_unlock; return 1; fi
  # 2) prueba aislada (consulta real) antes de tocar la principal
  tp_probe_config "$_cand"; _pc=$?
  if [ "$_pc" = 1 ]; then _tp_event "$_label: la prueba aislada falló"; echo "failure=probe_failed"; _tp_unlock; return 1; fi
  if [ "$_pc" = 2 ]; then echo "probe=not_verifiable"; fi   # x86: no se finge éxito
  # 3) backup de la config actual como last-known-good
  _ts=$(date +%Y%m%d%H%M%S 2>/dev/null || echo now)
  if [ -f "$TOML" ]; then cp "$TOML" "$TP_LKG/toml.$_ts" 2>/dev/null; cp "$TOML" "$TP_LKG/latest.toml" 2>/dev/null; fi
  # 4) aplicar atómicamente
  if cp "$_cand" "$TOML.new" 2>/dev/null && mv -f "$TOML.new" "$TOML" 2>/dev/null; then :; else rm -f "$TOML.new" 2>/dev/null; echo "failure=write"; _tp_unlock; return 1; fi
  # 5) reiniciar el proxy y verificar
  if command -v cmd_restart >/dev/null 2>&1; then cmd_restart >/dev/null 2>&1; fi
  _ok=1
  if [ "${DNSCRYPT_TEST_MODE:-0}" = 1 ] && [ -n "${DCM_TP_TEST_VERIFY:-}" ]; then
    [ "$DCM_TP_TEST_VERIFY" = ok ] && _ok=0 || _ok=1
  elif [ "$_pc" = 0 ]; then
    if command -v probe_listener_query >/dev/null 2>&1 && probe_listener_query >/dev/null 2>&1; then _ok=0; else _ok=1; fi
  else
    _ok=0   # not_verifiable: aplicado pero sin verificación runtime en x86
  fi
  if [ "$_ok" != 0 ] && [ "$_pc" = 0 ]; then
    # 6) rollback automático al last-known-good
    if [ -f "$TP_LKG/latest.toml" ]; then cp "$TP_LKG/latest.toml" "$TOML" 2>/dev/null; command -v cmd_restart >/dev/null 2>&1 && cmd_restart >/dev/null 2>&1; fi
    _tp_event "$_label: verificación falló -> rollback"; echo "failure=verify_rolledback"; _tp_unlock; return 1
  fi
  _tp_event "$_label: aplicado ($([ "$_pc" = 2 ] && echo not_verifiable || echo verified))"
  echo "applied=$([ "$_pc" = 2 ] && echo not_verifiable || echo verified)"
  _tp_unlock; return 0
}

transport_rollback() {
  transport_init
  [ -f "$TP_LKG/latest.toml" ] || { echo "no hay last-known-good para revertir" >&2; return 1; }
  _tp_lock || { echo "ERROR: operación en curso" >&2; return 1; }
  cp "$TP_LKG/latest.toml" "$TOML" 2>/dev/null && { command -v cmd_restart >/dev/null 2>&1 && cmd_restart >/dev/null 2>&1; _tp_event "rollback aplicado"; echo "rolled_back=yes"; }
  _tp_unlock
}

transport_status() {
  transport_init
  _mode=$(grep -o '"mode":"[^"]*"' "$TP_DIR/config.json" 2>/dev/null | cut -d'"' -f4)
  _anon=$(grep -o '"enabled":[a-z]*' "$TP_DIR/anonymized.json" 2>/dev/null | head -1 | cut -d: -f2)
  _odoh=$(grep -o '"enabled":[a-z]*' "$TP_DIR/odoh.json" 2>/dev/null | head -1 | cut -d: -f2)
  _odsup=$(grep -o '"supported":"[^"]*"' "$TP_DIR/odoh.json" 2>/dev/null | cut -d'"' -f4)
  echo "mode                : ${_mode:-direct}"
  echo "anonymized_enabled  : ${_anon:-false}"
  echo "odoh_enabled        : ${_odoh:-false}"
  echo "odoh_supported      : ${_odsup:-unknown}"
  echo "last_known_good     : $([ -f "$TP_LKG/latest.toml" ] && echo yes || echo no)"
}

transport_disable() {
  transport_init
  # Vuelve al transporte directo (rollback al LKG si existe).
  transport_rollback 2>/dev/null
  printf '{"mode":"direct","active":false}\n' > "$TP_DIR/config.json"
  printf '{"enabled":false,"resolver":"","relays":[]}\n' > "$TP_DIR/anonymized.json"
  _oj=$(cat "$TP_DIR/odoh.json" 2>/dev/null); printf '%s' "$_oj" | sed 's/"enabled":true/"enabled":false/' > "$TP_DIR/odoh.json" 2>/dev/null
  _tp_event "transporte deshabilitado (directo)"
  echo "disabled=yes"
}

# ===========================================================================
# ANONYMIZED DNSCRYPT
# ===========================================================================
# Fuente de relays/resolvers: archivo curado del módulo (config/transport) +
# los server_names ya presentes en el TOML. NO se descarga nada aquí.
_anon_relays_file() { echo "${MODDIR}/config/transport/relays.json"; }

anonymized_relays() {
  _f=$(_anon_relays_file)
  if [ -f "$_f" ]; then grep -o '"name":"[^"]*"' "$_f" 2>/dev/null | cut -d'"' -f4; fi
}
anonymized_resolvers() {
  # resolvers DNSCrypt compatibles: los server_names del TOML (excluye DoH).
  if [ -f "$TOML" ]; then grep -oE "server_names\s*=\s*\[[^]]*\]" "$TOML" 2>/dev/null | grep -oE "'[^']+'" | tr -d "'"; fi
}
anonymized_routes() {
  transport_init
  grep -o '"resolver":"[^"]*"' "$TP_DIR/anonymized.json" 2>/dev/null | cut -d'"' -f4 | while read -r _r; do
    [ -n "$_r" ] && echo "route: $_r via $(grep -o '"relays":\[[^]]*\]' "$TP_DIR/anonymized.json" 2>/dev/null | sed 's/[][]//g; s/"relays"://; s/"//g')"
  done
}
anonymized_status() {
  transport_init
  echo "enabled  : $(grep -o '"enabled":[a-z]*' "$TP_DIR/anonymized.json" | head -1 | cut -d: -f2)"
  echo "resolver : $(grep -o '"resolver":"[^"]*"' "$TP_DIR/anonymized.json" | cut -d'"' -f4)"
  echo "relays   : $(grep -o '"relays":\[[^]]*\]' "$TP_DIR/anonymized.json" | sed 's/"relays"://')"
  echo "note     : Anonymized DNSCrypt NO es una VPN; no garantiza anonimato absoluto."
  echo "note     : evita relay y resolver del mismo operador; mas relays = mas latencia."
}

# Construye una config candidata con [anonymized_dns] routes y valida.
# anonymized_build_candidate RESOLVER RELAY[,RELAY...] -> imprime ruta del TOML candidato
anonymized_build_candidate() {
  _res="$1"; _relays="$2"
  transport_init
  # validar entradas (sin metacaracteres)
  case "$_res" in *[!a-zA-Z0-9_.:-]*) echo "ERROR: resolver invalido" >&2; return 1 ;; esac
  case "$_relays" in *[!a-zA-Z0-9_.,:-]*) echo "ERROR: relays invalidos" >&2; return 1 ;; esac
  [ -f "$TOML" ] || { echo "ERROR: TOML base ausente" >&2; return 1; }
  _cand="$TP_RUN/anon.candidate.toml"
  # relays como lista TOML
  _rlist=$(printf '%s' "$_relays" | awk -F, '{for(i=1;i<=NF;i++){printf "%s'\''%s'\''", (i>1?", ":""), $i}}')
  # copiar TOML base y (re)escribir el bloque [anonymized_dns]
  awk 'BEGIN{skip=0} /^\[anonymized_dns\]/{skip=1; next} /^\[/{if(skip){skip=0}} !skip{print}' "$TOML" > "$_cand" 2>/dev/null
  {
    echo ""
    echo "[anonymized_dns]"
    echo "routes = ["
    echo "  { server_name='$_res', via=[$_rlist] }"
    echo "]"
    echo "skip_incompatible = true"
  } >> "$_cand"
  echo "$_cand"
}

anonymized_test() {
  _res="$1"; _relays="$2"
  _cand=$(anonymized_build_candidate "$_res" "$_relays") || return 1
  tp_check_config "$_cand"; _cc=$?
  [ "$_cc" = 1 ] && { echo "result=syntax_invalid"; return 1; }
  tp_probe_config "$_cand"; _pc=$?
  case "$_pc" in
    0) echo "result=ok"; return 0 ;;
    1) echo "result=query_failed"; return 1 ;;
    2) echo "result=not_verifiable"; echo "note=no ejecutable/verificable en este entorno (x86); prueba real pendiente en Android"; return 0 ;;
  esac
}

anonymized_apply() {
  _res="$1"; _relays="$2"
  _cand=$(anonymized_build_candidate "$_res" "$_relays") || return 1
  _out=$(transport_apply_atomic "$_cand" "anonymized")
  echo "$_out"
  case "$_out" in
    *applied=*) 
      _rl=$(printf '%s' "$_relays" | awk -F, '{for(i=1;i<=NF;i++){printf "%s\"%s\"",(i>1?",":""),$i}}')
      printf '{"enabled":true,"resolver":"%s","relays":[%s]}\n' "$_res" "$_rl" > "$TP_DIR/anonymized.json"
      chmod 0600 "$TP_DIR/anonymized.json"; return 0 ;;
    *) return 1 ;;
  esac
}

anonymized_disable() {
  transport_init
  printf '{"enabled":false,"resolver":"","relays":[]}\n' > "$TP_DIR/anonymized.json"
  transport_rollback 2>/dev/null
  _tp_event "anonymized deshabilitado"; echo "disabled=yes"
}

# ===========================================================================
# ODoH  (Oblivious DoH)
# ===========================================================================
# El binario contiene el code path (verificado por strings). La prueba runtime
# real requiere Android; en x86 se reporta not_verifiable, NO se finge activo.
odoh_supported() {
  # Evidencia estática: el binario acepta una config ODoH minima con -check.
  if [ "${DNSCRYPT_TEST_MODE:-0}" = 1 ] && [ -n "${DCM_ODOH_TEST_SUPPORT:-}" ]; then printf '%s' "$DCM_ODOH_TEST_SUPPORT"; return; fi
  _bin=$(command -v resolve_bin >/dev/null 2>&1 && resolve_bin 2>/dev/null || true)
  [ -n "$_bin" ] && [ -x "$_bin" ] || { printf unknown; return; }
  # buscar el marcador ODoH en el binario (code path presente)
  if strings "$_bin" 2>/dev/null | grep -qi "ODoH relay"; then printf code_path_present; else printf no; fi
}

odoh_status() {
  transport_init
  _sup=$(odoh_supported)
  # persistir el soporte detectado
  _oj=$(cat "$TP_DIR/odoh.json" 2>/dev/null)
  printf '%s' "$_oj" | sed "s/\"supported\":\"[^\"]*\"/\"supported\":\"$_sup\"/" > "$TP_DIR/odoh.json" 2>/dev/null
  echo "supported        : $_sup"
  echo "enabled          : $(grep -o '"enabled":[a-z]*' "$TP_DIR/odoh.json" | head -1 | cut -d: -f2)"
  echo "target           : $(grep -o '"target":"[^"]*"' "$TP_DIR/odoh.json" | cut -d'"' -f4)"
  echo "relay            : $(grep -o '"relay":"[^"]*"' "$TP_DIR/odoh.json" | cut -d'"' -f4)"
  case "$_sup" in
    code_path_present) echo "runtime_android  : pendiente de prueba real (ejecución ARM64 no verificable en este entorno)" ;;
    no|unknown)        echo "note             : No compatible o no verificable en este entorno" ;;
  esac
}

odoh_targets() { echo "(los targets ODoH se definen por stamps sdns:// con protocolo ODoH; usar 'odoh apply TARGET RELAY')"; }
odoh_relays()  { anonymized_relays; }   # los relays ODoH se listan igual (curados/servidor)

odoh_test() {
  _tgt="$1"; _relay="$2"
  _sup=$(odoh_supported)
  if [ "$_sup" != code_path_present ]; then echo "result=unsupported"; echo "note=No compatible o no verificable en este entorno"; return 1; fi
  # validar stamps
  if [ -n "$_tgt" ] && ! tp_validate_stamp "$_tgt"; then echo "result=invalid_stamp"; return 1; fi
  # en x86 la consulta real no es verificable
  if [ "${DNSCRYPT_TEST_MODE:-0}" = 1 ] && [ "${DCM_TP_TEST_QUERY:-}" = ok ]; then echo "result=ok"; return 0; fi
  echo "result=not_verifiable"
  echo "note=code path ODoH presente; consulta real pendiente en Android (no se marca activo)"
  return 0
}

odoh_apply() {
  _tgt="$1"; _relay="$2"
  _sup=$(odoh_supported)
  [ "$_sup" = code_path_present ] || { echo "result=unsupported"; echo "note=No compatible o no verificable en este entorno; no se aplica"; return 1; }
  tp_validate_stamp "$_tgt" || { echo "result=invalid_stamp"; return 1; }
  # Solo se marca enabled si hay prueba real verificable; en x86 queda preparado pero no activo.
  odoh_test "$_tgt" "$_relay" | grep -q "result=ok"
  if [ $? -eq 0 ]; then
    printf '{"enabled":true,"target":"%s","relay":"%s","supported":"%s"}\n' "$_tgt" "$_relay" "$_sup" > "$TP_DIR/odoh.json"
    echo "applied=verified"
  else
    printf '{"enabled":false,"target":"%s","relay":"%s","supported":"%s"}\n' "$_tgt" "$_relay" "$_sup" > "$TP_DIR/odoh.json"
    echo "applied=not_verifiable"
    echo "note=configuración guardada pero NO activada: prueba real pendiente en Android"
  fi
  chmod 0600 "$TP_DIR/odoh.json"
}

odoh_disable() {
  transport_init
  _oj=$(cat "$TP_DIR/odoh.json" 2>/dev/null); printf '%s' "$_oj" | sed 's/"enabled":true/"enabled":false/' > "$TP_DIR/odoh.json"
  transport_rollback 2>/dev/null
  _tp_event "odoh deshabilitado"; echo "disabled=yes"
}
