#!/system/bin/sh
##############################################################################
# DNSCrypt Manager - scripts/catalog.sh
# Creado por Skaymer AR
#
# Motor GENERICO del catalogo de listas (v0.2.0-RC2). Un unico motor por
# metadatos: no hay componentes por-fuente. La CLI lo sourcea despues de
# common.sh y security.sh. NO ejecutable solo. POSIX puro.
#
# Fuente canonica del catalogo: config/catalog/blocklists.json (para la WebUI y
# los mantenedores). En el dispositivo se consume la version PLANA generada
# config/catalog/blocklists.index.tsv (awk-friendly, sin dependencia de Python).
# Ambos artefactos los produce tools/build-catalog.py en dev/CI.
#
# El catalogo es ADITIVO sobre RC1: sus fuentes habilitadas se fusionan junto a
# las 6 categorias legacy en el mismo pipeline atomico de security.sh
# (sec_regen_and_reload -> sec_merge_blocked -> -check -> mv -> restart ->
# prueba DNS -> rollback). NUNCA descarga ni recompila en el boot.
#
# Columnas del TSV (mismas para custom.tsv), 1-indexadas:
#  1 id 2 family_id 3 name 4 maintainer 5 categories 6 aggressiveness 7 format
#  8 primary_url 9 license 10 upstream_status 11 recommended 12 mobile_suitability
#  13 archived 14 supersedes 15 contained_by 16 overlaps_with 17 conflicts_with
#  18 last_verified 19 description_es
##############################################################################

CAT_DIR="$DATA_DIR/catalog"
CAT_INDEX="$CAT_DIR/blocklists.index.tsv"
CAT_ENABLED="$CAT_DIR/enabled.txt"
CAT_CUSTOM="$CAT_DIR/custom.tsv"
CAT_CACHE_DIR="$CAT_DIR/cache"
CAT_BLACKLIST="$CAT_DIR/blacklist.txt"
CAT_COMPILE_LOCK="$RUN_DIR/catalog.compile.lock"
CAT_MIN_FREE_KB=51200          # ~50 MB libres minimos para compilar
CAT_MAX_SOURCE_BYTES=104857600 # 100 MB por fuente descargada
CAT_MIN_SOURCE_BYTES=32

cat_lib_loaded() { return 0; }

cat_init_dirs() {
  mkdir -p "$CAT_CACHE_DIR" 2>/dev/null
  chmod 0700 "$CAT_DIR" 2>/dev/null
  [ -f "$CAT_ENABLED" ] || : > "$CAT_ENABLED"
  [ -f "$CAT_CUSTOM" ] || : > "$CAT_CUSTOM"
  [ -f "$CAT_BLACKLIST" ] || : > "$CAT_BLACKLIST"
  chmod 0600 "$CAT_ENABLED" "$CAT_CUSTOM" "$CAT_BLACKLIST" 2>/dev/null
  return 0
}
cat_init_dirs

# Copia el index del modulo al dispositivo (solo si falta o cambio). Se llama
# desde la migracion. NUNCA descarga nada.
cat_sync_index() {
  _src="$MODDIR/config/catalog/blocklists.index.tsv"
  [ -f "$_src" ] || return 0
  if [ ! -f "$CAT_INDEX" ] || ! cmp -s "$_src" "$CAT_INDEX" 2>/dev/null; then
    cp -f "$_src" "$CAT_INDEX" 2>/dev/null
    chmod 0600 "$CAT_INDEX" 2>/dev/null
  fi
  return 0
}

# ---------------------------------------------------------------------------
# Lectura del index (index del modulo + custom del usuario)
# ---------------------------------------------------------------------------
# Imprime la fila completa (TSV) de un id, buscando primero en custom.
cat_row() {
  _id="$1"
  awk -F'\t' -v id="$_id" '$1==id {print; exit}' "$CAT_CUSTOM" 2>/dev/null | grep -q . && {
    awk -F'\t' -v id="$_id" '$1==id {print; exit}' "$CAT_CUSTOM" 2>/dev/null
    return 0
  }
  awk -F'\t' -v id="$_id" '!/^#/ && $1==id {print; exit}' "$CAT_INDEX" 2>/dev/null
}

# Campo N (1-indexado) de un id.
cat_field() {
  cat_row "$1" | awk -F'\t' -v n="$2" '{print $n}'
}

cat_exists() { [ -n "$(cat_row "$1")" ]; }

# Estado efectivo: si el dispositivo ya descargo+valido la fuente, "verified";
# si no, el estado declarado en el catalogo (unverified/legacy/archived/broken).
cat_effective_status() {
  _st=$(cat_meta_get "$1" status)
  if [ "$_st" = "verified" ]; then echo verified; else cat_field "$1" 10; fi
}

# Lista todos los ids (custom primero, luego catalogo), sin duplicar.
cat_all_ids() {
  {
    awk -F'\t' 'NF>=1 && $1!="" {print $1}' "$CAT_CUSTOM" 2>/dev/null
    awk -F'\t' '!/^#/ && NF>=1 && $1!="" {print $1}' "$CAT_INDEX" 2>/dev/null
  } | awk '!seen[$0]++'
}

# ---------------------------------------------------------------------------
# Estado habilitado
# ---------------------------------------------------------------------------
cat_is_enabled() { grep -qxF "$1" "$CAT_ENABLED" 2>/dev/null; }

cat_enable() {
  cat_is_enabled "$1" && return 0
  _t="$CAT_ENABLED.tmp.$$"
  { cat "$CAT_ENABLED" 2>/dev/null; echo "$1"; } | awk '!seen[$0]++' > "$_t"
  mv -f "$_t" "$CAT_ENABLED"; chmod 0600 "$CAT_ENABLED" 2>/dev/null
}

cat_disable() {
  _t="$CAT_ENABLED.tmp.$$"
  grep -vxF "$1" "$CAT_ENABLED" 2>/dev/null > "$_t"
  mv -f "$_t" "$CAT_ENABLED"; chmod 0600 "$CAT_ENABLED" 2>/dev/null
}

# Rutas de listas cacheadas de las fuentes habilitadas (para la compilacion).
cat_enabled_lists() {
  [ -f "$CAT_ENABLED" ] || return 0
  while IFS= read -r _id; do
    [ -n "$_id" ] || continue
    _f="$CAT_CACHE_DIR/$_id.list"
    [ -s "$_f" ] && printf '%s\n' "$_f"
  done < "$CAT_ENABLED"
}

# HOOK invocado por sec_merge_blocked: agrega al archivo de salida las fuentes
# del catalogo habilitadas + la blacklist manual. El sort -u final lo hace el
# llamador. Usa cat en lote (nunca bucle por dominio).
cat_append_active() {
  _out="$1"
  cat_enabled_lists | while IFS= read -r _f; do
    [ -s "$_f" ] && cat "$_f" >> "$_out"
  done
  # Blacklist manual del usuario (dominios ya validados al agregarse).
  [ -s "$CAT_BLACKLIST" ] && grep -E '^[a-z0-9.-]+$' "$CAT_BLACKLIST" >> "$_out" 2>/dev/null
  # Dominios bloqueados por controles de servicio ACTIVOS (p.ej. YouTube).
  command -v cat_svc_active_blocked >/dev/null 2>&1 && cat_svc_active_blocked >> "$_out" 2>/dev/null
  return 0
}

