#!/system/bin/sh
##############################################################################
# DNSCrypt Manager - scripts/security.sh
# Creado por Skaymer AR
#
# Libreria de la capa de seguridad (v0.2.0). La sourcea la CLI, igual que
# common.sh y validate-binary.sh. NO ejecutable sola. POSIX puro.
#
# Contiene:
#   - Blocklists por categoria con pipeline de actualizacion verificada
#     (descarga -> validacion -> -check -> backup -> reemplazo atomico ->
#     prueba DNS -> rollback automatico).
#   - Allowlist local + excepciones temporales con expiracion sin cron.
#   - Perfiles de seguridad (equilibrado / estricto / privacidad).
#   - Modo fail-closed OPCIONAL (opt-in, cadenas/tabla propias, idempotente,
#     jamas bloquea loopback ni la recuperacion root).
#   - Detector de fugas DNS (estados: protegido / posible_fuga /
#     no_verificable / conflicto / fallo; nunca afirma lo que no puede probar).
#   - Eventos de bloqueo ("por que fue bloqueado") + historial local
#     limitado y rotado. Nada sale del dispositivo.
#   - Migracion versionada v0.1.0 (schema 1) -> v0.2.0 (schema 2).
#
# SEGURIDAD: sin eval, sin pgrep/pkill/killall, sin chmod 777, sin tocar
# cadenas/tablas ajenas, ningun input del usuario se interpola sin validar,
# escrituras atomicas (tmp + mv), archivos 0600.
##############################################################################

# ----------------------------------------------------------------------------
# Rutas (todas descendientes de DATA_DIR: aisladas en modo test)
# ----------------------------------------------------------------------------
SEC_DIR="$DATA_DIR/security"
BL_SRC_DIR="$SEC_DIR/blocklists/sources.d"
BL_CACHE_DIR="$SEC_DIR/blocklists/cache"
BL_BAK_DIR="$SEC_DIR/blocklists/backup"
BL_ACTIVE_DIR="$SEC_DIR/active"
BL_BLOCKED="$BL_ACTIVE_DIR/blocked-names.txt"
BL_ALLOWED="$BL_ACTIVE_DIR/allowed-names.txt"
ALLOWLIST_FILE="$SEC_DIR/allowlist.txt"
EXCEPTIONS_FILE="$SEC_DIR/exceptions.tsv"
EVENTS_DIR="$SEC_DIR/events"
EVENTS_LOG="$EVENTS_DIR/blocked.log"
SEC_EXPORT_DIR="$SEC_DIR/export"
SCHEMA_FILE="$DATA_DIR/schema_version"
MIGRATION_FAILED_FLAG="$DATA_DIR/migration-failed"
FC_ENGAGED_TAG="$RUN_DIR/failclosed.engaged"

# Cadena/tabla PROPIAS del fail-closed. La tabla nft es SEPARADA de la de
# redireccion a proposito: redirect_remove_nft borra su tabla entera, y el
# ciclo de vida del fail-closed no debe morir con la redireccion (ni al reves).
FC_CHAIN="DNSCRYPT_FC"
NFT_FC_TABLE="dnscrypt_manager_fc"

SEC_CATEGORIES="malware phishing scams trackers ads cryptomining"
SEC_MAX_LIST_BYTES=26214400
SEC_MIN_LIST_BYTES=64
SEC_MAX_DOMAINS=500000
SEC_MIN_DOMAINS=10
SEC_MAX_IMPORT_BYTES=1048576
SEC_MAX_IMPORT_LINES=5000

DCM_SELF="${DCM_SELF:-$0}"

sec_lib_loaded() { return 0; }

sec_init_dirs() {
  mkdir -p "$BL_SRC_DIR" "$BL_CACHE_DIR" "$BL_BAK_DIR" "$BL_ACTIVE_DIR" \
           "$EVENTS_DIR" "$SEC_EXPORT_DIR" 2>/dev/null
  chmod 0700 "$SEC_DIR" 2>/dev/null
  return 0
}
sec_init_dirs

# ----------------------------------------------------------------------------
# Helpers basicos
# ----------------------------------------------------------------------------
sec_now() { date +%s; }

sec_bootid() { cat /proc/sys/kernel/random/boot_id 2>/dev/null || echo unknown; }

sec_sha256() {
  if have sha256sum; then sha256sum "$1" 2>/dev/null | awk '{print $1}'
  elif [ -n "$BUSYBOX" ]; then $BUSYBOX sha256sum "$1" 2>/dev/null | awk '{print $1}'
  else echo ""; fi
}

# Byte NUL en los primeros 64K => contenido binario, no una lista de texto.
sec_is_binary() {
  od -An -tx1 -N 65536 "$1" 2>/dev/null | tr ' ' '\n' | grep -qx '00'
}

