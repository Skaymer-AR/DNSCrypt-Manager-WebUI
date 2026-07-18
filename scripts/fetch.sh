#!/system/bin/sh
# scripts/fetch.sh  —  DNSCrypt Manager v0.3.0-RC1
#
# Motor comun de descarga seguro (A2.1) + clasificacion de error (A2.2).
# Usado por security.sh, catalog.sh, source doctor y fuentes custom.
#
# Reglas de seguridad (no negociables):
#   - HTTPS obligatorio en la peticion Y en los redirects (--proto/--proto-redir);
#   - TLS verificado (NUNCA curl -k), sin fallback a HTTP;
#   - sin eval, sin sh -c con la URL, sin DNS publico hardcodeado;
#   - la URL se valida y se rechazan metacaracteres de shell;
#   - descarga a temporal, se valida, y solo entonces reemplazo atomico;
#   - ante cualquier fallo NO se escribe el destino (se conserva la ultima copia);
#   - limpieza de temporales con trap; respeta cancelacion (PANIC/lock).
#
# Salida (stdout) machine-readable, una clave por linea:
#   failure_class=<clase>  http_status=<n>  bytes=<n>  content_type=<...>
#   redirect_url=<...>  format_detected=<hosts|domains|abp|unknown>  sha256=<...>
# Codigo de retorno: 0 solo si failure_class=ok.
#
# Clases: ok dns_system_failed dns_proxy_failed self_blocked connection_failed
#         tls_failed http_404 http_error redirect_invalid empty
#         html_instead_of_list validation_failed unsupported_format cancelled timeout

# --- utilidades ---
_fetch_rand() {
  if [ -r /dev/urandom ]; then head -c 6 /dev/urandom 2>/dev/null | od -An -tx1 2>/dev/null | tr -d ' \n'; else echo "$$_$(date +%s 2>/dev/null)"; fi
}

# _fetch_detect_format FILE -> imprime hosts|domains|abp|unknown
_fetch_detect_format() {
  _ff="$1"
  _first=$(grep -avE '^[[:space:]]*(#|!|$)' "$_ff" 2>/dev/null | head -1)
  case "$_first" in
    '0.0.0.0 '*|'127.0.0.1 '*|'::1 '*|':: '*) echo hosts ;;
    '||'*'^'*|'@@'*) echo abp ;;
    '') echo unknown ;;
    *' '*) echo hosts ;;   # dos campos -> hosts
    *.*) echo domains ;;   # contiene un punto -> dominio
    *) echo unknown ;;
  esac
}

# _fetch_is_html FILE -> 0 si parece HTML
_fetch_is_html() {
  _h=$(head -c 512 "$1" 2>/dev/null | tr 'A-Z' 'a-z')
  case "$_h" in
    *'<!doctype html'*|*'<html'*|*'<head'*|*'<body'*) return 0 ;;
  esac
  return 1
}