# ---------------------------------------------------------------------------
# Deteccion de formato (auto) y extraccion de dominios
# ---------------------------------------------------------------------------
# Detecta hosts|domains|abp mirando las primeras lineas utiles.
cat_detect_format() {
  _f="$1"
  awk '
    /^[[:space:]]*[#!]/ { next }
    /^[[:space:]]*$/ { next }
    {
      if ($0 ~ /^(\|\||@@\|\|)/ || $0 ~ /##/ || $0 ~ /\$[a-z]/) { print "abp"; exit }
      if ($0 ~ /^(0\.0\.0\.0|127\.0\.0\.1|::|::1)[[:space:]]+[A-Za-z0-9]/) { print "hosts"; exit }
      print "domains"; exit
    }
    END { }
  ' "$_f" 2>/dev/null
}

# Extrae dominios de reglas ABP claramente convertibles a DNS. Ignora reglas
# cosmeticas (##, #@#), reglas por ruta (con '/'), y reglas con opciones que
# cambian el significado ($...). Respeta excepciones simples (@@||dominio^) que
# se emiten a un archivo aparte para informar (no se aplican aca como allow;
# la allowlist del usuario es la autoridad). Informa "cobertura DNS parcial".
cat_abp_extract() {
  _in="$1"; _out="$2"
  tr -d '\r' < "$_in" | awk '
    /^[[:space:]]*[#!]/ { next }
    /##/ { next }
    /#@#/ { next }
    /^@@/ { next }               # excepciones: no son bloqueos
    /\// { next }                # reglas por ruta URL: se pierden en DNS
    {
      line = $0
      # opciones tras "$": si la regla trae modificadores, es ambigua para DNS
      if (index(line, "$") > 0) next
      # forma ||dominio^
      if (line ~ /^\|\|[A-Za-z0-9._-]+\^?$/) {
        d = line
        sub(/^\|\|/, "", d)
        sub(/\^$/, "", d)
        print tolower(d)
        next
      }
    }
  ' > "$_out.abp.$$"
  # Validacion de dominio estricta + dedupe (reusa el criterio de security.sh)
  grep -E '^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)+$' "$_out.abp.$$" \
    | grep -Ev '^([0-9]{1,3}\.){3}[0-9]{1,3}$' | sort -u > "$_out"
  rm -f "$_out.abp.$$" 2>/dev/null
  wc -l < "$_out" | tr -d ' '
}

# ---------------------------------------------------------------------------
# Descarga + normalizacion de UNA fuente -> cache/<id>.list + .meta con metricas
# ---------------------------------------------------------------------------
cat_meta_set() {
  # $1 id ; luego pares clave valor
  _mid="$1"; shift
  _mf="$CAT_CACHE_DIR/$_mid.meta"; _mt="$_mf.tmp.$$"
  : > "$_mt"
  while [ $# -ge 2 ]; do printf '%s=%s\n' "$1" "$2" >> "$_mt"; shift 2; done
  mv -f "$_mt" "$_mf"; chmod 0600 "$_mf" 2>/dev/null
}
cat_meta_get() { grep "^$2=" "$CAT_CACHE_DIR/$1.meta" 2>/dev/null | tail -n1 | cut -d= -f2-; }

cat_update_one() {
  _id="$1"
  cat_exists "$_id" || { echo "ERROR: id desconocido en el catalogo: '$_id'" >&2; return 1; }
  _url=$(cat_field "$_id" 8)
  _fmt=$(cat_field "$_id" 7)
  case "$_url" in https://*|file://*) : ;; *) echo "ERROR ($_id): url invalida" >&2; return 1 ;; esac

  _raw="$RUN_DIR/cat.$_id.raw.$$"
  _norm="$RUN_DIR/cat.$_id.norm.$$"
  # 1-2) descarga (reusa sec_download: file:// solo en TEST_MODE) + HTTP
  if ! sec_download "$_url" "$_raw"; then
    echo "ERROR ($_id): descarga fallida" >&2; rm -f "$_raw"; return 1
  fi
  # 3) tamano
  _sz=$(wc -c < "$_raw" 2>/dev/null | tr -d ' ')
  [ "$_sz" -ge "$CAT_MIN_SOURCE_BYTES" ] 2>/dev/null && [ "$_sz" -le "$CAT_MAX_SOURCE_BYTES" ] 2>/dev/null || {
    echo "ERROR ($_id): tamano fuera de rango ($_sz bytes)" >&2; rm -f "$_raw"; return 1; }
  # 4) tipo (texto)
  if command -v sec_is_binary >/dev/null 2>&1 && sec_is_binary "$_raw"; then
    echo "ERROR ($_id): contenido binario" >&2; rm -f "$_raw"; return 1
  fi
  _sha=$(sec_sha256 "$_raw")
  _total=$(grep -cve '^[[:space:]]*$' "$_raw" 2>/dev/null)
  # 5) formato: si es 'auto' o vacio, detectar
  case "$_fmt" in ''|auto) _fmt=$(cat_detect_format "$_raw") ;; esac
  # 6-9) extraer + normalizar + validar + dedupe interno
  _partial=0
  if [ "$_fmt" = "abp" ]; then
    _valid=$(cat_abp_extract "$_raw" "$_norm"); _partial=1
  else
    _valid=$(sec_parse_domains "$_raw" "$_fmt" "$_norm")
  fi
  case "$_valid" in ''|*[!0-9]*) echo "ERROR ($_id): parseo fallo" >&2; rm -f "$_raw" "$_norm"; return 1 ;; esac
  [ "$_valid" -ge 1 ] || { echo "ERROR ($_id): 0 dominios validos" >&2; rm -f "$_raw" "$_norm"; return 1; }
  _invalid=$(( _total - _valid )); [ "$_invalid" -lt 0 ] && _invalid=0
  _shalist=$(sec_sha256 "$_norm")
  # 10) guardar fuente normalizada (atomico)
  mv -f "$_norm" "$CAT_CACHE_DIR/$_id.list" || { echo "ERROR ($_id): mv fallo" >&2; rm -f "$_raw"; return 1; }
  chmod 0600 "$CAT_CACHE_DIR/$_id.list" 2>/dev/null
  cat_meta_set "$_id" \
    id "$_id" format "$_fmt" partial_dns "$_partial" status verified \
    total_source "$_total" valid_domains "$_valid" invalid_entries "$_invalid" \
    sha256_raw "$_sha" sha256_list "$_shalist" bytes_raw "$_sz" \
    updated_at "$(date '+%Y-%m-%d %H:%M:%S')" updated_epoch "$(sec_now)"
  rm -f "$_raw" 2>/dev/null
  if [ "$_partial" = "1" ]; then
    echo "OK ($_id): $_valid dominios (formato ABP: cobertura DNS parcial)."
  else
    echo "OK ($_id): $_valid dominios validos ($_invalid ignorados)."
  fi
  log_msg "catalog update $_id: OK ($_valid dominios, fmt=$_fmt)"
  return 0
}

# ---------------------------------------------------------------------------
# Compilacion a escala (fusion de activas). Lock + espacio libre. El pipeline
# atomico/rollback real vive en sec_regen_and_reload (que llama sec_merge_blocked
# -> cat_append_active). Aca se agrega control operativo.
# ---------------------------------------------------------------------------
cat_free_kb() {
  df -k "$DATA_DIR" 2>/dev/null | awk 'NR==2 {print $4; found=1} END{ if(!found) print 0 }'
}

cat_compile() {
  # Lock anti doble-compilacion.
  if [ -e "$CAT_COMPILE_LOCK" ]; then
    _lpid=$(cat "$CAT_COMPILE_LOCK" 2>/dev/null)
    if [ -n "$_lpid" ] && kill -0 "$_lpid" 2>/dev/null; then
      echo "ERROR: ya hay una compilacion en curso (pid $_lpid)." >&2; return 1
    fi
  fi
  echo "$$" > "$CAT_COMPILE_LOCK" 2>/dev/null
  # Espacio libre.
  _free=$(cat_free_kb)
  if [ -n "$_free" ] && [ "$_free" -lt "$CAT_MIN_FREE_KB" ] 2>/dev/null; then
    rm -f "$CAT_COMPILE_LOCK"
    echo "ERROR: espacio libre insuficiente (${_free}KB < ${CAT_MIN_FREE_KB}KB)." >&2; return 1
  fi
  _t0=$(sec_now)
  echo "Compilando listas activas (categorias legacy + catalogo)…"
  # nice/ionice si estan disponibles (fallback seguro: correr normal).
  if command -v sec_regen_and_reload >/dev/null 2>&1; then
    if have nice; then nice -n 10 sh -c ':' 2>/dev/null; fi
    sec_regen_and_reload; _rc=$?
  else
    _rc=1
  fi
  _t1=$(sec_now)
  rm -f "$CAT_COMPILE_LOCK" 2>/dev/null
  _cnt=0; [ -f "$BL_BLOCKED" ] && _cnt=$(wc -l < "$BL_BLOCKED" | tr -d ' ')
  if [ "$_rc" = "0" ]; then
    echo "OK: compilacion terminada. $_cnt dominios activos en $((_t1 - _t0))s."
    log_msg "catalog compile: OK ($_cnt dominios, $((_t1 - _t0))s)"
  else
    echo "ERROR: la compilacion fallo (rc=$_rc). Se conserva la ultima lista valida." >&2
  fi
  return "$_rc"
}

# ---------------------------------------------------------------------------
# Conflictos / redundancia por METADATOS (sin O(N^2) automatico).
# Analisis exacto entre dos fuentes: solo bajo demanda.
# ---------------------------------------------------------------------------
cat_conflicts_report() {
  echo "Redundancias y conflictos entre fuentes ACTIVAS (por metadatos):"
  _any=0
  while IFS= read -r _id; do
    [ -n "$_id" ] || continue
    cat_is_enabled "$_id" || continue
    _sup=$(cat_field "$_id" 14)   # supersedes
    _cont=$(cat_field "$_id" 15)  # contained_by
    _ovl=$(cat_field "$_id" 16)   # overlaps_with
    _conf=$(cat_field "$_id" 17)  # conflicts_with
    # contained_by: si una activa esta contenida por otra activa -> redundante
    _oldIFS=$IFS; IFS=,
    for _c in $_cont; do
      [ -n "$_c" ] || continue
      if cat_is_enabled "$_c"; then
        echo "  [redundante] '$_id' ya esta contenida en '$_c' (activa). Podrias desactivar '$_id'."
        _any=1
      fi
    done
    for _s in $_sup; do
      [ -n "$_s" ] || continue
      if cat_is_enabled "$_s"; then
        echo "  [sustitucion] '$_id' hace redundante a '$_s' (activa). Estas fuentes no son incompatibles, pero gran parte de su contenido ya esta incluido."
        _any=1
      fi
    done
    for _o in $_ovl; do
      [ -n "$_o" ] || continue
      if cat_is_enabled "$_o"; then
        echo "  [superposicion] '$_id' y '$_o' se solapan bastante (ambas activas)."
        _any=1
      fi
    done
    for _x in $_conf; do
      [ -n "$_x" ] || continue
      case "$_x" in _service*)
        echo "  [conflicto funcional] '$_id' puede chocar con el control de servicio '$_x'. Elegí un comportamiento."
        _any=1 ;;
      *)
        if cat_is_enabled "$_x"; then
          echo "  [conflicto] '$_id' entra en conflicto con '$_x' (ambas activas)."
          _any=1
        fi ;;
      esac
    done
    IFS=$_oldIFS
  done < "$CAT_ENABLED"
  [ "$_any" = "0" ] && echo "  (sin redundancias ni conflictos conocidos entre las fuentes activas)"
  return 0
}