# Ruta provista por el usuario (import/export): absoluta, sin '..', sin
# saltos de linea. Se usa SIEMPRE citada; esto solo corta lo obviamente roto.
sec_safe_user_path() {
  case "$1" in ''|*..*) return 1 ;; esac
  case "$1" in /*) : ;; *) return 1 ;; esac
  case "$1" in *"
"*) return 1 ;; esac
  return 0
}

# Confirmacion explicita para acciones peligrosas: --confirmed en argumentos,
# o "SI" interactivo si hay TTY. La WebUI siempre manda --confirmed tras su
# propio dialogo de confirmacion.
sec_needs_confirm() {
  for _a in "$@"; do [ "$_a" = "--confirmed" ] && return 0; done
  if [ -t 0 ]; then
    printf 'Escribi SI (mayusculas) para confirmar: ' >&2
    read -r _ans
    [ "$_ans" = "SI" ] && return 0
  fi
  return 1
}

# ----------------------------------------------------------------------------
# Bloques gestionados en un ARCHIVO arbitrario (mismos marcadores que
# set_managed_block de la CLI, para plena compatibilidad).
# ----------------------------------------------------------------------------
sec_block_in_file() {
  _file="$1"; _name="$2"
  _begin="# >>> DCM:$_name BEGIN"
  _end="# <<< DCM:$_name END"
  _content=$(cat)
  _tmp="$_file.tmp.$$"
  if [ -f "$_file" ]; then
    awk -v b="$_begin" -v e="$_end" '
      $0==b {skip=1; next}
      $0==e {skip=0; next}
      skip==0 {print}
    ' "$_file" > "$_tmp"
  else
    : > "$_tmp"
  fi
  {
    echo "$_begin"
    printf '%s\n' "$_content"
    echo "$_end"
  } >> "$_tmp"
  mv -f "$_tmp" "$_file"
  chmod 0600 "$_file" 2>/dev/null
}

sec_unblock_in_file() {
  _file="$1"; _name="$2"
  [ -f "$_file" ] || return 0
  _begin="# >>> DCM:$_name BEGIN"
  _end="# <<< DCM:$_name END"
  grep -qF "$_begin" "$_file" 2>/dev/null || return 0
  _tmp="$_file.tmp.$$"
  awk -v b="$_begin" -v e="$_end" '
    $0==b {skip=1; next}
    $0==e {skip=0; next}
    skip==0 {print}
  ' "$_file" > "$_tmp"
  mv -f "$_tmp" "$_file"
  chmod 0600 "$_file" 2>/dev/null
}

# ----------------------------------------------------------------------------
# Categorias y flags de proteccion
# ----------------------------------------------------------------------------
sec_cat_valid() {
  case "$1" in malware|phishing|scams|trackers|ads|cryptomining) return 0 ;; *) return 1 ;; esac
}
sec_cat_default() {
  case "$1" in malware|phishing|scams) echo 1 ;; *) echo 0 ;; esac
}
sec_cat_enabled() {
  _v=$(get_flag "protection_$1")
  [ -z "$_v" ] && _v=$(sec_cat_default "$1")
  [ "$_v" = "1" ]
}

sec_hist_mode() {
  _v=$(get_flag hist_mode)
  case "$_v" in off|blocked|blocked_errors|diag) echo "$_v" ;; *) echo blocked ;; esac
}
sec_hist_days() {
  _v=$(get_flag hist_days)
  case "$_v" in 1|3|7) echo "$_v" ;; *) echo 3 ;; esac
}
sec_hist_max() {
  _v=$(get_flag hist_max)
  case "$_v" in ''|*[!0-9]*) echo 1000; return ;; esac
  if [ "$_v" -ge 50 ] 2>/dev/null && [ "$_v" -le 10000 ] 2>/dev/null; then echo "$_v"; else echo 1000; fi
}

# ----------------------------------------------------------------------------
# Fuentes de blocklists (metadatos clave=valor en sources.d/<cat>.src)
# ----------------------------------------------------------------------------
sec_ensure_sources() {
  # Copia las fuentes por defecto del modulo SOLO si faltan (no pisa
  # personalizaciones del usuario).
  [ -d "$MODDIR/config/blocklist-sources" ] || return 0
  for _s in "$MODDIR"/config/blocklist-sources/*.src; do
    [ -f "$_s" ] || continue
    _b=$(basename "$_s")
    [ -f "$BL_SRC_DIR/$_b" ] || cp -f "$_s" "$BL_SRC_DIR/$_b" 2>/dev/null
  done
  return 0
}

sec_src_get() {
  grep "^$2=" "$BL_SRC_DIR/$1.src" 2>/dev/null | tail -n1 | cut -d= -f2-
}

sec_meta_get() {
  grep "^$2=" "$BL_CACHE_DIR/$1.meta" 2>/dev/null | tail -n1 | cut -d= -f2-
}

sec_write_meta() {
  # $1 cat $2 sha_raw $3 bytes_raw $4 dominios $5 status $6 sha_lista
  _m="$BL_CACHE_DIR/$1.meta"; _tmpm="$_m.tmp.$$"
  {
    echo "category=$1"
    echo "name=$(sec_src_get "$1" name)"
    echo "url=$(sec_src_get "$1" url)"
    echo "license=$(sec_src_get "$1" license)"
    echo "sha256_raw=$2"
    echo "bytes_raw=$3"
    echo "domains=$4"
    echo "status=$5"
    echo "sha256_list=$6"
    echo "updated_at=$(date '+%Y-%m-%d %H:%M:%S')"
    echo "updated_epoch=$(sec_now)"
  } > "$_tmpm" && mv -f "$_tmpm" "$_m"
  chmod 0600 "$_m" 2>/dev/null
}

# ----------------------------------------------------------------------------
# Descarga (https:// en produccion; file:// SOLO bajo DNSCRYPT_TEST_MODE=1)
# ----------------------------------------------------------------------------
sec_download() {
  _url="$1"; _dst="$2"
  case "$_url" in
    file://*)
      if [ "${DNSCRYPT_TEST_MODE:-0}" != "1" ]; then
        echo "ERROR: esquema file:// solo permitido en modo de pruebas" >&2
        return 1
      fi
      cp -f "${_url#file://}" "$_dst" 2>/dev/null || return 1
      ;;
    https://*)
      if have curl; then
        curl -fsSL --max-time 180 "$_url" -o "$_dst" || return 1
      elif have wget; then
        wget -q -T 180 -O "$_dst" "$_url" || return 1
      else
        echo "ERROR: ni curl ni wget disponibles para descargar" >&2
        return 1
      fi
      ;;
    *)
      echo "ERROR: URL invalida (solo https://)" >&2
      return 1
      ;;
  esac
  [ -s "$_dst" ]
}

# ----------------------------------------------------------------------------
# Parseo y validacion de una lista descargada.
#   $1 crudo  $2 formato (hosts|domains)  $3 salida
# Imprime la cantidad de dominios validos. Reglas:
#   - comentarios (#, !, ;) y lineas vacias fuera
#   - CRLF normalizado, minusculas, sin lineas absurdas (>512)
#   - formato hosts: solo 2do campo cuando el 1ro es 0.0.0.0/127.0.0.1/::/::1
#   - formato domains: exactamente UNA palabra por linea
#   - sintaxis de dominio estricta (misma clase que valid_host, en minusculas)
#   - fuera: IPs puras, URLs (fallan la sintaxis), localhost y ruido de hosts
#   - dedupe + orden estable
# ----------------------------------------------------------------------------
sec_parse_domains() {
  _raw="$1"; _fmt="$2"; _out="$3"
  tr -d '\r' < "$_raw" | awk -v fmt="$_fmt" '
    /^[[:space:]]*[#!;]/ { next }
    {
      line = $0
      sub(/[[:space:]]*#.*$/, "", line)
      sub(/^[[:space:]]+/, "", line)
      sub(/[[:space:]]+$/, "", line)
      if (length(line) == 0) next
      if (length(line) > 512) next
      n = split(line, f, /[[:space:]]+/)
      if (fmt == "hosts") {
        if (n < 2) next
        if (f[1] != "0.0.0.0" && f[1] != "127.0.0.1" && f[1] != "::" && f[1] != "::1") next
        d = f[2]
      } else {
        if (n != 1) next
        d = f[1]
      }
      print tolower(d)
    }' \
  | grep -E '^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)+$' \
  | awk 'length($0) <= 253' \
  | grep -Ev '^([0-9]{1,3}\.){3}[0-9]{1,3}$' \
  | grep -Ev '^(localhost|localhost\.localdomain|broadcasthost|ip6-localhost|ip6-loopback)$' \
  | sort -u > "$_out"
  wc -l < "$_out" | tr -d ' '
}

# ----------------------------------------------------------------------------
# Listas activas: fusion de categorias habilitadas y allowlist+excepciones
# ----------------------------------------------------------------------------
sec_merge_blocked() {
  # $1 salida ; opcional: $2 categoria a sustituir, $3 archivo candidato
  : > "$1"
  for _c in $SEC_CATEGORIES; do
    sec_cat_enabled "$_c" || continue
    if [ -n "${2:-}" ] && [ "$_c" = "$2" ]; then
      _f="$3"
    else
      _f="$BL_CACHE_DIR/$_c.list"
      [ "$(sec_meta_get "$_c" status)" = "ok" ] || continue
    fi
    [ -s "$_f" ] || continue
    cat "$_f" >> "$1"
  done
  # RC2: fusionar tambien las fuentes del catalogo habilitadas + blacklist
  # manual (motor por metadatos, aditivo sobre las categorias legacy).
  command -v cat_append_active >/dev/null 2>&1 && cat_append_active "$1"
  # Fusion a escala: sort -u externo (maneja millones de lineas sin bucles).
  [ -s "$1" ] && sort -u "$1" -o "$1"
  return 0
}

sec_active_exceptions() {
  # Imprime dominios de excepciones VIGENTES (sin reescribir el archivo).
  [ -f "$EXCEPTIONS_FILE" ] || return 0
  _now=$(sec_now); _bid=$(sec_bootid)
  awk -F'\t' -v now="$_now" -v bid="$_bid" '
    NF >= 5 {
      if ($2 == "boot") { if ($5 == bid) print $1; next }
      if ($2 + 0 > now && $3 + 0 <= now + 300) print $1
    }' "$EXCEPTIONS_FILE" 2>/dev/null
}

sec_sweep_exceptions() {
  # Elimina expiradas / de boots anteriores / con reloj inconsistente
  # (creadas "en el futuro": proteccion ante cambios de reloj).
  # rc 0 = sin cambios ; rc 10 = hubo limpieza.
  [ -f "$EXCEPTIONS_FILE" ] || return 0
  _now=$(sec_now); _bid=$(sec_bootid)
  _tmp="$EXCEPTIONS_FILE.tmp.$$"
  awk -F'\t' -v now="$_now" -v bid="$_bid" '
    NF >= 5 {
      if ($2 == "boot") { if ($5 == bid) print; next }
      if ($2 + 0 > now && $3 + 0 <= now + 300) print
    }' "$EXCEPTIONS_FILE" 2>/dev/null > "$_tmp"
  if cmp -s "$_tmp" "$EXCEPTIONS_FILE" 2>/dev/null; then
    rm -f "$_tmp"; return 0
  fi
  mv -f "$_tmp" "$EXCEPTIONS_FILE"
  chmod 0600 "$EXCEPTIONS_FILE" 2>/dev/null
  return 10
}

sec_build_allowed() {
  _out="$1"
  {
    [ -f "$ALLOWLIST_FILE" ] && cat "$ALLOWLIST_FILE"
    sec_active_exceptions
  } 2>/dev/null | grep -E '^[a-z0-9.-]+$' | sort -u > "$_out"
  return 0
}

# ----------------------------------------------------------------------------
# Sincronizacion de bloques [blocked_names]/[allowed_names] en el TOML.
# Setea SEC_TOML_CHANGED=0/1. Nunca deja un bloque apuntando a lista vacia.
# ----------------------------------------------------------------------------
sec_sync_toml_blocks() {
  SEC_TOML_CHANGED=0
  _pre=$(sec_sha256 "$TOML")
  if [ -s "$BL_BLOCKED" ]; then
    {
      echo "[blocked_names]"
      echo "  blocked_names_file = '$BL_BLOCKED'"
      if [ "$(sec_hist_mode)" != "off" ]; then
        echo "  log_file = '$EVENTS_LOG'"
        echo "  log_format = 'tsv'"
      fi
    } | sec_block_in_file "$TOML" security_blocked
  else
    sec_unblock_in_file "$TOML" security_blocked
  fi
  if [ -s "$BL_ALLOWED" ]; then
    {
      echo "[allowed_names]"
      echo "  allowed_names_file = '$BL_ALLOWED'"
    } | sec_block_in_file "$TOML" security_allowed
  else
    sec_unblock_in_file "$TOML" security_allowed
  fi
  _post=$(sec_sha256 "$TOML")
  [ "$_pre" != "$_post" ] && SEC_TOML_CHANGED=1
  return 0
}

# ----------------------------------------------------------------------------
# Regenerar listas activas + TOML; reiniciar el proxy SOLO si algo cambio
# y esta corriendo. Escrituras atomicas. Uso: sec_regen_and_reload [--no-restart]
# ----------------------------------------------------------------------------
sec_regen_and_reload() {
  sec_init_dirs
  sec_sweep_exceptions; _sw=$?
  _tb="$RUN_DIR/sec.blocked.tmp.$$"
  _ta="$RUN_DIR/sec.allowed.tmp.$$"
  sec_merge_blocked "$_tb"
  sec_build_allowed "$_ta"
  _changed=0
  cmp -s "$_tb" "$BL_BLOCKED" 2>/dev/null || _changed=1
  cmp -s "$_ta" "$BL_ALLOWED" 2>/dev/null || _changed=1
  mv -f "$_tb" "$BL_BLOCKED" 2>/dev/null
  mv -f "$_ta" "$BL_ALLOWED" 2>/dev/null
  chmod 0600 "$BL_BLOCKED" "$BL_ALLOWED" 2>/dev/null
  sec_sync_toml_blocks
  [ "$_sw" = "10" ] && _changed=1
  [ "${SEC_TOML_CHANGED:-0}" = "1" ] && _changed=1
  if [ "$_changed" = "1" ] && [ "${1:-}" != "--no-restart" ] && cmd_is_running 2>/dev/null; then
    log_msg "security: listas/config cambiaron; reiniciando dnscrypt-proxy"
    if ! cmd_restart >/dev/null 2>&1; then
      log_msg "security: restart tras regeneracion FALLO"
      sec_on_service_failure "regen-restart"
      return 1
    fi
  fi
  return 0
}

# ----------------------------------------------------------------------------
# FAIL-CLOSED. Opt-in. Cadena DNSCRYPT_FC (tabla filter) / tabla nft propia
# dnscrypt_manager_fc. Nunca bloquea loopback ni 127.0.0.0/8 ni ::1; el
# trafico upstream del proxy es DoH/443 y no se ve afectado. Idempotente.
# ----------------------------------------------------------------------------
sec_fc_flag_on() { [ "$(get_flag failclosed)" = "1" ]; }

fc_is_engaged() {
  if have iptables && iptables -t filter -C OUTPUT -j "$FC_CHAIN" 2>/dev/null; then
    return 0
  fi
  if have nft && nft list table inet "$NFT_FC_TABLE" >/dev/null 2>&1; then
    return 0
  fi
  return 1
}

fc_engage() {
  _fw=$(detect_firewall)
  case "$_fw" in
    iptables)
      for _ipt in iptables ip6tables; do
        have "$_ipt" || continue
        "$_ipt" -t filter -N "$FC_CHAIN" 2>/dev/null
        "$_ipt" -t filter -F "$FC_CHAIN" 2>/dev/null
        "$_ipt" -t filter -A "$FC_CHAIN" -o lo -j RETURN 2>/dev/null
        if [ "$_ipt" = "iptables" ]; then
          "$_ipt" -t filter -A "$FC_CHAIN" -d 127.0.0.0/8 -j RETURN 2>/dev/null
        else
          "$_ipt" -t filter -A "$FC_CHAIN" -d ::1/128 -j RETURN 2>/dev/null
        fi
        "$_ipt" -t filter -A "$FC_CHAIN" -p udp --dport 53 -j REJECT 2>/dev/null
        "$_ipt" -t filter -A "$FC_CHAIN" -p tcp --dport 53 -j REJECT 2>/dev/null
        "$_ipt" -t filter -C OUTPUT -j "$FC_CHAIN" 2>/dev/null || \
          "$_ipt" -t filter -I OUTPUT 1 -j "$FC_CHAIN" 2>/dev/null
      done
      ;;
    nft)
      nft delete table inet "$NFT_FC_TABLE" 2>/dev/null
      nft add table inet "$NFT_FC_TABLE" 2>/dev/null || {
        log_msg "failclosed: nft no pudo crear la tabla"; return 1; }
      nft add chain inet "$NFT_FC_TABLE" fc_out \
        '{ type filter hook output priority 0 ; }' 2>/dev/null
      nft add rule inet "$NFT_FC_TABLE" fc_out oif lo accept 2>/dev/null
      nft add rule inet "$NFT_FC_TABLE" fc_out ip daddr 127.0.0.0/8 accept 2>/dev/null
      nft add rule inet "$NFT_FC_TABLE" fc_out ip6 daddr ::1 accept 2>/dev/null
      nft add rule inet "$NFT_FC_TABLE" fc_out udp dport 53 reject 2>/dev/null
      nft add rule inet "$NFT_FC_TABLE" fc_out tcp dport 53 reject 2>/dev/null
      ;;
    none)
      log_msg "failclosed: SIN backend de firewall; imposible bloquear el puerto 53"
      return 1
      ;;
  esac
  if fc_is_engaged; then
    touch "$FC_ENGAGED_TAG" 2>/dev/null
    log_msg "failclosed: bloqueo de DNS externo ACTIVADO ($_fw)"
    return 0
  fi
  log_msg "failclosed: no se pudieron verificar las reglas ($_fw)"
  return 1
}

fc_release() {
  for _ipt in iptables ip6tables; do
    have "$_ipt" || continue
    while "$_ipt" -t filter -C OUTPUT -j "$FC_CHAIN" 2>/dev/null; do
      "$_ipt" -t filter -D OUTPUT -j "$FC_CHAIN" 2>/dev/null || break
    done
    "$_ipt" -t filter -F "$FC_CHAIN" 2>/dev/null
    "$_ipt" -t filter -X "$FC_CHAIN" 2>/dev/null
  done
  have nft && nft delete table inet "$NFT_FC_TABLE" 2>/dev/null
  rm -f "$FC_ENGAGED_TAG" 2>/dev/null
  return 0
}

# Punto unico de reaccion ante FALLO del servicio. Solo actua si el usuario
# activo fail-closed. Jamas devuelve error (defensivo: no romper el caller).
sec_on_service_failure() {
  sec_fc_flag_on || return 0
  log_msg "failclosed: fallo del servicio ($1); bloqueando consultas DNS externas"
  fc_engage || log_msg "failclosed: CRITICO - no se pudo activar el bloqueo tras el fallo ($1)"
  return 0
}

cmd_failclosed() {
  _sub="$1"; shift 2>/dev/null
  case "$_sub" in
    status)
      _on=inactivo; sec_fc_flag_on && _on=activo
      _eng=no; fc_is_engaged && _eng=si
      if [ "$1" = "--json" ]; then
        _jon=false; sec_fc_flag_on && _jon=true
        _jeng=false; fc_is_engaged && _jeng=true
        printf '{"failclosed":%s,"engaged":%s,%s}\n' "$_jon" "$_jeng" "$(json_kv backend "$(detect_firewall)")"
      else
        echo "fail-closed     : $_on (por defecto viene DESACTIVADO)"
        echo "bloqueo aplicado: $_eng"
        echo "backend         : $(detect_firewall)"
        echo "Desactivar en emergencia (ADB): su -c dnscrypt-manager failclosed disable"
        echo "PANIC siempre restaura la red:  su -c dnscrypt-manager panic"
      fi
      sec_fc_flag_on && return 0 || return 1
      ;;
    enable)
      echo "ADVERTENCIA: Si DNSCrypt deja de funcionar, el telefono puede"
      echo "quedarse sin resolucion DNS hasta restaurar la red manualmente."
      echo "Recuperacion siempre disponible: WebUI, 'failclosed disable' o PANIC."
      if ! sec_needs_confirm "$@"; then
        echo "No se aplico nada. Repeti con: dnscrypt-manager failclosed enable --confirmed" >&2
        return 3
      fi
      set_flag failclosed 1
      log_msg "failclosed: habilitado por el usuario"
      if cmd_is_running 2>/dev/null && cmd_is_listening >/dev/null 2>&1; then
        echo "OK: fail-closed HABILITADO. Se activara solo si el servicio falla."
      else
        echo "OK: fail-closed HABILITADO. El servicio no esta sano: bloqueando DNS externo AHORA."
        fc_engage || echo "AVISO: no se pudieron aplicar las reglas (ver logs)." >&2
      fi
      ;;
    disable)
      set_flag failclosed 0
      fc_release
      log_msg "failclosed: deshabilitado por el usuario"
      echo "OK: fail-closed DESACTIVADO y reglas retiradas. Vuelve el fail-open."
      ;;
    engage-if-set)
      # Interno (boot). Sin confirmacion: el flag YA fue confirmado al setearse.
      sec_fc_flag_on || { echo "failclosed inactivo; nada que hacer"; return 0; }
      fc_engage
      ;;
    *)
      echo "Uso: dnscrypt-manager failclosed {status|enable|disable}" >&2
      return 1
      ;;
  esac
}

# ----------------------------------------------------------------------------
# PROTECCION por categoria
# ----------------------------------------------------------------------------
cmd_protection() {
  _sub="$1"; shift 2>/dev/null
  case "$_sub" in
    status)
      if [ "$1" = "--json" ]; then
        printf '{'
        _first=1
        for _c in $SEC_CATEGORIES; do
          _e=false; sec_cat_enabled "$_c" && _e=true
          _n=$(sec_meta_get "$_c" domains); [ -z "$_n" ] && _n=0
          _st=$(sec_meta_get "$_c" status); [ -z "$_st" ] && _st=sin_lista
          [ "$_first" = 1 ] || printf ','
          _first=0
          printf '"%s":{"enabled":%s,"domains":%s,%s,%s}' \
            "$_c" "$_e" "$_n" "$(json_kv status "$_st")" \
            "$(json_kv updated "$(sec_meta_get "$_c" updated_at)")"
        done
        _tot=0; [ -f "$BL_BLOCKED" ] && _tot=$(wc -l < "$BL_BLOCKED" | tr -d ' ')
        printf ',"active_total":%s}\n' "$_tot"
      else
        echo "Proteccion web - estado por categoria"
        for _c in $SEC_CATEGORIES; do
          _e=OFF; sec_cat_enabled "$_c" && _e=ON
          _n=$(sec_meta_get "$_c" domains); [ -z "$_n" ] && _n=0
          _st=$(sec_meta_get "$_c" status); [ -z "$_st" ] && _st="sin lista descargada"
          printf '  %-12s %-3s  %8s dominios  (%s, %s)\n' "$_c" "$_e" "$_n" "$_st" "$(sec_meta_get "$_c" updated_at)"
        done
        _tot=0; [ -f "$BL_BLOCKED" ] && _tot=$(wc -l < "$BL_BLOCKED" | tr -d ' ')
        echo "  TOTAL activo en blocked-names.txt: $_tot dominios"
      fi
      ;;
    enable|disable)
      _c="$1"
      sec_cat_valid "$_c" || { echo "ERROR: categoria invalida: '$_c' (validas: $SEC_CATEGORIES)" >&2; return 1; }
      if [ "$_sub" = "enable" ]; then set_flag "protection_$_c" 1; else set_flag "protection_$_c" 0; fi
      log_msg "protection: $_c -> $_sub"
      if [ "$_sub" = "enable" ] && [ "$(sec_meta_get "$_c" status)" != "ok" ]; then
        echo "AVISO: '$_c' quedo habilitada pero AUN NO tiene lista validada."
        echo "       Descargala con: dnscrypt-manager blocklists update $_c"
      fi
      sec_regen_and_reload || return 1
      echo "OK: proteccion '$_c' $( [ "$_sub" = enable ] && echo habilitada || echo deshabilitada )."
      ;;
    *)
      echo "Uso: dnscrypt-manager protection {status [--json]|enable <cat>|disable <cat>}" >&2
      echo "Categorias: $SEC_CATEGORIES" >&2
      return 1
      ;;
  esac
}

# ----------------------------------------------------------------------------
# BLOCKLISTS: update / rollback / validate / status / sources
# Pipeline de update (16 pasos del contrato):
#  1 tmp  2 HTTP  3 tamaño  4 SHA-256  5 texto  6 sintaxis  7 rechazo de
#  IP/URL/invalidos  8 dedupe  9 minusculas  10 tmp final  11 -check
#  12 backup  13 reemplazo atomico  14 restart  15 prueba DNS  16 rollback.
# ----------------------------------------------------------------------------
sec__ufail() {
  echo "ERROR ($SEC_UF_CAT): $1" >&2
  log_msg "blocklists update $SEC_UF_CAT: FALLO - $1"
  rm -f "$SEC_UF_T1" "$SEC_UF_T2" 2>/dev/null
  return 1
}

sec_config_check_with() {
  # $1 cat  $2 lista candidata. rc0 ok / rc2 sin binario / rc1 rechazada.
  _bin=$(resolve_bin) || return 2
  _cb="$RUN_DIR/sec.cand.blocked.$$"
  _ca="$RUN_DIR/sec.cand.allowed.$$"
  _ct="$RUN_DIR/sec.cand.toml.$$"
  sec_merge_blocked "$_cb" "$1" "$2"
  sec_build_allowed "$_ca"
  cp -f "$TOML" "$_ct" 2>/dev/null || { rm -f "$_cb" "$_ca"; return 1; }
  if [ -s "$_cb" ]; then
    printf '%s\n' "[blocked_names]" "  blocked_names_file = '$_cb'" | sec_block_in_file "$_ct" security_blocked
  else
    sec_unblock_in_file "$_ct" security_blocked
  fi
  if [ -s "$_ca" ]; then
    printf '%s\n' "[allowed_names]" "  allowed_names_file = '$_ca'" | sec_block_in_file "$_ct" security_allowed
  else
    sec_unblock_in_file "$_ct" security_allowed
  fi
  "$_bin" -config "$_ct" -check >/dev/null 2>&1
  _rc=$?
  rm -f "$_cb" "$_ca" "$_ct" 2>/dev/null
  return "$_rc"
}

sec_update_category() {
  SEC_UF_CAT="$1"; _expsha="${2:-}"
  sec_ensure_sources
  [ -f "$BL_SRC_DIR/$SEC_UF_CAT.src" ] || { sec__ufail "sin archivo de fuente en sources.d"; return 1; }
  _url=$(sec_src_get "$SEC_UF_CAT" url)
  _fmt=$(sec_src_get "$SEC_UF_CAT" format); [ "$_fmt" = "hosts" ] || _fmt=domains
  _min=$(sec_src_get "$SEC_UF_CAT" min_bytes);   case "$_min" in ''|*[!0-9]*) _min=$SEC_MIN_LIST_BYTES ;; esac
  _max=$(sec_src_get "$SEC_UF_CAT" max_bytes);   case "$_max" in ''|*[!0-9]*) _max=$SEC_MAX_LIST_BYTES ;; esac
  _minc=$(sec_src_get "$SEC_UF_CAT" min_domains); case "$_minc" in ''|*[!0-9]*) _minc=$SEC_MIN_DOMAINS ;; esac
  [ -n "$_url" ] || { sec__ufail "la fuente no define url="; return 1; }

  SEC_UF_T1="$RUN_DIR/bl.$SEC_UF_CAT.raw.$$"
  SEC_UF_T2="$RUN_DIR/bl.$SEC_UF_CAT.out.$$"

  # 1-2) descarga a temporal + codigo HTTP (curl -f / wget rc)
  sec_download "$_url" "$SEC_UF_T1" || { sec__ufail "descarga fallida o vacia (paso 1-2)"; return 1; }
  # 3) tamaño minimo y maximo
  _sz=$(wc -c < "$SEC_UF_T1" 2>/dev/null | tr -d ' ')
  [ "$_sz" -ge "$_min" ] 2>/dev/null && [ "$_sz" -le "$_max" ] 2>/dev/null || \
    { sec__ufail "tamaño fuera de rango: $_sz bytes (esperado $_min..$_max) (paso 3)"; return 1; }
  # 4) SHA-256 real (y comparacion si el usuario fijo uno)
  _sha=$(sec_sha256 "$SEC_UF_T1")
  [ -n "$_sha" ] || { sec__ufail "no se pudo calcular SHA-256 (paso 4)"; return 1; }
  if [ -n "$_expsha" ] && [ "$_sha" != "$_expsha" ]; then
    sec__ufail "SHA-256 NO coincide: esperado $_expsha, obtenido $_sha (paso 4)"; return 1
  fi
  # 5) debe ser texto
  sec_is_binary "$SEC_UF_T1" && { sec__ufail "contenido binario (byte NUL) (paso 5)"; return 1; }
  # 6-10) parseo, validacion de dominios, dedupe, minusculas -> tmp final
  _count=$(sec_parse_domains "$SEC_UF_T1" "$_fmt" "$SEC_UF_T2")
  case "$_count" in ''|*[!0-9]*) sec__ufail "parseo fallo (paso 6-9)"; return 1 ;; esac
  [ "$_count" -ge "$_minc" ] || { sec__ufail "solo $_count dominios validos (minimo $_minc): lista vacia o corrupta (paso 6-9)"; return 1; }
  [ "$_count" -le "$SEC_MAX_DOMAINS" ] || { sec__ufail "demasiados dominios: $_count > $SEC_MAX_DOMAINS (paso 6-9)"; return 1; }
  _shalist=$(sec_sha256 "$SEC_UF_T2")
  # 11) probar la configuracion con la lista candidata
  sec_config_check_with "$SEC_UF_CAT" "$SEC_UF_T2"; _rc=$?
  if [ "$_rc" = "2" ]; then
    sec__ufail "sin binario dnscrypt-proxy: no se puede validar la config; la lista NO se activa (paso 11)"; return 1
  elif [ "$_rc" != "0" ]; then
    sec__ufail "dnscrypt-proxy -check rechazo la configuracion candidata (paso 11)"; return 1
  fi
  # 12) backup de la version anterior (si existia)
  _had_prev=0
  if [ -f "$BL_CACHE_DIR/$SEC_UF_CAT.list" ]; then
    cp -f "$BL_CACHE_DIR/$SEC_UF_CAT.list" "$BL_BAK_DIR/$SEC_UF_CAT.list.prev" 2>/dev/null && _had_prev=1
    cp -f "$BL_CACHE_DIR/$SEC_UF_CAT.meta" "$BL_BAK_DIR/$SEC_UF_CAT.meta.prev" 2>/dev/null
  fi
  # 13) reemplazo ATOMICO
  mv -f "$SEC_UF_T2" "$BL_CACHE_DIR/$SEC_UF_CAT.list" || { sec__ufail "mv atomico fallo (paso 13)"; return 1; }
  chmod 0600 "$BL_CACHE_DIR/$SEC_UF_CAT.list" 2>/dev/null
  sec_write_meta "$SEC_UF_CAT" "$_sha" "$_sz" "$_count" ok "$_shalist"
  rm -f "$SEC_UF_T1" 2>/dev/null
  # 14) regenerar lista activa (+restart si corre)
  sec_regen_and_reload
  # 15-16) prueba DNS; si falla, rollback automatico
  if cmd_is_running 2>/dev/null; then
    if ! cmd_test_dns --quiet >/dev/null 2>&1; then
      log_msg "blocklists update $SEC_UF_CAT: prueba DNS fallo; ROLLBACK automatico"
      if [ "$_had_prev" = "1" ]; then
        cp -f "$BL_BAK_DIR/$SEC_UF_CAT.list.prev" "$BL_CACHE_DIR/$SEC_UF_CAT.list" 2>/dev/null
        cp -f "$BL_BAK_DIR/$SEC_UF_CAT.meta.prev" "$BL_CACHE_DIR/$SEC_UF_CAT.meta" 2>/dev/null
      else
        rm -f "$BL_CACHE_DIR/$SEC_UF_CAT.list" "$BL_CACHE_DIR/$SEC_UF_CAT.meta" 2>/dev/null
      fi
      sec_regen_and_reload
      echo "ERROR ($SEC_UF_CAT): la prueba DNS fallo tras aplicar; se restauro la version anterior (paso 15-16)." >&2
      return 1
    fi
  fi
  echo "OK: '$SEC_UF_CAT' actualizada: $_count dominios (sha256 crudo $_sha)."
  log_msg "blocklists update $SEC_UF_CAT: OK ($_count dominios)"
  return 0
}

sec_rollback_category() {
  _c="$1"
  [ -f "$BL_BAK_DIR/$_c.list.prev" ] || { echo "ERROR: no hay version anterior guardada de '$_c'." >&2; return 1; }
  cp -f "$BL_BAK_DIR/$_c.list.prev" "$BL_CACHE_DIR/$_c.list" 2>/dev/null || return 1
  cp -f "$BL_BAK_DIR/$_c.meta.prev" "$BL_CACHE_DIR/$_c.meta" 2>/dev/null
  sec_regen_and_reload || return 1
  echo "OK: '$_c' restaurada a la version anterior."
  log_msg "blocklists rollback $_c: OK"
}

cmd_blocklists() {
  _sub="$1"; shift 2>/dev/null
  case "$_sub" in
    status)
      if [ "$1" = "--json" ]; then
        cmd_protection status --json
      else
        cmd_protection status
        echo "Fuentes definidas en: $BL_SRC_DIR (ver 'blocklists sources')"
      fi
      ;;
    sources)
      sec_ensure_sources
      echo "Fuentes de blocklists (nombre / licencia / url):"
      for _c in $SEC_CATEGORIES; do
        [ -f "$BL_SRC_DIR/$_c.src" ] || { echo "  $_c: (sin fuente)"; continue; }
        echo "  $_c: $(sec_src_get "$_c" name) [$(sec_src_get "$_c" license)]"
        echo "        $(sec_src_get "$_c" url)"
      done
      ;;
    update)
      _target="${1:-all}"
      _expsha=""
      if [ "$2" = "--sha256" ] && [ -n "$3" ]; then _expsha="$3"; fi
      if [ "$_target" = "all" ]; then
        _fails=0
        for _c in $SEC_CATEGORIES; do
          sec_cat_enabled "$_c" || continue
          sec_update_category "$_c" || _fails=$((_fails + 1))
        done
        [ "$_fails" -eq 0 ] && { echo "OK: todas las categorias habilitadas actualizadas."; return 0; }
        echo "ERROR: $_fails categoria(s) fallaron (las demas quedaron aplicadas o intactas)." >&2
        return 1
      fi
      sec_cat_valid "$_target" || { echo "ERROR: categoria invalida: '$_target'" >&2; return 1; }
      sec_update_category "$_target" "$_expsha"
      ;;
    rollback)
      _c="$1"
      sec_cat_valid "$_c" || { echo "Uso: dnscrypt-manager blocklists rollback <categoria>" >&2; return 1; }
      sec_rollback_category "$_c"
      ;;
    validate)
      _tgt="${1:-all}"
      _bad=0
      for _c in $SEC_CATEGORIES; do
        [ "$_tgt" = "all" ] || [ "$_tgt" = "$_c" ] || continue
        _f="$BL_CACHE_DIR/$_c.list"
        [ -f "$_f" ] || { echo "  $_c: sin lista en cache"; continue; }
        _want=$(sec_meta_get "$_c" sha256_list)
        _got=$(sec_sha256 "$_f")
        _badlines=$(grep -cEv '^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)+$' "$_f" 2>/dev/null)
        if [ -n "$_want" ] && [ "$_want" = "$_got" ] && [ "${_badlines:-0}" = "0" ]; then
          echo "  $_c: OK ($(sec_meta_get "$_c" domains) dominios, sha coincide, sintaxis limpia)"
        else
          echo "  $_c: CORRUPTA (sha esperado=$_want obtenido=$_got, lineas invalidas=$_badlines)"
          _bad=$((_bad + 1))
        fi
      done
      [ "$_bad" -eq 0 ]
      ;;
    *)
      echo "Uso: dnscrypt-manager blocklists {status|sources|update [cat|all] [--sha256 H]|rollback <cat>|validate [cat|all]}" >&2
      return 1
      ;;
  esac
}

# ----------------------------------------------------------------------------
# ALLOWLIST
# ----------------------------------------------------------------------------
sec_valid_domain() {
  [ "${#1}" -le 253 ] || return 1
  printf '%s' "$1" | grep -Eq '^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)+$' || return 1
  printf '%s' "$1" | grep -Eq '^([0-9]{1,3}\.){3}[0-9]{1,3}$' && return 1
  return 0
}

sec_allow_contains() {
  [ -f "$ALLOWLIST_FILE" ] && grep -qxF "$1" "$ALLOWLIST_FILE" 2>/dev/null
}

sec_allow_add_core() {
  # $1 dominio ya normalizado y validado. rc0 agregado / rc2 duplicado.
  sec_allow_contains "$1" && return 2
  _tmp="$ALLOWLIST_FILE.tmp.$$"
  { [ -f "$ALLOWLIST_FILE" ] && cat "$ALLOWLIST_FILE"; printf '%s\n' "$1"; } | sort -u > "$_tmp"
  mv -f "$_tmp" "$ALLOWLIST_FILE"
  chmod 0600 "$ALLOWLIST_FILE" 2>/dev/null
  return 0
}

cmd_allowlist() {
  _sub="$1"; shift 2>/dev/null
  sec_init_dirs
  case "$_sub" in
    list)
      if [ "$1" = "--json" ]; then
        printf '{"domains":['
        _first=1
        [ -f "$ALLOWLIST_FILE" ] && while IFS= read -r _d; do
          [ -n "$_d" ] || continue
          [ "$_first" = 1 ] || printf ','
          _first=0
          printf '"%s"' "$_d"
        done < "$ALLOWLIST_FILE"
        _n=0; [ -f "$ALLOWLIST_FILE" ] && _n=$(wc -l < "$ALLOWLIST_FILE" | tr -d ' ')
        printf '],"count":%s}\n' "$_n"
      else
        if [ -s "$ALLOWLIST_FILE" ]; then cat "$ALLOWLIST_FILE"; else echo "(allowlist vacia)"; fi
      fi
      ;;
    add)
      _d=$(printf '%s' "$1" | tr 'A-Z' 'a-z')
      sec_valid_domain "$_d" || { echo "ERROR: dominio invalido: '$1' (formato: example.com / sub.example.com; sin URL, IP, comodines ni rutas)" >&2; return 1; }
      sec_allow_add_core "$_d"; _rc=$?
      if [ "$_rc" = "2" ]; then echo "Ya estaba en la allowlist: $_d"; return 0; fi
      sec_regen_and_reload || return 1
      echo "OK: agregado a la allowlist: $_d"
      log_msg "allowlist add $_d"
      ;;
    remove)
      _d=$(printf '%s' "$1" | tr 'A-Z' 'a-z')
      sec_valid_domain "$_d" || { echo "ERROR: dominio invalido: '$1'" >&2; return 1; }
      sec_allow_contains "$_d" || { echo "ERROR: '$_d' no esta en la allowlist." >&2; return 1; }
      _tmp="$ALLOWLIST_FILE.tmp.$$"
      grep -vxF "$_d" "$ALLOWLIST_FILE" > "$_tmp" 2>/dev/null
      mv -f "$_tmp" "$ALLOWLIST_FILE"
      chmod 0600 "$ALLOWLIST_FILE" 2>/dev/null
      sec_regen_and_reload || return 1
      echo "OK: eliminado de la allowlist: $_d"
      log_msg "allowlist remove $_d"
      ;;
    search)
      _q=$(printf '%s' "$1" | tr 'A-Z' 'a-z' | tr -cd 'a-z0-9.-')
      [ -n "$_q" ] || { echo "ERROR: termino de busqueda vacio o invalido" >&2; return 1; }
      [ -f "$ALLOWLIST_FILE" ] && grep -F -- "$_q" "$ALLOWLIST_FILE" || true
      ;;
    clear)
      if ! sec_needs_confirm "$@"; then
        echo "Accion destructiva. Repeti con: dnscrypt-manager allowlist clear --confirmed" >&2
        return 3
      fi
      : > "$ALLOWLIST_FILE"
      sec_regen_and_reload || return 1
      echo "OK: allowlist vaciada."
      log_msg "allowlist clear"
      ;;
    export)
      _dst="${1:-$SEC_EXPORT_DIR/allowlist-$(date '+%Y%m%d-%H%M%S').txt}"
      sec_safe_user_path "$_dst" || { echo "ERROR: ruta de destino invalida" >&2; return 1; }
      cp -f "$ALLOWLIST_FILE" "$_dst" 2>/dev/null || { echo "ERROR: no se pudo escribir $_dst" >&2; return 1; }
      echo "OK: allowlist exportada a: $_dst"
      ;;
    import)
      _src="$1"
      sec_safe_user_path "$_src" || { echo "ERROR: ruta invalida (absoluta, sin '..')" >&2; return 1; }
      [ -f "$_src" ] || { echo "ERROR: no existe el archivo: $_src" >&2; return 1; }
      _sz=$(wc -c < "$_src" 2>/dev/null | tr -d ' ')
      [ "$_sz" -le "$SEC_MAX_IMPORT_BYTES" ] 2>/dev/null || { echo "ERROR: archivo demasiado grande (max ${SEC_MAX_IMPORT_BYTES} bytes)" >&2; return 1; }
      _nl=$(wc -l < "$_src" 2>/dev/null | tr -d ' ')
      [ "$_nl" -le "$SEC_MAX_IMPORT_LINES" ] 2>/dev/null || { echo "ERROR: demasiadas lineas (max $SEC_MAX_IMPORT_LINES)" >&2; return 1; }
      sec_is_binary "$_src" && { echo "ERROR: el archivo no es texto" >&2; return 1; }
      _added=0; _dup=0; _bad=0
      while IFS= read -r _line; do
        _d=$(printf '%s' "$_line" | tr -d '\r' | tr 'A-Z' 'a-z' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        [ -n "$_d" ] || continue
        case "$_d" in \#*) continue ;; esac
        if sec_valid_domain "$_d"; then
          sec_allow_add_core "$_d"
          if [ $? -eq 2 ]; then _dup=$((_dup + 1)); else _added=$((_added + 1)); fi
        else
          _bad=$((_bad + 1))
        fi
      done < "$_src"
      sec_regen_and_reload || return 1
      echo "OK: importacion terminada. Agregados: $_added, duplicados: $_dup, invalidos rechazados: $_bad."
      log_msg "allowlist import: +$_added dup=$_dup invalidos=$_bad"
      [ "$_added" -gt 0 ] || [ "$_dup" -gt 0 ]
      ;;
    *)
      echo "Uso: dnscrypt-manager allowlist {list [--json]|add <dom>|remove <dom>|search <q>|clear|export [ruta]|import <ruta>}" >&2
      return 1
      ;;
  esac
}

# ----------------------------------------------------------------------------
# EXCEPCIONES TEMPORALES (expiracion sin cron: barrido perezoso en cada
# operacion relevante + barrido en boot + sleeper detacheado en produccion)
# Formato TSV: dominio TAB expira(epoch|boot) TAB creada TAB origen TAB bootid TAB motivo
# ----------------------------------------------------------------------------
cmd_temporary_allow() {
  _sub="$1"; shift 2>/dev/null
  sec_init_dirs
  case "$_sub" in
    add)
      _d=$(printf '%s' "$1" | tr 'A-Z' 'a-z'); _dur="$2"; shift 2 2>/dev/null
      _reason="-"; _origin="cli"
      while [ $# -gt 0 ]; do
        case "$1" in
          --reason) _reason=$(printf '%s' "$2" | tr -cd 'a-zA-Z0-9 ._:-' | cut -c1-80); [ -n "$_reason" ] || _reason="-"; shift 2 ;;
          --origin) case "$2" in webui|cli) _origin="$2" ;; esac; shift 2 ;;
          *) shift ;;
        esac
      done
      sec_valid_domain "$_d" || { echo "ERROR: dominio invalido: '$_d'" >&2; return 1; }
      _secs=""
      case "$_dur" in
        5m) _secs=300 ;;
        15m) _secs=900 ;;
        1h) _secs=3600 ;;
        boot) _secs=boot ;;
        perm)
          cmd_allowlist add "$_d" || return 1
          echo "(permanente = allowlist; quitalo con: dnscrypt-manager allowlist remove $_d)"
          return 0 ;;
        *) echo "ERROR: duracion invalida: '$_dur' (validas: 5m 15m 1h boot perm)" >&2; return 1 ;;
      esac
      sec_sweep_exceptions >/dev/null 2>&1
      _now=$(sec_now); _bid=$(sec_bootid)
      if [ "$_secs" = "boot" ]; then _exp="boot"; else _exp=$((_now + _secs)); fi
      _tmp="$EXCEPTIONS_FILE.tmp.$$"
      { [ -f "$EXCEPTIONS_FILE" ] && awk -F'\t' -v d="$_d" '$1 != d' "$EXCEPTIONS_FILE"
        printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$_d" "$_exp" "$_now" "$_origin" "$_bid" "$_reason"
      } > "$_tmp"
      mv -f "$_tmp" "$EXCEPTIONS_FILE"
      chmod 0600 "$EXCEPTIONS_FILE" 2>/dev/null
      sec_regen_and_reload || return 1
      if [ "$_secs" != "boot" ] && [ "${DNSCRYPT_TEST_MODE:-0}" != "1" ]; then
        # Sleeper detacheado que dispara el barrido al expirar. En modo test
        # NO se lanza (los tests ejercitan 'sweep' de forma deterministica).
        ( sleep $((_secs + 2)); sh "$DCM_SELF" temporary-allow sweep >/dev/null 2>&1 ) >/dev/null 2>&1 &
      fi
      if [ "$_secs" = "boot" ]; then
        echo "OK: '$_d' permitido HASTA REINICIAR (motivo: $_reason)."
      else
        echo "OK: '$_d' permitido por $_dur (expira epoch $_exp; motivo: $_reason)."
      fi
      log_msg "temporary-allow add $_d $_dur ($_origin)"
      ;;
    remove)
      _d=$(printf '%s' "$1" | tr 'A-Z' 'a-z')
      sec_valid_domain "$_d" || { echo "ERROR: dominio invalido: '$_d'" >&2; return 1; }
      [ -f "$EXCEPTIONS_FILE" ] && grep -q "^$_d	" "$EXCEPTIONS_FILE" 2>/dev/null || {
        echo "ERROR: no hay excepcion activa para '$_d'." >&2; return 1; }
      _tmp="$EXCEPTIONS_FILE.tmp.$$"
      awk -F'\t' -v d="$_d" '$1 != d' "$EXCEPTIONS_FILE" > "$_tmp"
      mv -f "$_tmp" "$EXCEPTIONS_FILE"
      chmod 0600 "$EXCEPTIONS_FILE" 2>/dev/null
      sec_regen_and_reload || return 1
      echo "OK: excepcion revocada: $_d"
      log_msg "temporary-allow remove $_d"
      ;;
    list)
      sec_sweep_exceptions >/dev/null 2>&1
      if [ "$1" = "--json" ]; then
        _now=$(sec_now)
        printf '{"exceptions":['
        _first=1
        [ -f "$EXCEPTIONS_FILE" ] && while IFS='	' read -r _d _exp _cr _or _bid _re; do
          [ -n "$_d" ] || continue
          [ "$_first" = 1 ] || printf ','
          _first=0
          if [ "$_exp" = "boot" ]; then _rem="boot"; else _rem=$((_exp - _now)); fi
          printf '{%s,%s,%s,%s}' "$(json_kv domain "$_d")" "$(json_kv remaining "$_rem")" \
            "$(json_kv origin "$_or")" "$(json_kv reason "$_re")"
        done < "$EXCEPTIONS_FILE"
        printf ']}\n'
      else
        if [ -s "$EXCEPTIONS_FILE" ]; then
          _now=$(sec_now)
          echo "Excepciones temporales vigentes:"
          while IFS='	' read -r _d _exp _cr _or _bid _re; do
            [ -n "$_d" ] || continue
            if [ "$_exp" = "boot" ]; then _remtxt="hasta reiniciar"; else _remtxt="quedan $((_exp - _now))s"; fi
            printf '  %-40s %-18s origen=%s motivo=%s\n' "$_d" "$_remtxt" "$_or" "$_re"
          done < "$EXCEPTIONS_FILE"
        else
          echo "(sin excepciones temporales vigentes)"
        fi
      fi
      ;;
    sweep)
      sec_sweep_exceptions; _rc=$?
      if [ "$_rc" = "10" ]; then
        sec_regen_and_reload || return 1
        echo "OK: excepciones expiradas eliminadas; listas regeneradas."
      else
        echo "Sin excepciones expiradas."
      fi
      ;;
    *)
      echo "Uso: dnscrypt-manager temporary-allow {add <dom> <5m|15m|1h|boot|perm> [--reason R]|remove <dom>|list [--json]|sweep}" >&2
      return 1
      ;;
  esac
}

# ----------------------------------------------------------------------------
# PERFILES DE SEGURIDAD (aplicacion atomica con snapshot + rollback)
# ----------------------------------------------------------------------------
sec_profile_target_prot() {
  # $1 perfil $2 categoria -> 1/0/keep
  case "$1:$2" in
    balanced:malware|balanced:phishing|balanced:scams) echo 1 ;;
    balanced:*) echo 0 ;;
    strict:ads) echo keep ;;
    strict:*) echo 1 ;;
    privacy:malware|privacy:phishing|privacy:scams|privacy:trackers) echo 1 ;;
    privacy:ads) echo keep ;;
    privacy:*) echo 0 ;;
  esac
}
sec_profile_target_misc() {
  # $1 perfil $2 clave (failclosed|hist_mode|hist_days|hist_max|require_dnssec|require_nolog)
  case "$1:$2" in
    strict:failclosed) echo 1 ;;
    *:failclosed) echo 0 ;;
    strict:hist_mode) echo blocked_errors ;;
    *:hist_mode) echo blocked ;;
    privacy:hist_days) echo 1 ;;
    *:hist_days) echo 3 ;;
    privacy:hist_max) echo 200 ;;
    *:hist_max) echo 1000 ;;
    *:require_dnssec) echo true ;;
    privacy:require_nolog) echo true ;;
    *:require_nolog) echo false ;;
  esac
}

toml_set_toplevel() {
  _k="$1"; _v="$2"; _tmp="$TOML.tmp.$$"
  if grep -Eq "^[[:space:]]*$_k[[:space:]]*=" "$TOML" 2>/dev/null; then
    sed "s|^[[:space:]]*$_k[[:space:]]*=.*|$_k = $_v|" "$TOML" > "$_tmp" || return 1
  else
    { echo "$_k = $_v"; cat "$TOML"; } > "$_tmp" || return 1
  fi
  mv -f "$_tmp" "$TOML"
  chmod 0600 "$TOML" 2>/dev/null
}

sec_profile_plan() {
  _p="$1"
  echo "Plan del perfil '$_p' (actual -> nuevo):"
  for _c in $SEC_CATEGORIES; do
    _cur=0; sec_cat_enabled "$_c" && _cur=1
    _tgt=$(sec_profile_target_prot "$_p" "$_c")
    [ "$_tgt" = "keep" ] && _tgt="$_cur (se conserva; opcional)"
    echo "  protection_$_c: $_cur -> $_tgt"
  done
  _curfc=$(get_flag failclosed); [ -z "$_curfc" ] && _curfc=0
  echo "  failclosed: $_curfc -> $(sec_profile_target_misc "$_p" failclosed)"
  echo "  hist_mode: $(sec_hist_mode) -> $(sec_profile_target_misc "$_p" hist_mode)"
  echo "  hist_days: $(sec_hist_days) -> $(sec_profile_target_misc "$_p" hist_days)"
  echo "  hist_max: $(sec_hist_max) -> $(sec_profile_target_misc "$_p" hist_max)"
  _curd=$(grep -E '^require_dnssec' "$TOML" 2>/dev/null | head -n1 | awk -F= '{gsub(/ /,"",$2); print $2}')
  _curn=$(grep -E '^require_nolog' "$TOML" 2>/dev/null | head -n1 | awk -F= '{gsub(/ /,"",$2); print $2}')
  echo "  require_dnssec (TOML): ${_curd:-false} -> $(sec_profile_target_misc "$_p" require_dnssec)"
  echo "  require_nolog  (TOML): ${_curn:-false} -> $(sec_profile_target_misc "$_p" require_nolog)"
  echo "  Nota: require_* aplica a servidores de FUENTES; los [static] fijados no cambian."
}

cmd_security_profile() {
  _sub="$1"; shift 2>/dev/null
  case "$_sub" in
    status)
      _p=$(get_flag security_profile); [ -z "$_p" ] && _p=ninguno
      if [ "$1" = "--json" ]; then
        printf '{%s}\n' "$(json_kv profile "$_p")"
      else
        echo "Perfil aplicado: $_p"
        echo "(ver detalle vivo con: dnscrypt-manager protection status ; failclosed status)"
      fi
      ;;
    balanced|strict|privacy)
      _p="$_sub"
      sec_profile_plan "$_p"
      if [ "$_p" = "strict" ] && [ "$(get_flag failclosed)" != "1" ]; then
        echo ""
        echo "ADVERTENCIA (fail-closed): Si DNSCrypt deja de funcionar, el telefono"
        echo "puede quedarse sin resolucion DNS hasta restaurar la red manualmente."
        if ! sec_needs_confirm "$@"; then
          echo "No se aplico NADA. Repeti con: dnscrypt-manager security-profile strict --confirmed" >&2
          return 3
        fi
      fi
      # Snapshot para aplicacion atomica con rollback.
      _bkS="$RUN_DIR/profile.state.bak.$$"; _bkT="$RUN_DIR/profile.toml.bak.$$"
      cp -f "$STATE_FILE" "$_bkS" 2>/dev/null || : > "$_bkS"
      cp -f "$TOML" "$_bkT" 2>/dev/null
      _fail=0
      for _c in $SEC_CATEGORIES; do
        _tgt=$(sec_profile_target_prot "$_p" "$_c")
        [ "$_tgt" = "keep" ] && continue
        set_flag "protection_$_c" "$_tgt" || _fail=1
      done
      set_flag hist_mode "$(sec_profile_target_misc "$_p" hist_mode)" || _fail=1
      set_flag hist_days "$(sec_profile_target_misc "$_p" hist_days)" || _fail=1
      set_flag hist_max  "$(sec_profile_target_misc "$_p" hist_max)"  || _fail=1
      _fct=$(sec_profile_target_misc "$_p" failclosed)
      set_flag failclosed "$_fct" || _fail=1
      toml_set_toplevel require_dnssec "$(sec_profile_target_misc "$_p" require_dnssec)" || _fail=1
      toml_set_toplevel require_nolog  "$(sec_profile_target_misc "$_p" require_nolog)"  || _fail=1
      if [ "$_fail" = "0" ]; then
        sec_regen_and_reload || _fail=1
      fi
      if [ "$_fail" != "0" ]; then
        cp -f "$_bkS" "$STATE_FILE" 2>/dev/null
        [ -f "$_bkT" ] && cp -f "$_bkT" "$TOML" 2>/dev/null
        rm -f "$_bkS" "$_bkT" 2>/dev/null
        sec_regen_and_reload >/dev/null 2>&1
        echo "ERROR: fallo la aplicacion del perfil '$_p'; TODO fue restaurado al estado anterior." >&2
        log_msg "security-profile $_p: FALLO; rollback completo"
        return 1
      fi
      if [ "$_fct" = "0" ]; then
        fc_release
      elif ! { cmd_is_running 2>/dev/null && cmd_is_listening >/dev/null 2>&1; }; then
        fc_engage
      fi
      rm -f "$_bkS" "$_bkT" 2>/dev/null
      set_flag security_profile "$_p"
      echo "OK: perfil '$_p' aplicado."
      log_msg "security-profile $_p: aplicado"
      ;;
    *)
      echo "Uso: dnscrypt-manager security-profile {status [--json]|balanced|strict [--confirmed]|privacy}" >&2
      return 1
      ;;
  esac
}

# ----------------------------------------------------------------------------
# DETECTOR DE FUGAS DNS. Estados: protegido / posible_fuga / no_verificable /
# conflicto / fallo. Jamas afirma lo que no puede comprobar.
# ----------------------------------------------------------------------------
cmd_leak_test() {
  _json=0; [ "$1" = "--json" ] && _json=1
  _rows="$RUN_DIR/leak.rows.$$"; : > "$_rows"
  _lt() { printf '%s|%s|%s\n' "$1" "$2" "$3" >> "$_rows"; }

  if cmd_is_running 2>/dev/null && cmd_is_listening >/dev/null 2>&1; then
    _lt listener_local protegido "dnscrypt-proxy escucha en $(get_listen)"
  else
    _lt listener_local fallo "dnscrypt-proxy no esta corriendo/escuchando"
  fi
  if command -v probe_listener_query >/dev/null 2>&1 && probe_listener_query >/dev/null 2>&1; then
    _lt resolucion_proxy protegido "una consulta directa al listener respondio"
  else
    _lt resolucion_proxy fallo "el listener local no respondio la consulta de prueba"
  fi

  _redir=0; redirect_is_active && _redir=1
  _fc=0; fc_is_engaged && _fc=1
  for _pp in udp tcp; do
    if [ "$_redir" = "1" ]; then
      _lt "${_pp}53_ipv4" protegido "trafico $_pp/53 IPv4 redirigido al proxy"
    elif [ "$_fc" = "1" ]; then
      _lt "${_pp}53_ipv4" protegido "$_pp/53 IPv4 bloqueado por fail-closed"
    else
      _lt "${_pp}53_ipv4" posible_fuga "sin redireccion: el sistema usa su DNS normal por $_pp/53 IPv4"
    fi
  done
  _v6m=$(get_flag ipv6_mode); [ -z "$_v6m" ] && _v6m=redirect
  for _pp in udp tcp; do
    if [ "$_redir" = "1" ]; then
      if [ "$_v6m" = "block" ]; then
        _lt "${_pp}53_ipv6" protegido "$_pp/53 IPv6 cortado (modo block)"
      else
        _lt "${_pp}53_ipv6" protegido "$_pp/53 IPv6 redirigido al proxy"
      fi
    elif [ "$_fc" = "1" ]; then
      _lt "${_pp}53_ipv6" protegido "$_pp/53 IPv6 bloqueado por fail-closed"
    else
      _lt "${_pp}53_ipv6" posible_fuga "sin redireccion IPv6 activa"
    fi
  done

  if have ping; then
    if ping -c 1 -W 2 dns.google >/dev/null 2>&1; then
      if [ "$_redir" = "1" ]; then
        _lt resolucion_sistema protegido "el sistema resuelve, y con redireccion pasa por el proxy"
      else
        _lt resolucion_sistema posible_fuga "el sistema resuelve por su DNS normal (sin proteccion)"
      fi
    else
      _lt resolucion_sistema fallo "el sistema no pudo resolver (sin red o DNS caido)"
    fi
  else
    _lt resolucion_sistema no_verificable "sin 'ping' disponible para probar la resolucion del sistema"
  fi

  if have settings; then
    _pdm=$(settings get global private_dns_mode 2>/dev/null)
    case "$_pdm" in
      off) _lt private_dns protegido "Private DNS desactivado: no interfiere" ;;
      hostname)
        _pdh=$(settings get global private_dns_specifier 2>/dev/null)
        _lt private_dns conflicto "Private DNS con hostname '$_pdh': el DoT del sistema puede eludir la redireccion. Sugerido: Automatico u Off." ;;
      opportunistic) _lt private_dns posible_fuga "Private DNS automatico: DoT oportunista posible segun la red" ;;
      *) _lt private_dns no_verificable "valor no legible de private_dns_mode" ;;
    esac
  else
    _lt private_dns no_verificable "comando 'settings' no disponible en este entorno"
  fi

  if have ip; then
    if ip -o link 2>/dev/null | grep -Eq '(tun|wg|ppp)[0-9]*:'; then
      _lt vpn conflicto "interfaz VPN activa: la VPN puede usar su propio DNS y eludir la redireccion"
    else
      _lt vpn protegido "sin interfaz VPN detectada"
    fi
    if ip -o link 2>/dev/null | grep -Eq '(ap0|wlan1|softap|rndis)[0-9]*:'; then
      _lt hotspot posible_fuga "hotspot/tethering detectado: sus clientes no pasan por OUTPUT (activa PREROUTING: set-flag prerouting 1)"
    else
      _lt hotspot protegido "sin hotspot/tethering detectado"
    fi
  else
    _lt vpn no_verificable "sin 'ip' disponible"
    _lt hotspot no_verificable "sin 'ip' disponible"
  fi

  if have getprop; then
    _dns_props=""
    for _pk in dhcp.wlan0.dns1 dhcp.wlan0.dns2 net.dns1 net.dns2; do
      _pv=$(getprop "$_pk" 2>/dev/null)
      [ -n "$_pv" ] && _dns_props="$_dns_props $_pk=$_pv"
    done
    if [ -n "$_dns_props" ]; then
      if [ "$_redir" = "1" ]; then
        _lt dns_de_red protegido "DNS de la red ($_dns_props ) irrelevante bajo redireccion"
      else
        _lt dns_de_red posible_fuga "DNS de la red en uso directo:$_dns_props"
      fi
    else
      _lt dns_de_red no_verificable "propiedades DNS vacias (normal en Android moderno; netd no las expone)"
    fi
  else
    _lt dns_de_red no_verificable "sin 'getprop' disponible"
  fi

  _lt doh_navegador no_verificable "Esta aplicacion puede evitar la redireccion DNS del sistema usando HTTPS. DNSCrypt Manager puede detectarlo parcialmente, pero no bloquear todos los servicios DoH sin afectar trafico HTTPS legitimo."

  if [ "$_json" = "1" ]; then
    printf '{"checks":['
    _first=1
    while IFS='|' read -r _n _s _dt; do
      [ "$_first" = 1 ] || printf ','
      _first=0
      printf '{%s,%s,%s}' "$(json_kv name "$_n")" "$(json_kv state "$_s")" "$(json_kv detail "$_dt")"
    done < "$_rows"
    printf ']}\n'
  else
    echo "Auditoria de fugas DNS"
    echo "----------------------"
    while IFS='|' read -r _n _s _dt; do
      printf '  %-20s %-14s %s\n' "$_n" "$_s" "$_dt"
    done < "$_rows"
  fi
  rm -f "$_rows" 2>/dev/null
  return 0
}

# ----------------------------------------------------------------------------
# EVENTOS ("por que fue bloqueado") + HISTORIAL local limitado
# El log lo escribe dnscrypt-proxy ([blocked_names] log_file, formato tsv):
#   [fecha hora] TAB cliente TAB dominio TAB regla
# ----------------------------------------------------------------------------
sec_event_category() {
  # $1 dominio $2 regla -> categoria o "desconocida"
  for _c in $SEC_CATEGORIES; do
    _f="$BL_CACHE_DIR/$_c.list"
    [ -s "$_f" ] || continue
    if [ -n "$2" ] && [ "$2" != "-" ] && grep -qxF "$2" "$_f" 2>/dev/null; then
      echo "$_c"; return 0
    fi
  done
  _d="$1"; _i=0
  while [ -n "$_d" ] && [ "$_i" -lt 6 ]; do
    for _c in $SEC_CATEGORIES; do
      _f="$BL_CACHE_DIR/$_c.list"
      [ -s "$_f" ] || continue
      grep -qxF "$_d" "$_f" 2>/dev/null && { echo "$_c"; return 0; }
    done
    case "$_d" in *.*) _d="${_d#*.}" ;; *) _d="" ;; esac
    _i=$((_i + 1))
  done
  echo desconocida
}

sec_events_diag_autorevert() {
  [ "$(sec_hist_mode)" = "diag" ] || return 0
  _until=$(get_flag hist_diag_until)
  case "$_until" in ''|*[!0-9]*) return 0 ;; esac
  if [ "$(sec_now)" -gt "$_until" ] 2>/dev/null; then
    set_flag hist_mode blocked
    set_flag hist_diag_until 0
    log_msg "historial: modo diagnostico expirado; vuelta a 'blocked'"
  fi
  return 0
}

sec_events_prune() {
  sec_events_diag_autorevert
  [ -f "$EVENTS_LOG" ] || return 0
  _max=$(sec_hist_max)
  _cut_epoch=$(( $(sec_now) - $(sec_hist_days) * 86400 ))
  _cut_str=$(date -u -d "@$_cut_epoch" '+%Y-%m-%d %H:%M:%S' 2>/dev/null)
  _tmp="$EVENTS_LOG.tmp.$$"
  if [ -n "$_cut_str" ]; then
    awk -F'\t' -v cut="[$_cut_str" '$1 >= cut' "$EVENTS_LOG" 2>/dev/null | tail -n "$_max" > "$_tmp"
  else
    # date -d @epoch no soportado en este entorno: se conserva solo el tope
    # por cantidad (nunca crecimiento ilimitado); el filtro por dias queda
    # degradado y documentado.
    tail -n "$_max" "$EVENTS_LOG" > "$_tmp"
  fi
  if cmp -s "$_tmp" "$EVENTS_LOG" 2>/dev/null; then
    rm -f "$_tmp"; return 0
  fi
  # Truncado EN EL MISMO inode (cat >) para no romper el fd abierto del
  # daemon; una linea concurrente puede perderse en la ventana: asumido.
  cat "$_tmp" > "$EVENTS_LOG" 2>/dev/null
  rm -f "$_tmp"
  return 0
}

cmd_events() {
  _sub="${1:-list}"
  case "$_sub" in list|clear|export|stats|pause|resume|prune) shift 2>/dev/null ;; esac
  sec_init_dirs
  case "$_sub" in
    list)
      sec_events_prune
      _lim=50; _filter=""; _json=0
      while [ $# -gt 0 ]; do
        case "$1" in
          --limit) case "$2" in *[!0-9]*|'') : ;; *) [ "$2" -le 200 ] 2>/dev/null && _lim="$2" || _lim=200 ;; esac; shift 2 ;;
          --filter) _filter=$(printf '%s' "$2" | tr 'A-Z' 'a-z' | tr -cd 'a-z0-9.-'); shift 2 ;;
          --json) _json=1; shift ;;
          *) shift ;;
        esac
      done
      [ -s "$EVENTS_LOG" ] || { [ "$_json" = 1 ] && echo '{"events":[]}' || echo "(sin eventos de bloqueo registrados)"; return 0; }
      _sel="$RUN_DIR/ev.sel.$$"
      if [ -n "$_filter" ]; then
        grep -F -- "$_filter" "$EVENTS_LOG" | tail -n "$_lim" > "$_sel"
      else
        tail -n "$_lim" "$EVENTS_LOG" > "$_sel"
      fi
      # Mas nuevo primero (invertimos el recorte, acotado por _lim <= 200)
      _rev="$RUN_DIR/ev.rev.$$"
      awk '{a[NR]=$0} END{for(i=NR;i>=1;i--) print a[i]}' "$_sel" > "$_rev"
      if [ "$_json" = "1" ]; then
        printf '{"events":['
        _first=1
        while IFS='	' read -r _t _cl _dom _rule _rest; do
          [ -n "$_dom" ] || continue
          [ -n "$_rule" ] || _rule="-"
          _cat=$(sec_event_category "$_dom" "$_rule")
          _alw=false
          { sec_allow_contains "$_dom" || sec_active_exceptions | grep -qxF "$_dom"; } 2>/dev/null && _alw=true
          [ "$_first" = 1 ] || printf ','
          _first=0
          printf '{%s,%s,%s,%s,%s,"allowed_now":%s}' \
            "$(json_kv time "$_t")" "$(json_kv domain "$_dom")" "$(json_kv category "$_cat")" \
            "$(json_kv rule "$_rule")" "$(json_kv list "$(sec_meta_get "$_cat" name)")" "$_alw"
        done < "$_rev"
        printf ']}\n'
      else
        echo "Eventos de bloqueo (mas recientes primero, max $_lim):"
        while IFS='	' read -r _t _cl _dom _rule _rest; do
          [ -n "$_dom" ] || continue
          [ -n "$_rule" ] || _rule="-"
          _cat=$(sec_event_category "$_dom" "$_rule")
          _alw=no
          { sec_allow_contains "$_dom" || sec_active_exceptions | grep -qxF "$_dom"; } 2>/dev/null && _alw=si
          printf '  %s  %-38s cat=%-12s regla=%s permitido_ahora=%s\n' "$_t" "$_dom" "$_cat" "$_rule" "$_alw"
        done < "$_rev"
      fi
      rm -f "$_sel" "$_rev" 2>/dev/null
      ;;
    clear)
      : > "$EVENTS_LOG" 2>/dev/null
      echo "OK: historial de eventos borrado."
      log_msg "events clear"
      ;;
    export)
      sec_events_prune
      _dst="${1:-$SEC_EXPORT_DIR/eventos-$(date '+%Y%m%d-%H%M%S').tsv}"
      sec_safe_user_path "$_dst" || { echo "ERROR: ruta de destino invalida" >&2; return 1; }
      cp -f "$EVENTS_LOG" "$_dst" 2>/dev/null || { echo "ERROR: no se pudo escribir $_dst" >&2; return 1; }
      echo "OK: eventos exportados a: $_dst"
      ;;
    stats)
      sec_events_prune
      _json=0; [ "$1" = "--json" ] && _json=1
      _tot=0; [ -f "$EVENTS_LOG" ] && _tot=$(wc -l < "$EVENTS_LOG" | tr -d ' ')
      _u="$RUN_DIR/ev.u.$$"
      if [ -s "$EVENTS_LOG" ]; then
        tail -n 1000 "$EVENTS_LOG" | awk -F'\t' 'NF>=3 {print $3}' | sort | uniq -c | sort -rn > "$_u"
      else
        : > "$_u"
      fi
      _top=$(head -n1 "$_u" | awk '{print $2" ("$1")"}')
      [ -n "$_top" ] || _top="-"
      _cm=0; _cp=0; _cs=0; _ct=0; _ca=0; _cc=0; _scan=0
      while read -r _n _dom; do
        [ -n "$_dom" ] || continue
        _scan=$((_scan + 1)); [ "$_scan" -gt 300 ] && break
        case "$(sec_event_category "$_dom" "-")" in
          malware) _cm=$((_cm + _n)) ;;
          phishing) _cp=$((_cp + _n)) ;;
          scams) _cs=$((_cs + _n)) ;;
          trackers) _ct=$((_ct + _n)) ;;
          ads) _ca=$((_ca + _n)) ;;
          cryptomining) _cc=$((_cc + _n)) ;;
        esac
      done < "$_u"
      rm -f "$_u" 2>/dev/null
      _lastup=""
      for _c in $SEC_CATEGORIES; do
        _e=$(sec_meta_get "$_c" updated_at)
        [ -n "$_e" ] && { [ -z "$_lastup" ] || [ "$_e" \> "$_lastup" ]; } && _lastup="$_e"
      done
      [ -n "$_lastup" ] || _lastup="-"
      _errs=0; [ -f "$DAEMON_LOG" ] && _errs=$(grep -c 'ERROR' "$DAEMON_LOG" 2>/dev/null)
      if [ "$_json" = "1" ]; then
        printf '{"total":%s,"malware":%s,"phishing":%s,"scams":%s,"trackers":%s,"ads":%s,"cryptomining":%s,%s,%s,"resolution_errors_approx":%s}\n' \
          "$_tot" "$_cm" "$_cp" "$_cs" "$_ct" "$_ca" "$_cc" \
          "$(json_kv top_domain "$_top")" "$(json_kv lists_last_update "$_lastup")" "${_errs:-0}"
      else
        echo "Estadisticas de bloqueo (historial local, ultimas $_tot entradas)"
        echo "  total registrado : $_tot"
        echo "  malware=$_cm phishing=$_cp estafas=$_cs rastreadores=$_ct publicidad=$_ca criptomineria=$_cc"
        echo "  dominio mas bloqueado: $_top"
        echo "  ultima actualizacion de listas: $_lastup"
        echo "  errores de resolucion (aprox, log del daemon): ${_errs:-0}"
      fi
      ;;
    pause)
      _cur=$(sec_hist_mode)
      [ "$_cur" = "off" ] && { echo "El historial ya esta pausado."; return 0; }
      set_flag hist_mode_prev "$_cur"
      set_flag hist_mode off
      sec_regen_and_reload || return 1
      echo "OK: historial PAUSADO (no se registran nuevos bloqueos)."
      ;;
    resume)
      _prev=$(get_flag hist_mode_prev)
      case "$_prev" in blocked|blocked_errors|diag) : ;; *) _prev=blocked ;; esac
      set_flag hist_mode "$_prev"
      sec_regen_and_reload || return 1
      echo "OK: historial REANUDADO (modo: $_prev)."
      ;;
    prune)
      sec_events_prune
      echo "OK: retencion aplicada ($(sec_hist_days) dias / max $(sec_hist_max))."
      ;;
    *)
      echo "Uso: dnscrypt-manager events [list [--limit N] [--filter S] [--json]|clear|export [ruta]|stats [--json]|pause|resume]" >&2
      return 1
      ;;
  esac
}

# ----------------------------------------------------------------------------
# MIGRACION versionada: schema 1 (v0.1.0, sin archivo) -> schema 2 (v0.2.0)
# ADITIVA: jamas pisa flags/config existentes. Si falla: config previa
# intacta, failclosed=0, y service.sh no aplica redireccion ese boot.
# ----------------------------------------------------------------------------
sec_migrate() {
  _cur=$(cat "$SCHEMA_FILE" 2>/dev/null)
  case "$_cur" in ''|*[!0-9]*) _cur=1 ;; esac
  if [ "$_cur" -ge 2 ] 2>/dev/null; then
    echo "Migracion: schema ya en $_cur; nada que hacer."
    return 0
  fi
  log_msg "migracion v0.1.0 -> v0.2.0: inicio"
  rm -f "$MIGRATION_FAILED_FLAG" 2>/dev/null
  _err=0
  sec_init_dirs || _err=1
  [ -f "$ALLOWLIST_FILE" ]  || : > "$ALLOWLIST_FILE"  || _err=1
  [ -f "$EXCEPTIONS_FILE" ] || : > "$EXCEPTIONS_FILE" || _err=1
  chmod 0600 "$ALLOWLIST_FILE" "$EXCEPTIONS_FILE" 2>/dev/null
  sec_ensure_sources || _err=1
  for _c in $SEC_CATEGORIES; do
    [ -n "$(get_flag "protection_$_c")" ] || set_flag "protection_$_c" "$(sec_cat_default "$_c")" || _err=1
  done
  [ -n "$(get_flag failclosed)" ] || set_flag failclosed 0 || _err=1
  [ -n "$(get_flag hist_mode)" ]  || set_flag hist_mode blocked || _err=1
  [ -n "$(get_flag hist_days)" ]  || set_flag hist_days 3 || _err=1
  [ -n "$(get_flag hist_max)" ]   || set_flag hist_max 1000 || _err=1
  sec_regen_and_reload --no-restart || _err=1
  if [ "$_err" -ne 0 ]; then
    touch "$MIGRATION_FAILED_FLAG" 2>/dev/null
    set_flag failclosed 0
    log_msg "migracion: FALLO parcial; failclosed=0; la redireccion no se aplicara este boot"
    echo "ERROR: migracion incompleta. Config previa intacta; failclosed queda en 0;" >&2
    echo "       la redireccion automatica se omite hasta resolverlo. Ver: dnscrypt-manager logs" >&2
    return 1
  fi
  # RC2 (aditivo): copiar el index del catalogo al dispositivo (sin descargar).
  command -v cat_sync_index >/dev/null 2>&1 && cat_sync_index
  echo 2 > "$SCHEMA_FILE"
  log_msg "migracion v0.1.0 -> v0.2.0: OK (schema 2)"
  echo "OK: migracion a schema 2 completada. Proveedor, NextDNS, IPv6, redireccion,"
  echo "    backups y PANIC: conservados tal como estaban."
  return 0
}

# ----------------------------------------------------------------------------
# Fragmento JSON extra para 'status --json' (lo inserta la CLI)
# ----------------------------------------------------------------------------
sec_status_extra_json() {
  _fcj=false; sec_fc_flag_on && _fcj=true
  _fcej=false; fc_is_engaged 2>/dev/null && _fcej=true
  _prof=$(get_flag security_profile); [ -z "$_prof" ] && _prof=ninguno
  _bd=0; [ -f "$BL_BLOCKED" ] && _bd=$(wc -l < "$BL_BLOCKED" 2>/dev/null | tr -d ' ')
  _ev=0; [ -f "$EVENTS_LOG" ] && _ev=$(wc -l < "$EVENTS_LOG" 2>/dev/null | tr -d ' ')
  printf '"failclosed":%s,"failclosed_engaged":%s,%s,"blocked_domains":%s,"events_count":%s,' \
    "$_fcj" "$_fcej" "$(json_kv security_profile "$_prof")" "${_bd:-0}" "${_ev:-0}"
}