# dcm_fetch_url URL DEST CONTEXT
# Variables opcionales: DCM_FETCH_CONNECT_TIMEOUT DCM_FETCH_MAX_TIME
#   DCM_FETCH_MAX_REDIRS DCM_FETCH_MIN_BYTES DCM_FETCH_MAX_BYTES
#   DCM_FETCH_RESOLVE ("host:443:IP" para bootstrap con --resolve)
dcm_fetch_url() {
  _url="$1"; _dest="$2"; _ctx="${3:-fetch}"
  _emit_fc() { printf 'failure_class=%s\n' "$1"; }
  [ -n "$_url" ] || { _emit_fc unsupported_format; echo "reason=url vacia"; return 1; }

  # 1) URL: HTTPS obligatorio.
  case "$_url" in
    https://*) : ;;
    http://*)  _emit_fc unsupported_format; echo "reason=http no permitido (solo https)"; return 1 ;;
    file://*|ftp://*|data:*) _emit_fc unsupported_format; echo "reason=esquema no permitido"; return 1 ;;
    *) _emit_fc unsupported_format; echo "reason=esquema desconocido"; return 1 ;;
  esac
  # 2) Rechazar metacaracteres de shell / espacios / comillas en la URL.
  case "$_url" in
    *' '*|*"'"*|*'"'*|*'`'*|*'$'*|*'\'*|*';'*|*'|'*|*'&'*|*'<'*|*'>'*|*'('*|*')'*)
      _emit_fc validation_failed; echo "reason=URL con caracteres no permitidos"; return 1 ;;
  esac

  # Cancelacion (PANIC): si existe la marca, abortar sin escribir.
  if [ -n "${DATA_DIR:-}" ] && [ -f "$DATA_DIR/run/panic.flag" ]; then _emit_fc cancelled; return 1; fi

  _to_conn="${DCM_FETCH_CONNECT_TIMEOUT:-10}"
  _to_total="${DCM_FETCH_MAX_TIME:-60}"
  _max_redir="${DCM_FETCH_MAX_REDIRS:-5}"
  _max_bytes="${DCM_FETCH_MAX_BYTES:-26214400}"
  _min_bytes="${DCM_FETCH_MIN_BYTES:-256}"
  _ua="DNSCryptManager/0.3"
  _run="${DCM_FETCH_RUNDIR:-${DATA_DIR:-/tmp}/run}"
  mkdir -p "$_run" 2>/dev/null
  _tmp="$_run/fetch.$$.$(_fetch_rand)"
  _hdr="$_tmp.hdr"; _err="$_tmp.err"
  trap 'rm -f "$_tmp" "$_hdr" "$_err" 2>/dev/null' RETURN 2>/dev/null || true

  # --- Hook de test: inyecta rc/http/cuerpo sin red (solo TEST_MODE). ---
  if [ "${DNSCRYPT_TEST_MODE:-0}" = 1 ] && [ -n "${DCM_FETCH_TEST_RC:-}" ]; then
    _rc="$DCM_FETCH_TEST_RC"; _http="${DCM_FETCH_TEST_HTTP:-000}"
    if [ -n "${DCM_FETCH_TEST_BODY_FILE:-}" ] && [ -f "$DCM_FETCH_TEST_BODY_FILE" ]; then cp "$DCM_FETCH_TEST_BODY_FILE" "$_tmp" 2>/dev/null; else : > "$_tmp"; fi
    _ctype="${DCM_FETCH_TEST_CTYPE:-text/plain}"
    printf 'content-type: %s\r\n' "$_ctype" > "$_hdr"
  else
    # --- Descarga real ---
    _resolve_opt=""
    if [ -n "${DCM_FETCH_RESOLVE:-}" ]; then _resolve_opt="--resolve ${DCM_FETCH_RESOLVE}"; fi
    # proto '=https' y proto-redir '=https' impiden http/ftp/file en peticion y redirects.
    # shellcheck disable=SC2086
    _http=$(curl -fsS \
      --proto '=https' --proto-redir '=https' \
      --connect-timeout "$_to_conn" --max-time "$_to_total" \
      --max-redirs "$_max_redir" --location \
      --user-agent "$_ua" \
      --dump-header "$_hdr" \
      --max-filesize "$_max_bytes" \
      --write-out '%{http_code}' \
      $_resolve_opt \
      --output "$_tmp" "$_url" 2>"$_err")
    _rc=$?
  fi

  # 3) Clasificar por rc de curl.
  case "$_rc" in
    0) : ;;  # exito de transporte; validar contenido abajo
    6)  _emit_fc dns_system_failed; echo "reason=no se pudo resolver el host"; return 1 ;;
    7)  _emit_fc connection_failed; echo "reason=fallo de conexion"; return 1 ;;
    28) _emit_fc timeout; echo "reason=timeout"; return 1 ;;
    35|51|58|59|60|66|77|80|82|83|91) _emit_fc tls_failed; echo "reason=fallo TLS/certificado"; return 1 ;;
    47) _emit_fc redirect_invalid; echo "reason=demasiados redirects"; return 1 ;;
    63) _emit_fc empty; echo "reason=excede el tamano maximo"; return 1 ;;
    22) # HTTP >=400 (por --fail)
        case "$_http" in
          404) _emit_fc http_404; echo "http_status=404"; return 1 ;;
          *)   _emit_fc http_error; echo "http_status=$_http"; return 1 ;;
        esac ;;
    *)  # Otros: si el protocolo fue rechazado en un redirect, curl da 1/3.
        _emit_fc connection_failed; echo "reason=curl rc=$_rc"; return 1 ;;
  esac

  # 4) Validaciones de contenido.
  _bytes=$(wc -c < "$_tmp" 2>/dev/null | tr -d ' '); _bytes="${_bytes:-0}"
  _ctype=$(grep -ai '^content-type:' "$_hdr" 2>/dev/null | tail -1 | cut -d: -f2- | tr -d '\r' | sed 's/^ *//')
  echo "http_status=${_http:-200}"
  echo "content_type=${_ctype:-unknown}"
  echo "bytes=$_bytes"
  if [ "$_bytes" -lt "$_min_bytes" ]; then _emit_fc empty; echo "reason=archivo demasiado pequeno ($_bytes < $_min_bytes)"; return 1; fi
  if _fetch_is_html "$_tmp"; then _emit_fc html_instead_of_list; echo "reason=el servidor devolvio HTML, no una lista"; return 1; fi
  _fmt=$(_fetch_detect_format "$_tmp"); echo "format_detected=$_fmt"
  if [ "$_fmt" = "unknown" ]; then _emit_fc validation_failed; echo "reason=formato no reconocido"; return 1; fi

  _sha=$(sha256sum "$_tmp" 2>/dev/null | cut -d' ' -f1); echo "sha256=${_sha:-}"

  # 5) Reemplazo atomico SOLO si hay destino y todo valido.
  if [ -n "$_dest" ]; then
    mkdir -p "$(dirname "$_dest")" 2>/dev/null
    if cp "$_tmp" "$_dest.new" 2>/dev/null && mv -f "$_dest.new" "$_dest" 2>/dev/null; then
      :
    else
      rm -f "$_dest.new" 2>/dev/null
      _emit_fc validation_failed; echo "reason=no se pudo escribir el destino"; return 1
    fi
  fi
  _emit_fc ok
  return 0
}