# Analisis EXACTO de solapamiento entre dos fuentes (bajo demanda, solo si
# ambas tienen cache). Usa comm si esta; si no, sort+grep.
cat_overlap_exact() {
  _a="$CAT_CACHE_DIR/$1.list"; _b="$CAT_CACHE_DIR/$2.list"
  [ -s "$_a" ] && [ -s "$_b" ] || { echo "ERROR: ambas fuentes deben estar descargadas." >&2; return 1; }
  _na=$(wc -l < "$_a" | tr -d ' '); _nb=$(wc -l < "$_b" | tr -d ' ')
  if have comm; then
    _common=$(comm -12 "$_a" "$_b" | wc -l | tr -d ' ')
  else
    _common=$(sort "$_a" "$_b" | uniq -d | wc -l | tr -d ' ')
  fi
  _pct=0; [ "$_na" -gt 0 ] && _pct=$(( _common * 100 / _na ))
  echo "Solapamiento exacto '$1' ($_na) vs '$2' ($_nb): $_common dominios en comun (~$_pct% de '$1')."
}

# ---------------------------------------------------------------------------
# Fuentes personalizadas
# ---------------------------------------------------------------------------
cat_custom_slug() { printf '%s' "$1" | tr 'A-Z' 'a-z' | tr -cd 'a-z0-9_-' | cut -c1-40; }

cat_custom_add() {
  # $1 url  [--name N] [--category C] [--format F]
  _url="$1"; shift 2>/dev/null
  case "$_url" in https://*) : ;; *) echo "ERROR: solo https:// para fuentes personalizadas." >&2; return 1 ;; esac
  _name=""; _catg="custom"; _fmt="auto"
  while [ $# -gt 0 ]; do
    case "$1" in
      --name) _name=$(printf '%s' "$2" | tr -d '\t\n' | cut -c1-60); shift 2 ;;
      --category) _catg=$(printf '%s' "$2" | tr -cd 'a-z_,'); shift 2 ;;
      --format) case "$2" in hosts|domains|abp|auto) _fmt="$2" ;; esac; shift 2 ;;
      *) shift ;;
    esac
  done
  [ -n "$_name" ] || _name="Fuente personalizada"
  _slug=$(cat_custom_slug "$_name")
  [ -n "$_slug" ] || _slug=$(echo "$_url" | md5sum 2>/dev/null | cut -c1-12)
  _id="custom_$_slug"
  # Evitar colision de id
  if cat_exists "$_id"; then _id="custom_${_slug}_$(date +%s)"; fi
  # 19 columnas, mismo orden que el index
  _row="$_id	custom	$_name	usuario	$_catg	medium	$_fmt	$_url	unknown	custom	0	unknown	0				$(date '+%Y-%m-%d')	Fuente personalizada agregada por el usuario."
  printf '%s\n' "$_row" >> "$CAT_CUSTOM"
  chmod 0600 "$CAT_CUSTOM" 2>/dev/null
  echo "OK: fuente personalizada agregada con id '$_id'. Probala con: dnscrypt-manager catalog test $_id"
  log_msg "catalog custom add $_id ($_url)"
}

cat_custom_remove() {
  _id="$1"
  case "$_id" in custom_*) : ;; *) echo "ERROR: solo se pueden eliminar fuentes 'custom_*'." >&2; return 1 ;; esac
  grep -q "^$_id	" "$CAT_CUSTOM" 2>/dev/null || { echo "ERROR: no existe '$_id'." >&2; return 1; }
  _t="$CAT_CUSTOM.tmp.$$"
  awk -F'\t' -v id="$_id" '$1 != id' "$CAT_CUSTOM" > "$_t"
  mv -f "$_t" "$CAT_CUSTOM"; chmod 0600 "$CAT_CUSTOM" 2>/dev/null
  cat_disable "$_id"
  rm -f "$CAT_CACHE_DIR/$_id.list" "$CAT_CACHE_DIR/$_id.meta" 2>/dev/null
  echo "OK: fuente '$_id' eliminada."
  log_msg "catalog custom remove $_id"
}

# Prueba de descarga: cabeceras HTTP + SHA-256 sin activar la fuente.
cat_test_source() {
  _id="$1"
  cat_exists "$_id" || { echo "ERROR: id desconocido: '$_id'" >&2; return 1; }
  _url=$(cat_field "$_id" 8)
  echo "Probando '$_id' -> $_url"
  case "$_url" in
    file://*)
      [ "${DNSCRYPT_TEST_MODE:-0}" = "1" ] || { echo "file:// solo en modo test" >&2; return 1; }
      _p="${_url#file://}"
      [ -f "$_p" ] && echo "  archivo local OK, sha256=$(sec_sha256 "$_p"), bytes=$(wc -c < "$_p" | tr -d ' ')" || { echo "  no existe" >&2; return 1; } ;;
    https://*)
      if have curl; then
        echo "  --- cabeceras HTTP ---"
        curl -fsSI --max-time 30 "$_url" 2>/dev/null | sed 's/^/  /' | head -15
      fi
      _tmp="$RUN_DIR/cat.test.$$"
      if sec_download "$_url" "$_tmp"; then
        echo "  descarga OK: sha256=$(sec_sha256 "$_tmp"), bytes=$(wc -c < "$_tmp" | tr -d ' '), formato_detectado=$(cat_detect_format "$_tmp")"
        rm -f "$_tmp"
      else
        echo "  ERROR: la descarga fallo" >&2; return 1
      fi ;;
  esac
}

# ---------------------------------------------------------------------------
# Presentacion (list/info) en texto y JSON
# ---------------------------------------------------------------------------
cat_json_escape() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