# ---------------------------------------------------------------------------
# source doctor (A2.2). Diagnostico estructurado por fuente. Reutiliza
# dcm_fetch_url para la clasificacion de red y agrega senales de resolucion y
# de auto-bloqueo. No presenta todo como "descarga fallida".
# ---------------------------------------------------------------------------

# dcm_host_of URL -> hostname
dcm_host_of() {
  printf '%s' "$1" | sed -e 's#^[a-zA-Z]*://##' -e 's#/.*$##' -e 's#:.*$##' -e 's#@.*##' 2>/dev/null
}

# dcm_resolve_check HOST -> ok | failed | not_verifiable
# El shell root puede no compartir el contexto DNS de Android netd: si no hay
# herramienta utilizable, es not_verifiable, NO failed.
dcm_resolve_check() {
  _h="$1"; [ -n "$_h" ] || { echo not_verifiable; return; }
  if [ "${DNSCRYPT_TEST_MODE:-0}" = 1 ] && [ -n "${DCM_TEST_SYSRES:-}" ]; then echo "$DCM_TEST_SYSRES"; return; fi
  if command -v getent >/dev/null 2>&1; then
    if getent hosts "$_h" >/dev/null 2>&1; then echo ok; else echo failed; fi; return
  fi
  if command -v nslookup >/dev/null 2>&1; then
    if nslookup "$_h" >/dev/null 2>&1; then echo ok; else echo failed; fi; return
  fi
  echo not_verifiable
}

# dcm_host_in_active HOST -> yes | no | unknown
# ¿El hostname de la fuente esta bloqueado por la lista compilada activa?
dcm_host_in_active() {
  _h="$1"; [ -n "$_h" ] || { echo unknown; return; }
  if [ "${DNSCRYPT_TEST_MODE:-0}" = 1 ] && [ -n "${DCM_TEST_SELFBLOCK:-}" ]; then echo "$DCM_TEST_SELFBLOCK"; return; fi
  _active="${DATA_DIR:-}/security/active/blocked-names.txt"
  [ -f "$_active" ] || { echo unknown; return; }
  if grep -qxF "$_h" "$_active" 2>/dev/null; then echo yes; else echo no; fi
}