cmd_catalog() {
  cat_init_dirs
  _sub="${1:-list}"; shift 2>/dev/null
  case "$_sub" in
    sync) cat_sync_index; echo "OK: index del catalogo sincronizado ($(cat_all_ids | wc -l | tr -d ' ') entradas)." ;;

    list)
      _json=0; _filter_cat=""; _filter_maint=""; _only_enabled=0; _only_recommended=0; _only_archived=0; _search=""
      while [ $# -gt 0 ]; do
        case "$1" in
          --json) _json=1; shift ;;
          --category) _filter_cat="$2"; shift 2 ;;
          --maintainer) _filter_maint="$2"; shift 2 ;;
          --enabled) _only_enabled=1; shift ;;
          --recommended) _only_recommended=1; shift ;;
          --archived) _only_archived=1; shift ;;
          --search) _search=$(printf '%s' "$2" | tr 'A-Z' 'a-z'); shift 2 ;;
          *) shift ;;
        esac
      done
      _print_one() {
        _id="$1"
        _row=$(cat_row "$_id"); [ -n "$_row" ] || return 0
        _name=$(printf '%s' "$_row" | cut -f3); _maint=$(printf '%s' "$_row" | cut -f4)
        _cats=$(printf '%s' "$_row" | cut -f5); _agg=$(printf '%s' "$_row" | cut -f6)
        _fmt=$(printf '%s' "$_row" | cut -f7); _lic=$(printf '%s' "$_row" | cut -f9)
        _ups=$(cat_effective_status "$_id"); _rec=$(printf '%s' "$_row" | cut -f11)
        _mob=$(printf '%s' "$_row" | cut -f12); _arch=$(printf '%s' "$_row" | cut -f13)
        _desc=$(printf '%s' "$_row" | cut -f19)
        # filtros
        [ "$_only_enabled" = "1" ] && { cat_is_enabled "$_id" || return 0; }
        [ "$_only_recommended" = "1" ] && [ "$_rec" != "1" ] && return 0
        [ "$_only_archived" = "1" ] && [ "$_arch" != "1" ] && return 0
        [ -n "$_filter_cat" ] && { printf '%s' ",$_cats," | grep -q ",$_filter_cat," || return 0; }
        [ -n "$_filter_maint" ] && { printf '%s' "$_maint" | grep -qiF "$_filter_maint" || return 0; }
        [ -n "$_search" ] && { printf '%s' "$_id $_name $_desc $_cats" | tr 'A-Z' 'a-z' | grep -qF "$_search" || return 0; }
        _en=no; cat_is_enabled "$_id" && _en=si
        _dom=$(cat_meta_get "$_id" valid_domains); [ -n "$_dom" ] || _dom="-"
        if [ "$_json" = "1" ]; then
          _enb=false; cat_is_enabled "$_id" && _enb=true
          _recb=false; [ "$_rec" = "1" ] && _recb=true
          _arb=false; [ "$_arch" = "1" ] && _arb=true
          [ "$CAT_JSON_FIRST" = "0" ] && printf ','
          CAT_JSON_FIRST=0
          printf '{"id":"%s","name":"%s","maintainer":"%s","categories":"%s","aggressiveness":"%s","format":"%s","license":"%s","upstream_status":"%s","mobile_suitability":"%s","recommended":%s,"archived":%s,"enabled":%s,"valid_domains":"%s"}' \
            "$(cat_json_escape "$_id")" "$(cat_json_escape "$_name")" "$(cat_json_escape "$_maint")" \
            "$(cat_json_escape "$_cats")" "$_agg" "$_fmt" "$(cat_json_escape "$_lic")" "$_ups" "$_mob" \
            "$_recb" "$_arb" "$_enb" "$_dom"
        else
          printf '  [%s] %-34s %-12s %-9s dom=%-8s %s%s\n' \
            "$_en" "$_id" "$_maint" "$_agg" "$_dom" \
            "$( [ "$_rec" = 1 ] && echo '(recomendada) ' )" \
            "$( [ "$_arch" = 1 ] && echo '(ARCHIVADA) ' )"
        fi
      }
      if [ "$_json" = "1" ]; then
        CAT_JSON_FIRST=1
        printf '{"entries":['
        cat_all_ids | while IFS= read -r _id; do _print_one "$_id"; done
        printf ']}\n'
      else
        echo "Catalogo de listas (marca [si/no] = activa):"
        cat_all_ids | while IFS= read -r _id; do _print_one "$_id"; done
        echo "Total: $(cat_all_ids | wc -l | tr -d ' ') fuentes. Activas: $(grep -c . "$CAT_ENABLED" 2>/dev/null)."
      fi
      ;;

    info)
      _id="$1"
      cat_exists "$_id" || { echo "ERROR: id desconocido: '$_id'" >&2; return 1; }
      _row=$(cat_row "$_id")
      echo "id           : $_id"
      echo "nombre       : $(printf '%s' "$_row" | cut -f3)"
      echo "familia      : $(printf '%s' "$_row" | cut -f2)"
      echo "mantenedor   : $(printf '%s' "$_row" | cut -f4)"
      echo "categorias   : $(printf '%s' "$_row" | cut -f5)"
      echo "agresividad  : $(printf '%s' "$_row" | cut -f6)"
      echo "formato      : $(printf '%s' "$_row" | cut -f7)"
      echo "url          : $(printf '%s' "$_row" | cut -f8)"
      echo "licencia     : $(printf '%s' "$_row" | cut -f9)"
      echo "estado       : $(cat_effective_status "$_id")"
      echo "movil        : $(printf '%s' "$_row" | cut -f12)"
      echo "recomendada  : $( [ "$(printf '%s' "$_row" | cut -f11)" = 1 ] && echo si || echo no )"
      echo "archivada    : $( [ "$(printf '%s' "$_row" | cut -f13)" = 1 ] && echo si || echo no )"
      echo "sustituye a  : $(printf '%s' "$_row" | cut -f14)"
      echo "contenida en : $(printf '%s' "$_row" | cut -f15)"
      echo "se solapa con: $(printf '%s' "$_row" | cut -f16)"
      echo "conflictos   : $(printf '%s' "$_row" | cut -f17)"
      echo "activa       : $( cat_is_enabled "$_id" && echo si || echo no )"
      echo "descripcion  : $(printf '%s' "$_row" | cut -f19)"
      _m="$CAT_CACHE_DIR/$_id.meta"
      if [ -f "$_m" ]; then
        echo "--- metricas de la ultima descarga ---"
        echo "  total_source   : $(cat_meta_get "$_id" total_source)"
        echo "  valid_domains  : $(cat_meta_get "$_id" valid_domains)"
        echo "  invalid_entries: $(cat_meta_get "$_id" invalid_entries)"
        echo "  sha256_list    : $(cat_meta_get "$_id" sha256_list)"
        echo "  cobertura DNS  : $( [ "$(cat_meta_get "$_id" partial_dns)" = 1 ] && echo 'parcial (ABP)' || echo completa )"
        echo "  actualizada    : $(cat_meta_get "$_id" updated_at)"
      else
        echo "(aun no descargada: usa 'catalog update $_id')"
      fi
      ;;

    enable)
      _id="$1"
      cat_exists "$_id" || { echo "ERROR: id desconocido: '$_id'" >&2; return 1; }
      [ "$(cat_field "$_id" 13)" = "1" ] && echo "AVISO: '$_id' esta ARCHIVADA (legado). Se activa igual, pero no es recomendable."
      cat_enable "$_id"
      if [ ! -s "$CAT_CACHE_DIR/$_id.list" ]; then
        echo "'$_id' habilitada, pero aun sin descargar. Descargando…"
        cat_update_one "$_id" || { echo "AVISO: la descarga fallo; quedara activa pero sin aportar dominios hasta actualizar." >&2; }
      fi
      cat_compile || return 1
      echo "OK: '$_id' activada y compilada."
      ;;

    disable)
      _id="$1"
      cat_is_enabled "$_id" || { echo "'$_id' no estaba activa."; return 0; }
      cat_disable "$_id"
      cat_compile || return 1
      echo "OK: '$_id' desactivada y recompilada."
      ;;

    update)
      _tgt="${1:-enabled}"
      if [ "$_tgt" = "enabled" ] || [ "$_tgt" = "all" ]; then
        _fails=0; _n=0
        while IFS= read -r _id; do
          [ -n "$_id" ] || continue
          _n=$((_n+1))
          cat_update_one "$_id" || _fails=$((_fails+1))
        done < "$CAT_ENABLED"
        [ "$_n" = "0" ] && { echo "(no hay fuentes activas para actualizar)"; return 0; }
        cat_compile || _fails=$((_fails+1))
        [ "$_fails" = "0" ] && echo "OK: $_n fuente(s) activa(s) actualizada(s) y compiladas." || { echo "ERROR: $_fails fallo(s)." >&2; return 1; }
      else
        cat_update_one "$_tgt" || return 1
        cat_is_enabled "$_tgt" && cat_compile
      fi
      ;;

    compile) cat_compile ;;
    conflicts)
      if [ -n "$1" ] && [ -n "$2" ]; then cat_overlap_exact "$1" "$2"; else cat_conflicts_report; fi ;;
    metrics)
      _id="$1"; cat_exists "$_id" || { echo "ERROR: id desconocido" >&2; return 1; }
      echo "Metricas de '$_id':"
      for _k in total_source valid_domains invalid_entries sha256_list partial_dns updated_at; do
        echo "  $_k = $(cat_meta_get "$_id" "$_k")"
      done ;;
    test) cat_test_source "$1" ;;

    custom)
      _cs="$1"; shift 2>/dev/null
      case "$_cs" in
        add) cat_custom_add "$@" ;;
        remove) cat_custom_remove "$1" ;;
        list)
          if [ -s "$CAT_CUSTOM" ]; then
            echo "Fuentes personalizadas:"
            awk -F'\t' '{printf "  %-28s %s  [%s]\n", $1, $8, $7}' "$CAT_CUSTOM"
          else echo "(sin fuentes personalizadas)"; fi ;;
        export)
          _dst="${1:-$CAT_DIR/custom-export-$(date '+%Y%m%d-%H%M%S').tsv}"
          cp -f "$CAT_CUSTOM" "$_dst" 2>/dev/null && echo "OK: catalogo personalizado exportado a $_dst" || { echo "ERROR: no se pudo exportar" >&2; return 1; } ;;
        *) echo "Uso: catalog custom {add <url> [--name N][--category C][--format F]|remove <id>|list|export [ruta]}" >&2; return 1 ;;
      esac ;;

    *)
      echo "Uso: dnscrypt-manager catalog {list [--json][--search S][--category C][--maintainer M][--enabled][--recommended][--archived]|info <id>|enable <id>|disable <id>|update [id|enabled|all]|compile|conflicts [id1 id2]|metrics <id>|test <id>|custom ...|sync}" >&2
      return 1 ;;
  esac
}

##############################################################################
# IMPORTADOR BINDHOSTS
# Archivos: sources.txt / blacklist.txt / whitelist.txt / custom.txt
# Por defecto ANALIZA (dry-run) y muestra un resumen; aplica solo con --confirmed.
##############################################################################

# Normaliza una entrada a dominio: quita esquema/rutas de una URL, minusculas,
# recorta espacios. Devuelve "" si no es convertible a un dominio simple.
cat_url_to_domain() {
  _v=$(printf '%s' "$1" | tr -d '\r' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | tr 'A-Z' 'a-z')
  case "$_v" in
    http://*|https://*)
      _v=$(printf '%s' "$_v" | sed -E 's#^https?://##; s#/.*$##; s#:[0-9]+$##') ;;
  esac
  printf '%s' "$_v"
}

# Clasifica un token de dominio: echo "ok"|"example"|"suspicious"|"invalid"
cat_domain_class() {
  _d="$1"
  # Sospechoso (envuelto): un dominio real seguido de un placeholder, p.ej.
  # s.youtube.com.domain.name. Se marca y NUNCA se importa automaticamente.
  case "$_d" in
    *.domain.name|*.domain.invalid|*.example.example) echo suspicious; return ;;
  esac
  # Entrada de ejemplo: TLDs reservados (RFC 2606/6761). No son dominios reales;
  # se detectan como "entrada de ejemplo" y no se importan.
  case "$_d" in
    *.example|*.example.com|*.example.org|*.example.net|example.com|example.org|example.net|*.test|*.invalid|*.localhost|*.local|localhost)
      echo example; return ;;
  esac
  if command -v sec_valid_domain >/dev/null 2>&1 && sec_valid_domain "$_d"; then
    echo ok
  else
    echo invalid
  fi
}