# dcm_source_doctor SOURCE_ID
# Resuelve url/tipo desde el catalogo o desde las .src antiguas, emite campos.
dcm_source_doctor() {
  _sid="$1"
  _url=""; _stype="unknown"
  # 1) catalogo (si cat_field esta disponible)
  if command -v cat_exists >/dev/null 2>&1 && cat_exists "$_sid" 2>/dev/null; then
    _url=$(cat_field "$_sid" 8 2>/dev/null); _stype="catalog"
  elif [ -n "${BL_SRC_DIR:-}" ] && [ -f "$BL_SRC_DIR/$_sid.src" ]; then
    _url=$(sec_src_get "$_sid" url 2>/dev/null); _stype="legacy_src"
  elif [ -n "${DATA_DIR:-}" ] && [ -f "$DATA_DIR/catalog/custom/$_sid.src" ]; then
    _url=$(grep '^url=' "$DATA_DIR/catalog/custom/$_sid.src" 2>/dev/null | tail -1 | cut -d= -f2-); _stype="custom"
  fi
  echo "source_id=$_sid"
  echo "source_type=$_stype"
  if [ -z "$_url" ]; then echo "failure_class=unsupported_format"; echo "recommendation=id desconocido o sin URL"; return 1; fi
  echo "url=$_url"
  _host=$(dcm_host_of "$_url"); echo "hostname=$_host"

  _sysres=$(dcm_resolve_check "$_host"); echo "system_resolution=$_sysres"
  # proxy_resolution: consulta directa al listener local (best-effort).
  _proxyres=not_verifiable
  if [ "${DNSCRYPT_TEST_MODE:-0}" = 1 ] && [ -n "${DCM_TEST_PROXYRES:-}" ]; then _proxyres="$DCM_TEST_PROXYRES"; fi
  echo "proxy_resolution=$_proxyres"
  _blocked=$(dcm_host_in_active "$_host"); echo "source_hostname_blocked=$_blocked"

  # 2) fetch de diagnostico (sin escribir destino).
  _out=$(dcm_fetch_url "$_url" "" doctor 2>/dev/null)
  _fc=$(printf '%s\n' "$_out" | grep '^failure_class=' | tail -1 | cut -d= -f2)
  _http=$(printf '%s\n' "$_out" | grep '^http_status=' | tail -1 | cut -d= -f2)
  _ctype=$(printf '%s\n' "$_out" | grep '^content_type=' | tail -1 | cut -d= -f2-)
  _bytes=$(printf '%s\n' "$_out" | grep '^bytes=' | tail -1 | cut -d= -f2)
  _fmt=$(printf '%s\n' "$_out" | grep '^format_detected=' | tail -1 | cut -d= -f2)
  # Refinar: si la descarga fallo por DNS pero el host esta auto-bloqueado -> self_blocked.
  if [ "$_fc" = dns_system_failed ] && [ "$_blocked" = yes ]; then _fc=self_blocked; fi
  echo "http_status=${_http:-}"
  echo "redirect_url="
  echo "content_type=${_ctype:-}"
  echo "bytes=${_bytes:-0}"
  echo "format_detected=${_fmt:-}"

  # 3) ultima copia valida (desde source-status runtime, si existe).
  _lva=no; _lvd=0; _lvt=""
  _sst="${DATA_DIR:-}/catalog/source-status.tsv"
  if [ -f "$_sst" ]; then
    _row=$(awk -F'\t' -v id="$_sid" '$1==id{print; exit}' "$_sst" 2>/dev/null)
    if [ -n "$_row" ]; then
      _lvd=$(printf '%s' "$_row" | cut -f5); _lvt=$(printf '%s' "$_row" | cut -f6)
      [ -n "$_lvd" ] && [ "$_lvd" != "0" ] && _lva=yes
    fi
  fi
  echo "last_valid_available=$_lva"
  echo "last_valid_domains=${_lvd:-0}"
  echo "last_valid_timestamp=${_lvt:-}"

  # runtime_status declarado por el catalogo (broken/legacy/etc) si aplica.
  _rst="unknown"
  if [ "$_stype" = catalog ]; then _rst=$(cat_field "$_sid" 10 2>/dev/null); fi
  echo "runtime_status=${_rst:-unknown}"
  echo "failure_class=${_fc:-ok}"

  # 4) recomendacion segun clase.
  case "${_fc:-ok}" in
    ok)                 echo "recommendation=fuente OK; se puede actualizar" ;;
    self_blocked)       echo "recommendation=el host de la fuente esta en la lista activa; usar resolucion bootstrap o excluirlo" ;;
    dns_system_failed)  echo "recommendation=fallo de resolucion DNS (posible contexto netd/shell); reintentar o usar bootstrap; conservar ultima copia valida" ;;
    http_404)           echo "recommendation=URL caida (404); marcar broken/legacy y usar reemplazo; no reintentar" ;;
    tls_failed)         echo "recommendation=fallo TLS; verificar certificado/host; NO usar -k" ;;
    html_instead_of_list) echo "recommendation=el servidor devolvio HTML; revisar la URL de descarga directa" ;;
    empty|validation_failed) echo "recommendation=contenido invalido; conservar ultima copia valida" ;;
    *)                  echo "recommendation=revisar detalle de failure_class=$_fc" ;;
  esac
  [ "${_fc:-ok}" = ok ] && return 0 || return 1
}