# Analiza un set BindHosts. Escribe planes a $CAT_BH_WORK/*.plan y cuenta.
cat_bindhosts_scan() {
  _dir="$1"
  CAT_BH_WORK="$RUN_DIR/bh.$$"; mkdir -p "$CAT_BH_WORK"
  : > "$CAT_BH_WORK/sources.match"; : > "$CAT_BH_WORK/sources.custom"
  : > "$CAT_BH_WORK/sources.broken"; : > "$CAT_BH_WORK/sources.archived"
  : > "$CAT_BH_WORK/black.ok"; : > "$CAT_BH_WORK/allow.ok"
  : > "$CAT_BH_WORK/suspicious"; : > "$CAT_BH_WORK/example"; : > "$CAT_BH_WORK/invalid"; : > "$CAT_BH_WORK/ignored"
  : > "$CAT_BH_WORK/dups"; : > "$CAT_BH_WORK/sources.dups"

  # --- sources.txt: URLs de blocklists ---
  if [ -f "$_dir/sources.txt" ]; then
    while IFS= read -r _line; do
      _l=$(printf '%s' "$_line" | tr -d '\r' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
      [ -n "$_l" ] || continue
      case "$_l" in \#*|!*) continue ;; esac
      case "$_l" in
        https://*) : ;;
        http://*) printf '%s\n' "$_l" >> "$CAT_BH_WORK/sources.broken"; continue ;;
        *) printf '%s\n' "$_l" >> "$CAT_BH_WORK/sources.broken"; continue ;;
      esac
      # match contra el catalogo por primary_url
      _mid=$(awk -F'\t' -v u="$_l" '!/^#/ && $8==u {print $1; exit}' "$CAT_INDEX" 2>/dev/null)
      if [ -n "$_mid" ]; then
        _arch=$(cat_field "$_mid" 13)
        if [ "$_arch" = "1" ]; then printf '%s\t%s\n' "$_mid" "$_l" >> "$CAT_BH_WORK/sources.archived"
        else printf '%s\t%s\n' "$_mid" "$_l" >> "$CAT_BH_WORK/sources.match"; fi
      else
        printf '%s\n' "$_l" >> "$CAT_BH_WORK/sources.custom"
      fi
    done < "$_dir/sources.txt"
    # Detectar fuentes duplicadas (misma id o misma URL). StevenBlack repetido, etc.
    if [ -s "$CAT_BH_WORK/sources.match" ]; then
      _mb=$(wc -l < "$CAT_BH_WORK/sources.match" | tr -d ' ')
      sort -u "$CAT_BH_WORK/sources.match" -o "$CAT_BH_WORK/sources.match"
      _ma=$(wc -l < "$CAT_BH_WORK/sources.match" | tr -d ' ')
      _dd=$(( _mb - _ma )); [ "$_dd" -gt 0 ] && echo "fuentes catalogo duplicadas:$_dd" >> "$CAT_BH_WORK/sources.dups"
    fi
    for _cf in sources.custom sources.archived sources.broken; do
      _p="$CAT_BH_WORK/$_cf"; [ -s "$_p" ] || continue
      _cb=$(wc -l < "$_p" | tr -d ' '); sort -u "$_p" -o "$_p"; _ca=$(wc -l < "$_p" | tr -d ' ')
      _cd=$(( _cb - _ca )); [ "$_cd" -gt 0 ] && echo "$_cf duplicadas:$_cd" >> "$CAT_BH_WORK/sources.dups"
    done
  fi

  # --- blacklist.txt: dominios a bloquear ---
  if [ -f "$_dir/blacklist.txt" ]; then
    while IFS= read -r _line; do
      _l=$(printf '%s' "$_line" | tr -d '\r' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
      [ -n "$_l" ] || continue
      case "$_l" in \#*|!*) continue ;; esac
      _d=$(cat_url_to_domain "$_l")
      case "$(cat_domain_class "$_d")" in
        ok) printf '%s\n' "$_d" >> "$CAT_BH_WORK/black.ok" ;;
        example) printf '%s\t(blacklist)\n' "$_d" >> "$CAT_BH_WORK/example" ;;
        suspicious) printf '%s\t(blacklist)\n' "$_d" >> "$CAT_BH_WORK/suspicious" ;;
        *) printf '%s\t(blacklist)\n' "$_l" >> "$CAT_BH_WORK/invalid" ;;
      esac
    done < "$_dir/blacklist.txt"
  fi

  # --- whitelist.txt: dominios a permitir (RECHAZA URLs) ---
  if [ -f "$_dir/whitelist.txt" ]; then
    while IFS= read -r _line; do
      _l=$(printf '%s' "$_line" | tr -d '\r' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
      [ -n "$_l" ] || continue
      case "$_l" in \#*|!*) continue ;; esac
      case "$_l" in
        http://*|https://*) printf '%s\t(URL en whitelist: rechazada)\n' "$_l" >> "$CAT_BH_WORK/invalid"; continue ;;
      esac
      _d=$(printf '%s' "$_l" | tr 'A-Z' 'a-z')
      case "$(cat_domain_class "$_d")" in
        ok) printf '%s\n' "$_d" >> "$CAT_BH_WORK/allow.ok" ;;
        example) printf '%s\t(whitelist)\n' "$_d" >> "$CAT_BH_WORK/example" ;;
        suspicious) printf '%s\t(whitelist)\n' "$_d" >> "$CAT_BH_WORK/suspicious" ;;
        *) printf '%s\t(whitelist)\n' "$_l" >> "$CAT_BH_WORK/invalid" ;;
      esac
    done < "$_dir/whitelist.txt"
  fi

  # --- custom.txt: pares IP + dominio ---
  if [ -f "$_dir/custom.txt" ]; then
    while IFS= read -r _line; do
      _l=$(printf '%s' "$_line" | tr -d '\r' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
      [ -n "$_l" ] || continue
      case "$_l" in \#*|!*) continue ;; esac
      case "$_l" in http://*|https://*) printf '%s\t(URL en custom: no es un par hosts)\n' "$_l" >> "$CAT_BH_WORK/ignored"; continue ;; esac
      _ip=$(printf '%s' "$_l" | awk '{print $1}')
      _dom=$(printf '%s' "$_l" | awk '{print $2}' | tr 'A-Z' 'a-z')
      [ -n "$_dom" ] || { printf '%s\t(sin dominio)\n' "$_l" >> "$CAT_BH_WORK/invalid"; continue; }
      case "$(cat_domain_class "$_dom")" in
        ok) : ;;
        example) printf '%s\t(custom)\n' "$_dom" >> "$CAT_BH_WORK/example"; continue ;;
        suspicious) printf '%s\t(custom)\n' "$_dom" >> "$CAT_BH_WORK/suspicious"; continue ;;
        *) printf '%s\t(custom)\n' "$_l" >> "$CAT_BH_WORK/invalid"; continue ;;
      esac
      case "$_ip" in
        0.0.0.0|127.0.0.1|::|::1) printf '%s\n' "$_dom" >> "$CAT_BH_WORK/black.ok" ;;
        *) printf '%s -> %s\t(mapeo de IP no soportado; se ignora)\n' "$_ip" "$_dom" >> "$CAT_BH_WORK/ignored" ;;
      esac
    done < "$_dir/custom.txt"
  fi

  # dedupe y conteo de duplicados
  for _f in black.ok allow.ok; do
    _p="$CAT_BH_WORK/$_f"
    [ -s "$_p" ] || continue
    _before=$(wc -l < "$_p" | tr -d ' ')
    sort -u "$_p" -o "$_p"
    _after=$(wc -l < "$_p" | tr -d ' ')
    _d=$(( _before - _after )); [ "$_d" -gt 0 ] && echo "$_f:$_d" >> "$CAT_BH_WORK/dups"
  done
  return 0
}

cat_bindhosts_summary() {
  echo "Resumen de importacion BindHosts:"
  echo "  fuentes reconocidas (catalogo) : $(grep -c . "$CAT_BH_WORK/sources.match" 2>/dev/null)"
  echo "  fuentes -> personalizadas      : $(grep -c . "$CAT_BH_WORK/sources.custom" 2>/dev/null)"
  echo "  fuentes archivadas             : $(grep -c . "$CAT_BH_WORK/sources.archived" 2>/dev/null)"
  echo "  fuentes rotas/invalidas        : $(grep -c . "$CAT_BH_WORK/sources.broken" 2>/dev/null)"
  echo "  dominios a blacklist (validos) : $(grep -c . "$CAT_BH_WORK/black.ok" 2>/dev/null)"
  echo "  dominios a allowlist (validos) : $(grep -c . "$CAT_BH_WORK/allow.ok" 2>/dev/null)"
  echo "  entradas de ejemplo (ignoradas): $(grep -c . "$CAT_BH_WORK/example" 2>/dev/null)"
  echo "  sospechosos (revisar)          : $(grep -c . "$CAT_BH_WORK/suspicious" 2>/dev/null)"
  echo "  invalidos rechazados           : $(grep -c . "$CAT_BH_WORK/invalid" 2>/dev/null)"
  if [ -s "$CAT_BH_WORK/sources.dups" ]; then
    echo "  --- duplicados de fuentes detectados ---"
    sed 's/^/    /' "$CAT_BH_WORK/sources.dups"
  fi
  echo "  ignorados (mapeos IP / URLs)   : $(grep -c . "$CAT_BH_WORK/ignored" 2>/dev/null)"
  if [ -s "$CAT_BH_WORK/suspicious" ]; then
    echo "  --- sospechosos (NO se importan sin revision) ---"
    sed 's/^/    /' "$CAT_BH_WORK/suspicious" | head -20
  fi
}

cmd_bindhosts() {
  cat_init_dirs
  _sub="${1:-analyze}"; shift 2>/dev/null
  _dir="$1"; shift 2>/dev/null
  [ -n "$_dir" ] || { echo "Uso: dnscrypt-manager bindhosts {analyze|import} <directorio> [--confirmed]" >&2; return 1; }
  case "$_dir" in *..*) echo "ERROR: ruta invalida" >&2; return 1 ;; esac
  [ -d "$_dir" ] || { echo "ERROR: no es un directorio: $_dir" >&2; return 1; }

  cat_bindhosts_scan "$_dir"
  cat_bindhosts_summary

  case "$_sub" in
    analyze)
      echo "(analisis: no se aplico nada. Para aplicar: dnscrypt-manager bindhosts import $_dir --confirmed)"
      rm -rf "$CAT_BH_WORK" 2>/dev/null
      return 0 ;;
    import)
      _confirmed=0
      for _a in "$@"; do [ "$_a" = "--confirmed" ] && _confirmed=1; done
      if [ "$_confirmed" != "1" ]; then
        echo "No se aplico nada. Repeti con --confirmed para importar." >&2
        rm -rf "$CAT_BH_WORK" 2>/dev/null
        return 3
      fi
      # blacklist manual (append + dedupe)
      if [ -s "$CAT_BH_WORK/black.ok" ]; then
        { cat "$CAT_BLACKLIST" 2>/dev/null; cat "$CAT_BH_WORK/black.ok"; } | sort -u > "$CAT_BLACKLIST.tmp.$$"
        mv -f "$CAT_BLACKLIST.tmp.$$" "$CAT_BLACKLIST"; chmod 0600 "$CAT_BLACKLIST" 2>/dev/null
      fi
      # allowlist (via CLI para revalidar cada dominio)
      _al=0
      if [ -s "$CAT_BH_WORK/allow.ok" ]; then
        while IFS= read -r _d; do
          [ -n "$_d" ] || continue
          cmd_allowlist add "$_d" >/dev/null 2>&1 && _al=$((_al+1))
        done < "$CAT_BH_WORK/allow.ok"
      fi
      # fuentes: match -> habilitar; custom -> agregar (sin activar)
      _en=0
      if [ -s "$CAT_BH_WORK/sources.match" ]; then
        while IFS= read -r _lm; do
          _mid=$(printf '%s' "$_lm" | cut -f1)
          [ -n "$_mid" ] && cat_enable "$_mid" && _en=$((_en+1))
        done < "$CAT_BH_WORK/sources.match"
      fi
      _cu=0
      if [ -s "$CAT_BH_WORK/sources.custom" ]; then
        while IFS= read -r _url; do
          [ -n "$_url" ] || continue
          cat_custom_add "$_url" --name "BindHosts import" >/dev/null 2>&1 && _cu=$((_cu+1))
        done < "$CAT_BH_WORK/sources.custom"
      fi
      # recompilar con todo lo nuevo
      cat_compile >/dev/null 2>&1
      echo "OK: importado. blacklist += $(grep -c . "$CAT_BH_WORK/black.ok" 2>/dev/null), allowlist += $_al, fuentes activadas: $_en, fuentes personalizadas: $_cu."
      echo "    (fuentes personalizadas quedan AGREGADAS pero NO activadas; revisalas en el catalogo)."
      log_msg "bindhosts import: black+$(grep -c . "$CAT_BH_WORK/black.ok" 2>/dev/null) allow+$_al enable+$_en custom+$_cu"
      rm -rf "$CAT_BH_WORK" 2>/dev/null
      return 0 ;;
    *)
      rm -rf "$CAT_BH_WORK" 2>/dev/null
      echo "Uso: dnscrypt-manager bindhosts {analyze|import} <directorio> [--confirmed]" >&2
      return 1 ;;
  esac
}

# Adaptador para el comando top-level `import-bindhosts DIR [--dry-run|--confirmed]`.
# Dry-run (o sin flag) = seguro, no modifica nada. --confirmed = aplica atomico.
cmd_import_bindhosts() {
  _dir=""; _mode="analyze"
  while [ $# -gt 0 ]; do
    case "$1" in
      --dry-run) _mode="analyze" ;;
      --confirmed|--apply) _mode="import" ;;
      -*) : ;;
      *) [ -z "$_dir" ] && _dir="$1" ;;
    esac
    shift
  done
  [ -n "$_dir" ] || { echo "Uso: dnscrypt-manager import-bindhosts <directorio> [--dry-run|--confirmed]" >&2; return 1; }
  if [ "$_mode" = "import" ]; then
    cmd_bindhosts import "$_dir" --confirmed
  else
    cmd_bindhosts analyze "$_dir"
  fi
}

##############################################################################
# CONTROLES DE PRIVACIDAD POR SERVICIO (motor separado de las blocklists)
# Estado: $CAT_DIR/service-state.tsv  ->  id \t mode \t block_until \t bootid
#   block_until: epoch | "always" | "boot" | "0" (off)
# Los dominios de controles ACTIVOS se suman a la compilacion (cat_append_active).
# La blacklist/allowlist manual del usuario siguen siendo independientes.
##############################################################################
SVC_INDEX="$CAT_DIR/service-controls.index.tsv"
SVC_STATE="$CAT_DIR/service-state.tsv"