# ===========================================================================
# A2.3 — BOOTSTRAP DNS AISLADO
# Evita que una blocklist activa bloquee el hostname necesario para actualizar
# esa misma lista. NO desactiva nada global: levanta una instancia temporal de
# dnscrypt-proxy con la blocklist desactivada SOLO ahi, resuelve el hostname y
# descarga con --resolve conservando TLS/SNI. Limpieza con trap. Ante cualquier
# fallo, preserva la ultima copia valida.
# ===========================================================================

# _boot_free_port -> imprime un puerto TCP/UDP libre (best-effort).
_boot_free_port() {
  if [ "${DNSCRYPT_TEST_MODE:-0}" = 1 ] && [ -n "${DCM_BOOT_TEST_PORT:-}" ]; then printf '%s' "$DCM_BOOT_TEST_PORT"; return; fi
  _p=$(( (RANDOM % 20000) + 20000 ))
  # intento acotado de encontrar uno no escuchado
  _i=0
  while [ $_i -lt 10 ]; do
    if ! (netstat -ltnu 2>/dev/null | grep -q ":$_p "); then printf '%s' "$_p"; return; fi
    _p=$(( (RANDOM % 20000) + 20000 )); _i=$((_i+1))
  done
  printf '%s' "$_p"
}

# dcm_bootstrap_resolve HOST -> imprime una IP (o vacio). Levanta instancia temp.
# Devuelve 0 si obtuvo IP. TEST: DCM_BOOT_TEST_IP inyecta IP; DCM_BOOT_TEST_INSTANCE=fail
# simula que la instancia no arranca.
dcm_bootstrap_resolve() {
  _bh="$1"; [ -n "$_bh" ] || return 1
  if [ "${DNSCRYPT_TEST_MODE:-0}" = 1 ]; then
    [ "${DCM_BOOT_TEST_INSTANCE:-ok}" = fail ] && return 1
    if [ -n "${DCM_BOOT_TEST_IP:-}" ]; then printf '%s' "$DCM_BOOT_TEST_IP"; return 0; fi
    return 1
  fi
  # --- Real ---
  _bin=$(command -v resolve_bin >/dev/null 2>&1 && resolve_bin 2>/dev/null || true)
  [ -n "$_bin" ] && [ -x "$_bin" ] || return 1
  _brun="${DATA_DIR:-/tmp}/run/bootstrap.$$.$(_fetch_rand)"
  mkdir -p "$_brun" 2>/dev/null
  _bport=$(_boot_free_port)
  _bcfg="$_brun/bootstrap.toml"
  # Config temporal: mismo transporte/resolver validos, blocklist DESACTIVADA aqui,
  # listener SOLO en localhost. Derivamos del TOML principal sin modificarlo.
  {
    echo "listen_addresses = ['127.0.0.1:$_bport']"
    echo "max_clients = 25"
    echo "ipv4_servers = true"
    echo "ipv6_servers = false"
    echo "require_dnssec = false"
    echo "cache = false"
    # blocked_names_file NO se define aqui -> sin blocklist en esta instancia.
    # Reusar las mismas fuentes de resolvers del TOML principal si existen.
    if [ -f "${TOML:-}" ]; then
      awk '/^\[sources/{p=1} p{print} ' "$TOML" 2>/dev/null
      awk '/^server_names/{print}' "$TOML" 2>/dev/null
    fi
  } > "$_bcfg" 2>/dev/null
  # Lanzar instancia temporal con el patron de kill seguro (sin pkill/killall).
  "$_bin" -config "$_bcfg" >/dev/null 2>&1 &
  _bpid=$!
  # trap de limpieza: matar el arbol de la instancia temporal y borrar temporales.
  trap '_dcm_boot_cleanup "$_bpid" "$_brun"' RETURN 2>/dev/null || true
  # esperar breve a que escuche
  _w=0; while [ $_w -lt 20 ]; do
    if netstat -ltnu 2>/dev/null | grep -q "127.0.0.1:$_bport "; then break; fi
    sleep 0.1; _w=$((_w+1))
  done
  # resolver SOLO el hostname necesario contra la instancia temporal
  _ip=""
  if [ -n "${BUSYBOX:-}" ]; then
    _ip=$($BUSYBOX nslookup "$_bh" "127.0.0.1:$_bport" 2>/dev/null | awk '/^Address[: ]/{ip=$NF} END{print ip}')
  fi
  [ -n "$_ip" ] || _ip=$("$_bin" -config "$_bcfg" -resolve "$_bh" 2>/dev/null | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -1)
  _dcm_boot_cleanup "$_bpid" "$_brun"
  trap - RETURN 2>/dev/null || true
  [ -n "$_ip" ] || return 1
  printf '%s' "$_ip"
}