svc_init() { [ -f "$SVC_STATE" ] || : > "$SVC_STATE"; chmod 0600 "$SVC_STATE" 2>/dev/null; }

svc_sync_index() {
  _src="$MODDIR/config/catalog/service-controls.index.tsv"
  [ -f "$_src" ] || return 0
  if [ ! -f "$SVC_INDEX" ] || ! cmp -s "$_src" "$SVC_INDEX" 2>/dev/null; then
    cp -f "$_src" "$SVC_INDEX" 2>/dev/null; chmod 0600 "$SVC_INDEX" 2>/dev/null
  fi
}

svc_row() { awk -F'\t' -v id="$1" '!/^#/ && $1==id {print; exit}' "$SVC_INDEX" 2>/dev/null; }
svc_exists() { [ -n "$(svc_row "$1")" ]; }
svc_field() { svc_row "$1" | awk -F'\t' -v n="$2" '{print $n}'; }
svc_block_domains() { svc_field "$1" 4 | tr ',' '\n' | grep -v '^$'; }

# Estado actual (mode) de un control, respetando expiracion.
svc_state_line() { awk -F'\t' -v id="$1" '$1==id {print; exit}' "$SVC_STATE" 2>/dev/null; }
svc_current_mode() {
  _l=$(svc_state_line "$1"); [ -n "$_l" ] || { echo normal; return; }
  _mode=$(printf '%s' "$_l" | cut -f2)
  _until=$(printf '%s' "$_l" | cut -f3)
  _bid=$(printf '%s' "$_l" | cut -f4)
  case "$_until" in
    always) echo "$_mode" ;;
    boot) if [ "$_bid" = "$(sec_bootid)" ]; then echo "$_mode"; else echo normal; fi ;;
    0|'') echo normal ;;
    *) if [ "$_until" -gt "$(sec_now)" ] 2>/dev/null; then echo "$_mode"; else echo normal; fi ;;
  esac
}

# Un control esta "bloqueando" si su modo actual != normal.
svc_is_blocking() { [ "$(svc_current_mode "$1")" != "normal" ]; }

# Dominios que deben bloquearse AHORA por controles activos (para compilacion).
cat_svc_active_blocked() {
  [ -f "$SVC_INDEX" ] || return 0
  awk -F'\t' '!/^#/ {print $1}' "$SVC_INDEX" 2>/dev/null | while IFS= read -r _id; do
    [ -n "$_id" ] || continue
    if svc_is_blocking "$_id"; then svc_block_domains "$_id"; fi
  done
}

svc_set_state() {
  # $1 id  $2 mode  $3 until  $4 bootid
  svc_init
  _t="$SVC_STATE.tmp.$$"
  awk -F'\t' -v id="$1" '$1 != id' "$SVC_STATE" > "$_t" 2>/dev/null
  printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" >> "$_t"
  mv -f "$_t" "$SVC_STATE"; chmod 0600 "$SVC_STATE" 2>/dev/null
}

# Reporta conflicto allowlist vs control (allowlist gana, pero se avisa).
svc_check_allowlist_conflict() {
  _id="$1"; _conf=0
  svc_block_domains "$_id" | while IFS= read -r _d; do
    [ -n "$_d" ] || continue
    if command -v sec_allow_contains >/dev/null 2>&1 && sec_allow_contains "$_d"; then
      echo "  [conflicto] '$_d' esta en la allowlist Y este control quiere bloquearlo."
      echo "              La allowlist tiene prioridad: el control NO tendra efecto sobre '$_d'."
      echo "              Elegí una conducta coherente: quitalo de la allowlist o no uses este control."
    fi
  done
}

cmd_service() {
  cat_init_dirs; svc_init
  _sub="${1:-list}"; shift 2>/dev/null
  case "$_sub" in
    sync) svc_sync_index; echo "OK: controles de servicio sincronizados." ;;
    list)
      if [ "${1:-}" = "--json" ]; then
        printf '{"controls":['
        _first=1
        awk -F'\t' '!/^#/ {print $1}' "$SVC_INDEX" 2>/dev/null | while IFS= read -r _id; do
          [ "$_first" = 0 ] && printf ','; _first=0
          printf '{"id":"%s","service":"%s","name":"%s","mode":"%s","confidence":"%s"}' \
            "$_id" "$(svc_field "$_id" 2)" "$(cat_json_escape "$(svc_field "$_id" 3)")" \
            "$(svc_current_mode "$_id")" "$(svc_field "$_id" 5)"
        done
        printf ']}\n'
      else
        echo "Controles de privacidad por servicio:"
        awk -F'\t' '!/^#/ {print $1}' "$SVC_INDEX" 2>/dev/null | while IFS= read -r _id; do
          [ -n "$_id" ] || continue
          printf '  [%s] %-22s %s\n' "$(svc_current_mode "$_id")" "$_id" "$(svc_field "$_id" 3)"
        done
        [ -s "$SVC_INDEX" ] || echo "  (sin controles disponibles; corre 'migrate' o 'service sync')"
      fi ;;
    info|status)
      _id="$1"; svc_exists "$_id" || { echo "ERROR: control desconocido: '$_id'" >&2; return 1; }
      echo "id           : $_id"
      echo "servicio     : $(svc_field "$_id" 2)"
      echo "nombre       : $(svc_field "$_id" 3)"
      echo "bloquea      : $(svc_field "$_id" 4)"
      echo "confianza    : $(svc_field "$_id" 5)"
      echo "modos        : $(svc_field "$_id" 6)"
      echo "modo actual  : $(svc_current_mode "$_id")"
      echo "descripcion  : $(svc_field "$_id" 8)"
      svc_check_allowlist_conflict "$_id" ;;
    set)
      _id="$1"; _mode="$2"
      svc_exists "$_id" || { echo "ERROR: control desconocido: '$_id'" >&2; return 1; }
      _support=$(svc_field "$_id" 6)
      printf '%s' ",$_support," | grep -q ",$_mode," || { echo "ERROR: modo invalido '$_mode'. Validos: $_support" >&2; return 1; }
      case "$_mode" in
        normal) svc_set_state "$_id" normal 0 "" ; echo "OK: '$_id' en modo normal (sin bloquear)." ;;
        15m) svc_set_state "$_id" 15m "$(( $(sec_now) + 900 ))" "" ;;
        1h)  svc_set_state "$_id" 1h "$(( $(sec_now) + 3600 ))" "" ;;
        boot) svc_set_state "$_id" boot boot "$(sec_bootid)" ;;
        perm) svc_set_state "$_id" perm always "" ;;
      esac
      if [ "$_mode" != "normal" ]; then
        echo "Control experimental de mejor esfuerzo. DNSCrypt Manager no puede garantizar que YouTube no utilice otros dominios o endpoints para registrar actividad."
        echo "Puede afectar: historial, recomendaciones, algoritmo, progreso y sincronizacion."
        svc_check_allowlist_conflict "$_id"
      fi
      cat_compile >/dev/null 2>&1
      echo "OK: '$_id' -> $_mode (recompilado)." ;;
    conflicts)
      _any=0
      awk -F'\t' '!/^#/ {print $1}' "$SVC_INDEX" 2>/dev/null | while IFS= read -r _id; do
        svc_is_blocking "$_id" || continue
        svc_check_allowlist_conflict "$_id"
      done ;;
    *) echo "Uso: dnscrypt-manager service {list [--json]|info <id>|status <id>|set <id> <normal|15m|1h|boot|perm>|conflicts|sync}" >&2; return 1 ;;
  esac
}