# _dcm_boot_cleanup PID RUNDIR — mata el arbol temporal (reusa el patron seguro).
_dcm_boot_cleanup() {
  _cp="$1"; _cr="$2"
  if [ -n "$_cp" ]; then
    if command -v _cat_kill_tree >/dev/null 2>&1; then _cat_kill_tree "$_cp" TERM 2>/dev/null; sleep 0.2; _cat_kill_tree "$_cp" KILL 2>/dev/null
    else kill -TERM "$_cp" 2>/dev/null; sleep 0.2; kill -KILL "$_cp" 2>/dev/null; fi
  fi
  [ -n "$_cr" ] && rm -rf "$_cr" 2>/dev/null
}

# dcm_bootstrap_fetch URL DEST CONTEXT
# 1) intenta descarga normal; 2) si falla por DNS o autobloqueo, hace bootstrap.
dcm_bootstrap_fetch() {
  _url="$1"; _dest="$2"; _ctx="${3:-bootstrap}"
  _r1=$(dcm_fetch_url "$_url" "$_dest" "$_ctx")
  _fc1=$(printf '%s\n' "$_r1" | grep '^failure_class=' | tail -1 | cut -d= -f2)
  echo "$_r1"
  case "$_fc1" in
    ok) return 0 ;;
    dns_system_failed|self_blocked) : ;;  # candidatos a bootstrap
    *) return 1 ;;                          # otros fallos no se arreglan con bootstrap
  esac
  _bh=$(dcm_host_of "$_url")
  echo "bootstrap=attempt hostname=$_bh"
  _ip=$(dcm_bootstrap_resolve "$_bh")
  if [ -z "$_ip" ]; then
    echo "bootstrap=failed_no_ip"
    echo "failure_class=${_fc1}"   # se mantiene la clase original; se preservo la copia
    return 1
  fi
  # validar forma de IP
  case "$_ip" in
    *[!0-9.]*) echo "bootstrap=failed_bad_ip"; echo "failure_class=${_fc1}"; return 1 ;;
  esac
  echo "bootstrap=resolved ip=$_ip"
  # reintento con --resolve (TLS/SNI del hostname original)
  _r2=$(DCM_FETCH_RESOLVE="$_bh:443:$_ip" dcm_fetch_url "$_url" "$_dest" "$_ctx")
  _fc2=$(printf '%s\n' "$_r2" | grep '^failure_class=' | tail -1 | cut -d= -f2)
  echo "$_r2"
  echo "bootstrap=used"
  [ "$_fc2" = ok ] && return 0 || return 1
}
