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
#  18 last_verified 19 description_es 20 source_name 21 source_group
#  22 source_subgroup 23 source_packs 24 source_formats 25 source_urls
#  26 source_url_count 27 activation_blocked
##############################################################################

CAT_DIR="$DATA_DIR/catalog"
CAT_INDEX="$CAT_DIR/blocklists.index.tsv"
CAT_ENABLED="$CAT_DIR/enabled.txt"
CAT_CUSTOM="$CAT_DIR/custom.tsv"
CAT_CACHE_DIR="$CAT_DIR/cache"
CAT_BLACKLIST="$CAT_DIR/blacklist.txt"
SRCST="$CAT_DIR/source-status.tsv"   # estado runtime persistente (separado del catalogo)
CAT_SUCCESS="$CAT_DIR/source-success.tsv" # ultimo artefacto validado por fuente
CAT_MANIFEST="$CAT_DIR/blocklists-manifest.json"
CAT_PROVENANCE="$CAT_DIR/source-provenance.tsv"
CAT_COMPILE_LOCK="$RUN_DIR/catalog.compile.lock"        # lock DIR (mkdir atomico)
CAT_COMPILE_PROGRESS="$RUN_DIR/catalog.compile.progress" # estado consultable
: "${CAT_COMPILE_TIMEOUT_DEFAULT:=900}"                    # 15 min tope seguro (override por env)
CAT_STATS="$CAT_DIR/contribution-stats.tsv"             # aporte unico (runtime, separado)
: "${CAT_MIN_FREE_KB:=524288}"  # ~512 MiB libres para staging/rollback a escala (override por env)
: "${CAT_MAX_SOURCE_BYTES:=268435456}" # 256 MiB por fuente descargada (override por env)
: "${CAT_MIN_SOURCE_BYTES:=32}"
: "${CAT_MAX_SOURCE_DOMAINS:=5000000}"
: "${CAT_MAX_ACTIVE_DOMAINS:=5000000}" # limite del conjunto deduplicado del catalogo activo
: "${CAT_MAX_ACTIVE_SOURCE_ENTRIES:=10000000}" # incluye duplicados; acota procesamiento y almacenamiento
: "${CAT_MAX_ACTIVE_SOURCE_BYTES:=1073741824}" # 1 GiB entre cachés activas del catálogo
: "${CAT_MIN_RETENTION_PCT:=50}" # rechaza caidas bruscas contra la ultima cache valida
: "${CAT_DOWNLOAD_RESERVE_KB:=524288}" # conserva 512 MiB libres mientras prepara las cachés
: "${CAT_DOWNLOAD_JOBS:=4}" # máximo de descargas concurrentes; el worker reduce esto según el espacio disponible

CAT_DOWNLOAD_LOCK="$CAT_DIR/download-all.lock"
CAT_DOWNLOAD_STATUS="$CAT_DIR/download-all.status"
CAT_DOWNLOAD_LOG="$CAT_DIR/download-all.log"

cat_lib_loaded() { return 0; }

cat_init_dirs() {
  mkdir -p "$CAT_CACHE_DIR" 2>/dev/null
  chmod 0700 "$CAT_DIR" 2>/dev/null
  [ -f "$CAT_ENABLED" ] || : > "$CAT_ENABLED"
  [ -f "$CAT_CUSTOM" ] || : > "$CAT_CUSTOM"
  [ -f "$CAT_BLACKLIST" ] || : > "$CAT_BLACKLIST"
  [ -f "$SRCST" ] || : > "$SRCST"
  [ -f "$CAT_SUCCESS" ] || : > "$CAT_SUCCESS"
  chmod 0600 "$CAT_ENABLED" "$CAT_CUSTOM" "$CAT_BLACKLIST" "$SRCST" "$CAT_SUCCESS" 2>/dev/null
  return 0
}
cat_init_dirs

# Metadatos locales del módulo, NO listas descargadas ni preferencias. Esta
# sincronización es independiente del schema: una actualización puede cambiar
# el catálogo sin cambiar el formato de los datos del usuario.
# Staging en el MISMO directorio + rename: lectores concurrentes ven siempre
# el índice anterior completo o el nuevo completo, nunca una copia a medias.
cat_sync_index() (
  _cat_src="$MODDIR/config/catalog/blocklists.index.tsv"
  if [ ! -f "$_cat_src" ] || [ ! -r "$_cat_src" ] || [ ! -s "$_cat_src" ]; then
    echo "ERROR: falta el índice de catálogo incluido en el módulo: $_cat_src" >&2
    return 1
  fi
  if [ -f "$CAT_INDEX" ] && [ -r "$CAT_INDEX" ] && cmp -s "$_cat_src" "$CAT_INDEX" 2>/dev/null; then
    return 0
  fi
  _cat_tmp=$(mktemp "$CAT_DIR/.blocklists.index.XXXXXX") || {
    echo "ERROR: no se pudo preparar el índice de catálogo en $CAT_DIR" >&2; return 1;
  }
  trap 'rm -f "$_cat_tmp"' 0
  trap 'exit 1' HUP INT TERM
  if ! cp "$_cat_src" "$_cat_tmp" || ! chmod 0600 "$_cat_tmp" || ! cmp -s "$_cat_src" "$_cat_tmp"; then
    echo "ERROR: no se pudo copiar el índice de catálogo; se conserva el anterior." >&2
    return 1
  fi
  if ! awk -F '\t' '!/^#/ && NF {
      if (NF!=27 || $1 !~ /^[a-z0-9][a-z0-9_-]*$/ || seen[$1]++) bad=1
      count++
    } END { exit (bad || count==0) }' "$_cat_tmp"; then
    echo "ERROR: índice de catálogo inválido; se conserva el anterior." >&2
    return 1
  fi
  if ! mv -f "$_cat_tmp" "$CAT_INDEX"; then
    echo "ERROR: no se pudo reemplazar el índice de catálogo; se conserva el anterior." >&2
    return 1
  fi
  return 0
)

# Autorreparación al consultar: también funciona antes de migrate/primer boot,
# o si una instalación schema 3 perdió solo este archivo de metadatos.
cat_ensure_index() {
  [ -f "$CAT_INDEX" ] && [ -r "$CAT_INDEX" ] && [ -s "$CAT_INDEX" ] && return 0
  cat_sync_index
}

# ---------------------------------------------------------------------------
# Lectura del index (index del modulo + custom del usuario)
# ---------------------------------------------------------------------------
# Imprime la fila completa (TSV) de un id, buscando primero en custom.
cat_row() {
  cat_ensure_index || return 1
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
cat_upstream_status() { cat_field "$1" 10; }
cat_runtime_status() { srcst_status "$1"; }

# Lista todos los ids (custom primero, luego catalogo), sin duplicar.
cat_all_ids() {
  cat_ensure_index || return 1
  {
    awk -F'\t' 'NF>=1 && $1!="" {print $1}' "$CAT_CUSTOM" 2>/dev/null
    awk -F'\t' '!/^#/ && NF>=1 && $1!="" {print $1}' "$CAT_INDEX" 2>/dev/null
  } | awk '!seen[$0]++'
}

# Resumen pequeño del catalogo para la WebUI. La pantalla de Listas no necesita
# recibir las fichas completas para dibujar los acordeones: primero pide solo
# estos contadores y luego solicita una categoria cuando el usuario la abre.
# Esto evita truncamientos del stdout de ksu.exec en Android.
cat_groups_output() {
  cat_ensure_index || return 1
  awk -F '\t' \
    -v custom_file="$CAT_CUSTOM" -v index_file="$CAT_INDEX" \
    -v enabled_file="$CAT_ENABLED" '
    BEGIN {
      order[1]="Security"; order[2]="Privacy"; order[3]="ParentalControl"
      order[4]="dcm"; order[5]="rethink_unassigned"
    }
    function add(    g) {
      if ($1=="" || seen[$1]++) return
      if ($20=="") g="dcm"
      else if ($21=="") g="rethink_unassigned"
      else g=$21
      count[g]++
      if ($1 in active) active_count[g]++
    }
    FILENAME == enabled_file { if ($1!="") active[$1]=1; next }
    /^#/ { next }
    NF < 1 || $1 == "" { next }
    FILENAME == custom_file { add(); next }
    FILENAME == index_file { add(); next }
    END {
      printf "{\"groups\":["
      for (i=1; i<=5; i++) {
        g=order[i]
        if (i>1) printf ","
        printf "{\"key\":\"%s\",\"count\":%d,\"active\":%d}", g, count[g]+0, active_count[g]+0
      }
      print "]}"
    }
  ' "$CAT_ENABLED" "$CAT_CUSTOM" "$CAT_INDEX"
}

# La WebUI pide todo el catálogo como JSON. Leer cada fila mediante cat_field,
# srcst_field y cat_success_field lanzaba cientos de procesos en el teléfono.
# Esta ruta hace una sola pasada por los índices y carga los estados runtime en
# memoria dentro de awk, preservando los campos JSON y filtros de la CLI.
cat_list_output() {
  cat_ensure_index || return 1
  awk -F '\t' \
    -v custom_file="$CAT_CUSTOM" -v index_file="$CAT_INDEX" \
    -v enabled_file="$CAT_ENABLED" -v status_file="$SRCST" -v success_file="$CAT_SUCCESS" \
    -v filter_cat="$1" -v filter_maint="$(printf '%s' "$2" | tr 'A-Z' 'a-z')" \
    -v only_enabled="$3" -v only_recommended="$4" -v only_archived="$5" \
    -v search="$(printf '%s' "$6" | tr 'A-Z' 'a-z')" -v output="$7" \
    -v group_filter="$8" '
    function j(s, out, i, c) {
      out = ""
      for (i = 1; i <= length(s); i++) {
        c = substr(s, i, 1)
        if (c == "\\") out = out "\\\\"
        else if (c == "\"") out = out "\\\""
        else if (c == "\t") out = out "\\t"
        else if (c == "\r") out = out "\\r"
        else if (c == "\n") out = out "\\n"
        else out = out c
      }
      return out
    }
    function num(v, fallback) { return (v ~ /^[0-9]+$/) ? v : fallback }
    function emit(    id, name, maint, cats, agg, fmt, lic, upstream, recommended,
                      mobile, archived, desc, source_name, source_group, subgroup,
                      packs, formats, urls, url_count, act_blocked, enabled,
                      license_blocked, runtime, domains, last_success, sha, bytes,
                      hay, catlist, group_key) {
      id=$1; name=$3; maint=$4; cats=$5; agg=$6; fmt=$7; lic=$9; upstream=$10
      recommended=$11; mobile=$12; archived=$13; desc=$19
      source_name=$20; source_group=$21; subgroup=$22
      if (source_name=="") group_key="dcm"
      else if (source_group=="") group_key="rethink_unassigned"
      else group_key=source_group
      packs=$23; gsub(/,/, "|", packs)
      formats=$24; gsub(/,/, "|", formats)
      urls=$25; gsub(/,/, "|", urls)
      url_count=num($26, "0")
      act_blocked=($27=="1" || $27=="true" || $27=="yes")
      enabled=(id in active)
      all_count++
      if (enabled) active_count++
      # La licencia se muestra como metadata, pero no bloquea el opt-in manual.
      # El contenido no se empaqueta; se descarga del upstream cuando el usuario aplica.
      license_blocked=0
      runtime=(id in status) && status[id]!="" ? status[id] : "never_checked"
      domains=(id in success) && success[id,7]!="" ? success[id,7] : ((id in status) && status[id,9]!="" ? status[id,9] : "-")
      last_success=(id in success) && success[id,9]!="" ? success[id,9] : ((id in status) && status[id,4]!="" ? status[id,4] : "0")
      sha=(id in success) ? success[id,4] : ""
      bytes=(id in success) ? num(success[id,5], "0") : "0"

      if (only_enabled && !enabled) return
      if (only_recommended && recommended!="1") return
      if (only_archived && archived!="1") return
      if (group_filter!="" && group_key!=group_filter) return
      if (filter_cat!="" && index("," cats ",", "," filter_cat ",")==0) return
      if (filter_maint!="" && index(tolower(maint), filter_maint)==0) return
      hay=tolower(id " " name " " desc " " cats)
      if (search!="" && index(hay, search)==0) return

      if (output == "text") {
        printf "  [%s] %-34s %-12s %-9s %s/%s dom=%-8s %s%s\n", \
          (enabled ? "si" : "no"), id, maint, agg, upstream, runtime, domains, \
          (recommended=="1" ? "(recomendada) " : ""), (archived=="1" ? "(ARCHIVADA) " : "")
        return
      }
      if (!first) printf ","
      first=0
      printf "{\"id\":\"%s\",\"name\":\"%s\",\"source_name\":\"%s\",\"source_group\":\"%s\",\"source_subgroup\":\"%s\",\"source_packs\":\"%s\",\"source_formats\":\"%s\",\"source_urls\":\"%s\",\"source_url_count\":%s,\"activation_blocked\":%s,\"maintainer\":\"%s\",\"categories\":\"%s\",\"aggressiveness\":\"%s\",\"format\":\"%s\",\"license\":\"%s\",\"license_blocked\":%s,\"upstream_status\":\"%s\",\"runtime_status\":\"%s\",\"mobile_suitability\":\"%s\",\"recommended\":%s,\"archived\":%s,\"enabled\":%s,\"valid_domains\":\"%s\",\"cache_domains\":\"%s\",\"last_success\":%s,\"sha256\":\"%s\",\"downloaded_bytes\":%s}", \
        j(id), j(name), j(source_name), j(source_group), j(subgroup), j(packs), j(formats), j(urls), url_count, \
        (act_blocked ? "true" : "false"), j(maint), j(cats), j(agg), j(fmt), j(lic), \
        (license_blocked ? "true" : "false"), j(upstream), j(runtime), j(mobile), \
        (recommended=="1" ? "true" : "false"), (archived=="1" ? "true" : "false"), \
        (enabled ? "true" : "false"), j(domains), j(domains), num(last_success,"0"), j(sha), bytes
    }
    BEGIN {
      first=1
      if (output == "text") print "Catalogo de listas (marca [si/no] = activa):"
      else print "{\"entries\":["
    }
    FILENAME == enabled_file { if ($1!="") active[$1]=1; next }
    FILENAME == status_file {
      if ($1!="") { status[$1]=$2; status[$1,4]=$4; status[$1,9]=$9 }
      next
    }
    FILENAME == success_file {
      if ($1!="") { success[$1]=1; success[$1,4]=$4; success[$1,5]=$5; success[$1,7]=$7; success[$1,9]=$9 }
      next
    }
    /^#/ { next }
    NF < 1 || $1 == "" { next }
    FILENAME == custom_file { if (!seen[$1]++) emit(); next }
    FILENAME == index_file { if (!seen[$1]++) emit(); next }
    END {
      if (output == "text") printf "Total: %d fuentes. Activas: %d.\n", all_count, active_count
      else print "]}"
    }
  ' "$CAT_ENABLED" "$SRCST" "$CAT_SUCCESS" "$CAT_CUSTOM" "$CAT_INDEX"
}

# ---------------------------------------------------------------------------
# Estado habilitado
# ---------------------------------------------------------------------------
cat_is_enabled() { grep -qxF "$1" "$CAT_ENABLED" 2>/dev/null; }

cat_activation_blocked() {
  case "$(cat_field "$1" 27)" in 1|true|yes) return 0 ;; esac
  return 1
}

cat_activation_check() {
  _id="$1"
  if cat_activation_blocked "$_id"; then
    echo "ERROR ($_id): fuente compuesta o sin transporte/formato compatible; requiere revisión antes de activarse." >&2
    return 1
  fi
  return 0
}

cat_enable() {
  cat_activation_check "$1" || return 1
  cat_license_check "$1" || return 1
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

# Evita que la union del catalogo activo crezca sin limite en dispositivos
# moviles. El conteo se deduplica antes de comparar; las categorias legacy
# conservan su comportamiento y no se modifican con este limite.
cat_active_stats() {
  _raw="$RUN_DIR/catalog.active.raw.$$"; _unique="$RUN_DIR/catalog.active.unique.$$"
  : > "$_raw" || return 1
  cat_enabled_lists | while IFS= read -r _f; do [ -s "$_f" ] && cat "$_f" >> "$_raw"; done
  sort -u "$_raw" > "$_unique" || { rm -f "$_raw" "$_unique"; return 1; }
  _total=$(wc -l < "$_raw" | tr -d ' ')
  _unique_count=$(wc -l < "$_unique" | tr -d ' ')
  _bytes=$(wc -c < "$_raw" | tr -d ' ')
  rm -f "$_raw" "$_unique"
  printf '%s\t%s\t%s\n' "${_total:-0}" "${_unique_count:-0}" "${_bytes:-0}"
}

cat_active_unique_count() {
  cat_active_stats | cut -f2
}

cat_validate_active_limit() {
  case "$CAT_MAX_ACTIVE_DOMAINS" in ''|*[!0-9]*) CAT_MAX_ACTIVE_DOMAINS=5000000 ;; esac
  case "$CAT_MAX_ACTIVE_SOURCE_ENTRIES" in ''|*[!0-9]*) CAT_MAX_ACTIVE_SOURCE_ENTRIES=10000000 ;; esac
  case "$CAT_MAX_ACTIVE_SOURCE_BYTES" in ''|*[!0-9]*) CAT_MAX_ACTIVE_SOURCE_BYTES=1073741824 ;; esac
  _stats=$(cat_active_stats) || { echo "ERROR: no se pudo medir el catálogo activo." >&2; return 1; }
  _raw=$(printf '%s\n' "$_stats" | cut -f1)
  _unique=$(printf '%s\n' "$_stats" | cut -f2)
  _bytes=$(printf '%s\n' "$_stats" | cut -f3)
  if [ "$_raw" -gt "$CAT_MAX_ACTIVE_SOURCE_ENTRIES" ] 2>/dev/null; then
    echo "ERROR: las fuentes activas suman $_raw entradas normalizadas (incluye duplicados); el límite seguro es $CAT_MAX_ACTIVE_SOURCE_ENTRIES." >&2
    log_msg "[BLOCKLIST] ERROR active source entries limit exceeded ($_raw > $CAT_MAX_ACTIVE_SOURCE_ENTRIES); active list preserved"
    return 1
  fi
  if [ "$_bytes" -gt "$CAT_MAX_ACTIVE_SOURCE_BYTES" ] 2>/dev/null; then
    echo "ERROR: las cachés activas suman $_bytes bytes; el límite seguro es $CAT_MAX_ACTIVE_SOURCE_BYTES." >&2
    log_msg "[BLOCKLIST] ERROR active source bytes limit exceeded ($_bytes > $CAT_MAX_ACTIVE_SOURCE_BYTES); active list preserved"
    return 1
  fi
  if [ "$_unique" -gt "$CAT_MAX_ACTIVE_DOMAINS" ] 2>/dev/null; then
    echo "ERROR: el catálogo activo contiene $_unique dominios únicos; el límite seguro es $CAT_MAX_ACTIVE_DOMAINS. Desactiva fuentes redundantes o agresivas." >&2
    log_msg "[BLOCKLIST] ERROR active catalog limit exceeded ($_unique > $CAT_MAX_ACTIVE_DOMAINS); active list preserved"
    return 1
  fi
  return 0
}

# Orden CANONICO y estable de fuentes activas: prioridad explicita (recomendadas
# primero) y luego ID alfabetico. NO depende del orden del filesystem. El aporte
# unico por fuente depende de este orden; por eso se fija y se documenta.
cat_enabled_ordered() {
  [ -f "$CAT_ENABLED" ] || return 0
  while IFS= read -r _id; do
    [ -n "$_id" ] || continue
    _rec=$(cat_field "$_id" 11); [ "$_rec" = "1" ] && _pri=0 || _pri=1
    printf '%s\t%s\n' "$_pri" "$_id"
  done < "$CAT_ENABLED" | sort -t"$(printf '\t')" -k1,1 -k2,2 | awk -F'\t' '{print $2}'
}

# ---------------------------------------------------------------------------
# APORTE UNICO por fuente (estadisticas runtime, SEPARADAS del catalogo).
# Procesa las fuentes activas en orden canonico acumulando un conjunto "visto"
# y usa comm/sort por LOTES (nunca loops por dominio). Guarda:
#   source_id, total, internal_dups, already_present, unique, redundant_pct
# Mas un resumen: total unico y efectivo tras allowlist.
# ---------------------------------------------------------------------------
cat_stats_compute() {
  cat_init_dirs
  _seen="$RUN_DIR/stats.seen.$$"; : > "$_seen"
  _tmp="$CAT_STATS.tmp.$$"
  printf '#source_id\ttotal\tinternal_dups\talready_present\tunique\tredundant_pct\n' > "$_tmp"
  _order="$RUN_DIR/stats.order.$$"; cat_enabled_ordered > "$_order"
  while IFS= read -r _id; do
    [ -n "$_id" ] || continue
    _f="$CAT_CACHE_DIR/$_id.list"; [ -s "$_f" ] || continue
    _u="$RUN_DIR/stats.u.$$"; sort -u "$_f" > "$_u"
    _total=$(grep -cve '^[[:space:]]*$' "$_f" 2>/dev/null)
    _uin=$(wc -l < "$_u" | tr -d ' ')
    _intdup=$(( _total - _uin )); [ "$_intdup" -lt 0 ] && _intdup=0
    _already=$(comm -12 "$_u" "$_seen" 2>/dev/null | wc -l | tr -d ' ')
    _contrib=$(( _uin - _already )); [ "$_contrib" -lt 0 ] && _contrib=0
    sort -u "$_seen" "$_u" -o "$_seen"
    _pct=0; [ "$_total" -gt 0 ] 2>/dev/null && _pct=$(( (_intdup + _already) * 100 / _total ))
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$_id" "$_total" "$_intdup" "$_already" "$_contrib" "$_pct" >> "$_tmp"
    rm -f "$_u"
  done < "$_order"
  # Resumen: total unico y efectivo tras allowlist.
  _tot_uniq=$(wc -l < "$_seen" | tr -d ' ')
  _allow_hit=0
  if [ -f "$ALLOWLIST_FILE" ]; then
    _al="$RUN_DIR/stats.al.$$"; sort -u "$ALLOWLIST_FILE" > "$_al" 2>/dev/null
    _allow_hit=$(comm -12 "$_al" "$_seen" 2>/dev/null | wc -l | tr -d ' '); rm -f "$_al"
  fi
  _eff=$(( _tot_uniq - _allow_hit )); [ "$_eff" -lt 0 ] && _eff=0
  printf '#summary\ttotal_unique\t%s\tallowlisted\t%s\teffective\t%s\n' "$_tot_uniq" "$_allow_hit" "$_eff" >> "$_tmp"
  mv -f "$_tmp" "$CAT_STATS"; chmod 0600 "$CAT_STATS" 2>/dev/null
  rm -f "$_seen" "$_order"
}

cat_stats_show() {
  if [ "${1:-}" = "--compute" ] || [ ! -f "$CAT_STATS" ]; then
    echo "Calculando aporte unico (orden canonico)…" >&2
    cat_stats_compute
  fi
  [ -f "$CAT_STATS" ] || { echo "(sin estadisticas; compila o usa 'catalog stats --compute')"; return 0; }
  if [ "${1:-}" = "--json" ]; then
    printf '{"sources":['
    _first=1
    awk -F'\t' '!/^#/{print}' "$CAT_STATS" | while IFS= read -r _l; do
      [ "$_first" = 0 ] && printf ','; _first=0
      printf '{"id":"%s","total":%s,"internal_dups":%s,"already_present":%s,"unique":%s,"redundant_pct":%s}' \
        "$(printf '%s' "$_l" | cut -f1)" "$(printf '%s' "$_l" | cut -f2)" "$(printf '%s' "$_l" | cut -f3)" \
        "$(printf '%s' "$_l" | cut -f4)" "$(printf '%s' "$_l" | cut -f5)" "$(printf '%s' "$_l" | cut -f6)"
    done
    _sum=$(grep '^#summary' "$CAT_STATS" 2>/dev/null)
    printf '],"summary":{"total_unique":%s,"allowlisted":%s,"effective":%s}}\n' \
      "$(printf '%s' "$_sum" | cut -f3)" "$(printf '%s' "$_sum" | cut -f5)" "$(printf '%s' "$_sum" | cut -f7)"
  else
    echo "Aporte unico por fuente (orden canonico: recomendadas, luego id):"
    printf '  %-34s %8s %8s %9s %8s %5s\n' "fuente" "total" "int.dup" "yapresen" "unico" "red%"
    awk -F'\t' '!/^#/{printf "  %-34s %8s %8s %9s %8s %4s%%\n",$1,$2,$3,$4,$5,$6}' "$CAT_STATS"
    _sum=$(grep '^#summary' "$CAT_STATS" 2>/dev/null)
    if [ -n "$_sum" ]; then
      echo "  ----"
      echo "  total unico: $(printf '%s' "$_sum" | cut -f3) · en allowlist: $(printf '%s' "$_sum" | cut -f5) · efectivo tras allowlist: $(printf '%s' "$_sum" | cut -f7)"
    fi
    echo "  (nota: el 'aporte unico' depende del orden de compilacion; se usa un orden canonico fijo.)"
  fi
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
  # Dominios de los controles de servicio DECLARATIVOS activos (v0.3, servicectl.sh).
  command -v sc_append_active >/dev/null 2>&1 && sc_append_active "$_out" 2>/dev/null
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
# Estado RUNTIME persistente y SEPARADO del catalogo (que es inmutable).
# Archivo: $CAT_DIR/source-status.tsv  (nunca se toca el JSON/TSV generado).
# Columnas 1-indexadas:
#  1 source_id 2 runtime_status 3 last_attempt 4 last_success 5 http_status
#  6 bytes 7 sha256 8 total_source 9 valid 10 invalid 11 partial_dns
#  12 error 13 effective_url
# runtime_status: never_checked|verified|download_failed|validation_failed|stale|rollback_active
srcst_init() { [ -f "$SRCST" ] || : > "$SRCST"; chmod 0600 "$SRCST" 2>/dev/null; }
srcst_row() { awk -F'\t' -v id="$1" '$1==id {print; exit}' "$SRCST" 2>/dev/null; }
srcst_field() { srcst_row "$1" | awk -F'\t' -v n="$2" '{print $n}'; }
srcst_status() { _s=$(srcst_field "$1" 2); [ -n "$_s" ] && echo "$_s" || echo never_checked; }
srcst_last_success() { _s=$(srcst_field "$1" 4); [ -n "$_s" ] && echo "$_s" || echo 0; }
# Sanitiza un valor para el TSV (sin tabs ni saltos).
srcst_clean() { printf '%s' "$1" | tr '\t\n\r' '   ' | cut -c1-200; }
# Escribe/actualiza la fila de una fuente (upsert). Argumentos posicionales:
#  id status http bytes sha total valid invalid partial error url success(0/1)
srcst_write() {
  srcst_init
  _sid="$1"; _st="$2"; _http="$3"; _by="$4"; _sha="$5"; _tot="$6"; _val="$7"
  _inv="$8"; _par="$9"; _err="$(srcst_clean "${10}")"; _url="$(srcst_clean "${11}")"; _ok="${12}"
  _now=$(sec_now)
  _prevok=$(srcst_last_success "$_sid")
  if [ "$_ok" = "1" ]; then _ls="$_now"; else _ls="$_prevok"; fi
  _t="$SRCST.tmp.$$"
  awk -F'\t' -v id="$_sid" '$1 != id' "$SRCST" 2>/dev/null > "$_t"
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$_sid" "$_st" "$_now" "$_ls" "$_http" "$_by" "$_sha" "$_tot" "$_val" "$_inv" "$_par" "$_err" "$_url" >> "$_t"
  mv -f "$_t" "$SRCST"; chmod 0600 "$SRCST" 2>/dev/null
}
srcst_clear() {
  srcst_init; _t="$SRCST.tmp.$$"
  awk -F'\t' -v id="$1" '$1 != id' "$SRCST" 2>/dev/null > "$_t"
  mv -f "$_t" "$SRCST"; chmod 0600 "$SRCST" 2>/dev/null
}

# LICENSE_UNKNOWN es metadata informativa. Las fuentes siguen apagadas por
# defecto y solo se descargan tras una seleccion explicita del usuario.
cat_license_unknown() {
  case "$(cat_field "$1" 9)" in ''|unknown|UNKNOWN|LICENSE_UNKNOWN) return 0 ;; esac
  return 1
}

cat_license_check() {
  _id="$1"
  cat_exists "$_id" || { echo "ERROR: id desconocido en el catalogo: '$_id'" >&2; return 1; }
  return 0
}

# Descarga controlada. La URL inicial debe ser HTTPS (file:// solo en tests);
# los redirects de curl también quedan limitados a HTTPS. La respuesta nunca se
# ejecuta y solo llega a una ruta temporal bajo RUN_DIR.
cat_fetch_raw() {
  _url="$1"; _dst="$2"
  case "$CAT_MAX_SOURCE_BYTES" in ''|*[!0-9]*) CAT_MAX_SOURCE_BYTES=268435456 ;; esac
  _fetch_cap=$((CAT_MAX_SOURCE_BYTES + 1))
  CAT_FETCH_HTTP="-"
  case "$_url" in
    file://*)
      [ "${DNSCRYPT_TEST_MODE:-0}" = "1" ] || return 1
      CAT_FETCH_HTTP=local
      sec_download "$_url" "$_dst"
      return $? ;;
    https://*) : ;;
    *) return 1 ;;
  esac
  # Hook determinista para fixtures: enumera código HTTP/RC y copia solo datos.
  if [ "${DNSCRYPT_TEST_MODE:-0}" = "1" ] && [ -n "${DNSCRYPT_TEST_CAT_BODY_FILE:-}" ]; then
    CAT_FETCH_HTTP="${DNSCRYPT_TEST_CAT_HTTP:-200}"
    _rc="${DNSCRYPT_TEST_CAT_RC:-0}"
    case "$_rc" in ''|*[!0-9]*) _rc=1 ;; esac
    case "$CAT_FETCH_HTTP" in 2[0-9][0-9]) : ;; *) return 1 ;; esac
    # Simula fuentes lentas y mide solapamiento en la suite; esta rama solo
    # existe con TEST_MODE y nunca se incluye en una ruta de producción.
    if [ -n "${DNSCRYPT_TEST_CAT_CONCURRENCY_FILE:-}" ]; then
      _tc="$DNSCRYPT_TEST_CAT_CONCURRENCY_FILE"; _tl="$_tc.lock"
      while ! mkdir "$_tl" 2>/dev/null; do sleep 0.01; done
      _ta=$(cat "$_tc.active" 2>/dev/null); case "$_ta" in ''|*[!0-9]*) _ta=0 ;; esac
      _ta=$((_ta + 1)); printf '%s\n' "$_ta" > "$_tc.active"
      _tm=$(cat "$_tc.max" 2>/dev/null); case "$_tm" in ''|*[!0-9]*) _tm=0 ;; esac
      [ "$_ta" -le "$_tm" ] || printf '%s\n' "$_ta" > "$_tc.max"
      rmdir "$_tl" 2>/dev/null
      _td="${DNSCRYPT_TEST_CAT_DELAY:-1}"
      case "$_td" in ''|*[!0-9]*) _td=1 ;; esac
      sleep "$_td"
    fi
    [ "$_rc" = "0" ] || return 1
    cp -f "$DNSCRYPT_TEST_CAT_BODY_FILE" "$_dst" 2>/dev/null || return 1
    if [ -n "${DNSCRYPT_TEST_CAT_CONCURRENCY_FILE:-}" ]; then
      _tc="$DNSCRYPT_TEST_CAT_CONCURRENCY_FILE"; _tl="$_tc.lock"
      while ! mkdir "$_tl" 2>/dev/null; do sleep 0.01; done
      _ta=$(cat "$_tc.active" 2>/dev/null); case "$_ta" in ''|*[!0-9]*) _ta=1 ;; esac
      _ta=$((_ta - 1)); [ "$_ta" -ge 0 ] || _ta=0
      printf '%s\n' "$_ta" > "$_tc.active"; rmdir "$_tl" 2>/dev/null
    fi
    [ -s "$_dst" ]
    return $?
  fi
  _fetch_tag="${CAT_FETCH_TOKEN:-$$}"
  if have curl; then
    _headers="$RUN_DIR/cat.fetch.headers.$_fetch_tag"; _status="$RUN_DIR/cat.fetch.status.$_fetch_tag"
    rm -f "$_headers" "$_status" 2>/dev/null
    (
      curl -sSL --proto '=https' --proto-redir '=https' \
        --connect-timeout 15 --max-time 90 -D "$_headers" "$_url"
      printf '%s\n' "$?" > "$_status"
    ) | head -c "$_fetch_cap" > "$_dst"
    _rc=$(cat "$_status" 2>/dev/null)
    _http=$(awk '$1 ~ /^HTTP\// && $2 ~ /^[0-9][0-9][0-9]$/ {code=$2} END {print code}' "$_headers" 2>/dev/null)
    CAT_FETCH_HTTP="${_http:-000}"
    _sz=$(wc -c < "$_dst" 2>/dev/null | tr -d ' ')
    rm -f "$_headers" "$_status" 2>/dev/null
    case "$CAT_FETCH_HTTP" in
      2[0-9][0-9])
        # head limita el archivo en streaming incluso con curl anterior a 8.4,
        # donde --max-filesize no cubria respuestas sin Content-Length.
        if [ "${_sz:-0}" -gt "$CAT_MAX_SOURCE_BYTES" ] 2>/dev/null; then return 0; fi
        [ "${_rc:-1}" = "0" ] && [ -s "$_dst" ]; return $? ;;
    esac
    rm -f "$_dst" 2>/dev/null
    return 1
  elif have wget; then
    _wget_help=$(wget --help 2>&1)
    if ! printf '%s\n' "$_wget_help" | grep -q -- '--max-redirect' \
      || ! printf '%s\n' "$_wget_help" | grep -q -- '--server-response'; then
      CAT_FETCH_HTTP=unknown
      echo "ERROR: wget no permite limitar redirecciones; hace falta curl o GNU Wget compatible." >&2
      return 1
    fi
    _headers="$RUN_DIR/cat.fetch.headers.$_fetch_tag"; _status="$RUN_DIR/cat.fetch.status.$_fetch_tag"
    rm -f "$_headers" "$_status" 2>/dev/null
    (
      wget --max-redirect=0 --server-response -T 90 -O - "$_url" 2> "$_headers"
      printf '%s\n' "$?" > "$_status"
    ) | head -c "$_fetch_cap" > "$_dst"
    _rc=$(cat "$_status" 2>/dev/null)
    _http=$(awk '$1 ~ /^HTTP\// && $2 ~ /^[0-9][0-9][0-9]$/ {code=$2} END {print code}' "$_headers" 2>/dev/null)
    CAT_FETCH_HTTP="${_http:-unknown}"
    _sz=$(wc -c < "$_dst" 2>/dev/null | tr -d ' ')
    rm -f "$_headers" "$_status" 2>/dev/null
    case "$CAT_FETCH_HTTP" in
      2[0-9][0-9])
        if [ "${_sz:-0}" -gt "$CAT_MAX_SOURCE_BYTES" ] 2>/dev/null; then return 0; fi
        [ "${_rc:-1}" = "0" ] && [ -s "$_dst" ]; return $? ;;
    esac
    rm -f "$_dst" 2>/dev/null
    return 1
  fi
  echo "ERROR: ni curl ni wget disponibles para descargar" >&2
  return 1
}

# Devuelve empty|html|json|text según el primer contenido no comentado.
cat_payload_type() {
  _file="$1"
  awk '
    /^[[:space:]]*$/ { next }
    /^[[:space:]]*[#!;]/ { next }
    {
      s=tolower($0); sub(/^[[:space:]]+/, "", s)
      if (s ~ /^<!doctype[[:space:]]+html/ || s ~ /^<html/ || s ~ /^<head/ || s ~ /^<body/ || s ~ /^<title/) print "html"
      else if (s ~ /^\{/ || s ~ /^\[/) print "json"
      else if (s ~ /cloudflare ray id|cf-browser-verification|enable javascript and cookies|access denied/) print "html"
      else print "text"
      exit
    }
    END { if (NR == 0) print "empty" }
  ' "$_file" 2>/dev/null
}

cat_success_row() { awk -F'\t' -v id="$1" '$1==id {print; exit}' "$CAT_SUCCESS" 2>/dev/null; }
cat_success_field() { cat_success_row "$1" | awk -F'\t' -v n="$2" '{print $n}'; }

# source-success.tsv: id, URL, hash crudo, hash normalizado, bytes, reglas
# crudas, dominios validos, ignorados, timestamp de exito, revision o '-'.
cat_success_write() (
  _id="$1"; _url="$(srcst_clean "$2")"; _raw="$3"; _norm="$4"; _bytes="$5"
  _total="$6"; _valid="$7"; _invalid="$8"; _when="$9"; _revision="${10:--}"
  _t="$CAT_SUCCESS.tmp.$$"
  awk -F'\t' -v id="$_id" '$1 != id' "$CAT_SUCCESS" 2>/dev/null > "$_t"
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$_id" "$_url" "$_raw" "$_norm" "$_bytes" "$_total" "$_valid" "$_invalid" "$_when" "$_revision" >> "$_t"
  mv -f "$_t" "$CAT_SUCCESS" && chmod 0600 "$CAT_SUCCESS" 2>/dev/null
)

cat_success_clear() {
  _t="$CAT_SUCCESS.tmp.$$"
  awk -F'\t' -v id="$1" '$1 != id' "$CAT_SUCCESS" 2>/dev/null > "$_t"
  mv -f "$_t" "$CAT_SUCCESS" && chmod 0600 "$CAT_SUCCESS" 2>/dev/null
}

# Artefacto runtime: hashes upstream/normalizado, conteos, URL y snapshot de
# fuentes activas. Se reemplaza atómicamente y nunca contiene consultas DNS.
cat_manifest_generate() (
  cat_init_dirs
  if [ "${DNSCRYPT_TEST_MODE:-0}" = "1" ] && [ -n "${DNSCRYPT_TEST_CAT_MANIFEST_COUNTER:-}" ]; then
    printf 'rebuild\n' >> "$DNSCRYPT_TEST_CAT_MANIFEST_COUNTER"
  fi
  _tmp="$CAT_MANIFEST.tmp.$$"
  _now=$(sec_now)
  printf '{"schema":1,"generated_at":%s,"active_sources":[' "$_now" > "$_tmp" || return 1
  _first=1
  if [ -s "$CAT_ENABLED" ]; then
    while IFS= read -r _id; do
      [ -n "$_id" ] || continue
      [ "$_first" = 1 ] || printf ',' >> "$_tmp"
      _first=0
      printf '"%s"' "$(cat_json_escape "$_id")" >> "$_tmp"
    done < "$CAT_ENABLED"
  fi
  printf '],"sources":[' >> "$_tmp"
  _first=1
  if [ -s "$CAT_SUCCESS" ]; then
    while IFS="$(printf '\t')" read -r _id _url _raw _list _bytes _total _valid _invalid _when _rev; do
      [ -n "$_id" ] || continue
      [ "$_first" = 1 ] || printf ',' >> "$_tmp"
      _first=0
      _cats=$(cat_field "$_id" 5)
      _license=$(cat_field "$_id" 9)
      _runtime=$(srcst_status "$_id")
      _cached="$CAT_CACHE_DIR/$_id.list"
      _cache_count=0; [ -f "$_cached" ] && _cache_count=$(wc -l < "$_cached" | tr -d ' ')
      [ -n "$_rev" ] && [ "$_rev" != "-" ] && _rev_json="\"$(cat_json_escape "$_rev")\"" || _rev_json=null
      printf '{"id":"%s","url":"%s","categories":"%s","license":"%s","status":"%s","rules_downloaded":%s,"valid_domains":%s,"cached_domains":%s,"invalid_entries":%s,"downloaded_bytes":%s,"raw_sha256":"%s","normalized_sha256":"%s","last_success":%s,"revision":%s}' \
        "$(cat_json_escape "$_id")" "$(cat_json_escape "$_url")" "$(cat_json_escape "$_cats")" \
        "$(cat_json_escape "$_license")" "$_runtime" "${_total:-0}" "${_valid:-0}" "${_cache_count:-0}" \
        "${_invalid:-0}" "${_bytes:-0}" "$_raw" "$_list" "${_when:-0}" "$_rev_json" >> "$_tmp"
    done < "$CAT_SUCCESS"
  fi
  _blocked_count=0; _blocked_bytes=0; _blocked_sha=""
  [ -f "$BL_BLOCKED" ] && { _blocked_count=$(wc -l < "$BL_BLOCKED" | tr -d ' '); _blocked_bytes=$(wc -c < "$BL_BLOCKED" | tr -d ' '); _blocked_sha=$(sec_sha256 "$BL_BLOCKED"); }
  _prov_sha=""; [ -f "$CAT_PROVENANCE" ] && _prov_sha=$(sec_sha256 "$CAT_PROVENANCE")
  printf '],"compiled":{"domains":%s,"bytes":%s,"sha256":"%s","provenance_sha256":"%s"}}\n' \
    "${_blocked_count:-0}" "${_blocked_bytes:-0}" "$_blocked_sha" "$_prov_sha" >> "$_tmp"
  mv -f "$_tmp" "$CAT_MANIFEST" || { rm -f "$_tmp"; return 1; }
  chmod 0600 "$CAT_MANIFEST" 2>/dev/null
)

# Mapa auditable de cada dominio de una fuente activa a su id y clasificación
# local. Un dominio presente en varias fuentes conserva una fila por fuente.
cat_provenance_generate() {
  _raw="$CAT_PROVENANCE.raw.$$"; _sorted="$CAT_PROVENANCE.sorted.$$"
  : > "$_raw"
  while IFS= read -r _id; do
    [ -n "$_id" ] || continue
    _list="$CAT_CACHE_DIR/$_id.list"; [ -s "$_list" ] || continue
    _cats=$(cat_field "$_id" 5)
    awk -v id="$_id" -v cats="$_cats" 'NF==1 {print $1 "\t" id "\t" cats}' "$_list" >> "$_raw" || {
      rm -f "$_raw" "$_sorted"; return 1;
    }
  done < "$CAT_ENABLED"
  sort -u -t "$(printf '\t')" -k1,1 -k2,2 -k3,3 "$_raw" > "$_sorted" || {
    rm -f "$_raw" "$_sorted"; return 1;
  }
  mv -f "$_sorted" "$CAT_PROVENANCE" || { rm -f "$_raw" "$_sorted"; return 1; }
  rm -f "$_raw"
  chmod 0600 "$CAT_PROVENANCE" 2>/dev/null
}

cat_update_one() {
  _id="$1"
  if [ "${CAT_DOWNLOAD_ALL_WORKER:-0}" != "1" ] && cat_download_all_running; then
    echo "ERROR ($_id): hay una descarga global del catálogo en curso; reintentá al finalizar." >&2
    return 1
  fi
  cat_exists "$_id" || { echo "ERROR: id desconocido en el catalogo: '$_id'" >&2; return 1; }
  cat_activation_check "$_id" || return 1
  cat_license_check "$_id" || return 1
  # Fuentes marcadas broken/archived NO se descargan (evita reintentar un 404
  # permanente como si fuera temporal). Se conserva la ultima copia valida.
  _decl=$(cat_field "$_id" 10)
  case "$_decl" in
    broken|archived)
      srcst_write "$_id" download_failed "-" 0 "" 0 0 0 0 "fuente $_decl: no se descarga (broken/archived)" "$(cat_field "$_id" 8)" 0
      echo "OMITIDA ($_id): fuente $_decl; no se descarga. Se conserva la ultima copia valida si existe." >&2
      return 1 ;;
  esac
  _url=$(cat_field "$_id" 8)
  _fmt=$(cat_field "$_id" 7)
  case "$_url" in https://*|file://*) : ;; *) echo "ERROR ($_id): url invalida" >&2; return 1 ;; esac

  _raw="$RUN_DIR/cat.$_id.raw.$$"
  _norm="$RUN_DIR/cat.$_id.norm.$$"
  # 1-2) descarga (reusa sec_download: file:// solo en TEST_MODE) + HTTP.
  # NO se toca cache/<id>.list salvo exito: una descarga fallida conserva la
  # ultima fuente valida.
  if [ "${CAT_PREFETCH_ATTEMPTED:-0}" = "1" ]; then
    _raw="${CAT_PREFETCH_RAW:-}"
    _http="${CAT_PREFETCH_HTTP:-unknown}"
    _fetch_ok="${CAT_PREFETCH_OK:-0}"
  else
    _raw="$RUN_DIR/cat.$_id.raw.$$"
    if cat_fetch_raw "$_url" "$_raw"; then _fetch_ok=1; else _fetch_ok=0; fi
    _http="${CAT_FETCH_HTTP:--}"
  fi
  if [ "$_fetch_ok" != "1" ] || [ ! -s "$_raw" ]; then
    srcst_write "$_id" download_failed "$_http" 0 "" 0 0 0 0 "HTTP $_http o descarga fallida" "$_url" 0
    log_msg "[BLOCKLIST] ERROR source returned HTTP $_http; keeping previous valid copy ($_id)"
    echo "ERROR ($_id): HTTP $_http o descarga fallida; se conserva la cache valida anterior." >&2
    rm -f "$_raw"; return 1
  fi
  _http="${CAT_FETCH_HTTP:--}"
  # 3) tamano
  _sz=$(wc -c < "$_raw" 2>/dev/null | tr -d ' ')
  if ! { [ "$_sz" -ge "$CAT_MIN_SOURCE_BYTES" ] 2>/dev/null && [ "$_sz" -le "$CAT_MAX_SOURCE_BYTES" ] 2>/dev/null; }; then
    srcst_write "$_id" validation_failed "$_http" "$_sz" "" 0 0 0 0 "tamano fuera de rango" "$_url" 0
    echo "ERROR ($_id): tamano fuera de rango ($_sz bytes)" >&2; rm -f "$_raw"; return 1
  fi
  # 4) tipo (texto)
  if command -v sec_is_binary >/dev/null 2>&1 && sec_is_binary "$_raw"; then
    srcst_write "$_id" validation_failed "$_http" "$_sz" "" 0 0 0 0 "contenido binario" "$_url" 0
    echo "ERROR ($_id): contenido binario" >&2; rm -f "$_raw"; return 1
  fi
  _payload=$(cat_payload_type "$_raw")
  case "$_payload" in
    html|json|empty)
      srcst_write "$_id" validation_failed "$_http" "$_sz" "" 0 0 0 0 "contenido $_payload inesperado" "$_url" 0
      log_msg "[BLOCKLIST] ERROR unexpected $_payload response ($_id); keeping previous valid copy"
      echo "ERROR ($_id): contenido $_payload inesperado; se conserva la cache valida anterior." >&2
      rm -f "$_raw"; return 1 ;;
  esac
  _sha=$(sec_sha256 "$_raw")
  _total=$(grep -cve '^[[:space:]]*$' "$_raw" 2>/dev/null)
  # 5) formato: si es 'auto' o vacio, detectar
  case "$_fmt" in ''|auto) _fmt=$(cat_detect_format "$_raw") ;; esac
  case "$_fmt" in hosts|domains|abp) : ;; *)
    srcst_write "$_id" validation_failed "$_http" "$_sz" "$_sha" "$_total" 0 "$_total" 0 "formato no soportado" "$_url" 0
    echo "ERROR ($_id): formato no soportado; se conserva la cache valida anterior." >&2
    rm -f "$_raw"; return 1 ;;
  esac
  # 6-9) extraer + normalizar + validar + dedupe interno
  _partial=0
  if [ "$_fmt" = "abp" ]; then
    _valid=$(cat_abp_extract "$_raw" "$_norm"); _partial=1
  else
    _valid=$(sec_parse_domains "$_raw" "$_fmt" "$_norm")
  fi
  case "$_valid" in
    ''|*[!0-9]*)
      srcst_write "$_id" validation_failed "$_http" "$_sz" "$_sha" "$_total" 0 0 "$_partial" "parseo fallo" "$_url" 0
      echo "ERROR ($_id): parseo fallo" >&2; rm -f "$_raw" "$_norm"; return 1 ;;
  esac
  if [ "$_valid" -lt 1 ]; then
    srcst_write "$_id" validation_failed "$_http" "$_sz" "$_sha" "$_total" 0 "$_total" "$_partial" "0 dominios validos" "$_url" 0
    echo "ERROR ($_id): 0 dominios validos" >&2; rm -f "$_raw" "$_norm"; return 1
  fi
  case "$CAT_MAX_SOURCE_DOMAINS" in ''|*[!0-9]*) CAT_MAX_SOURCE_DOMAINS=5000000 ;; esac
  if [ "$_valid" -gt "$CAT_MAX_SOURCE_DOMAINS" ] 2>/dev/null; then
    srcst_write "$_id" validation_failed "$_http" "$_sz" "$_sha" "$_total" "$_valid" 0 "$_partial" "demasiados dominios validos" "$_url" 0
    echo "ERROR ($_id): $_valid dominios supera el maximo seguro $CAT_MAX_SOURCE_DOMAINS; se conserva la cache valida anterior." >&2
    rm -f "$_raw" "$_norm"; return 1
  fi
  # 9b) Sanity check de evolución: una fuente que cae por debajo del 50% de
  # su última caché válida necesita investigación; no se acepta en silencio.
  _cached="$CAT_CACHE_DIR/$_id.list"
  if [ -s "$_cached" ]; then
    _prev_count=$(wc -l < "$_cached" | tr -d ' ')
    case "$CAT_MIN_RETENTION_PCT" in ''|*[!0-9]*) CAT_MIN_RETENTION_PCT=50 ;; esac
    [ "$CAT_MIN_RETENTION_PCT" -le 100 ] || CAT_MIN_RETENTION_PCT=50
    if [ "$_prev_count" -ge 20 ] 2>/dev/null && [ $((_valid * 100)) -lt $((_prev_count * CAT_MIN_RETENTION_PCT)) ] 2>/dev/null; then
      srcst_write "$_id" validation_failed "$_http" "$_sz" "$_sha" "$_total" "$_valid" 0 "$_partial" "caida de conteo: $_prev_count -> $_valid" "$_url" 0
      log_msg "[BLOCKLIST] ERROR anomalous count drop ($_id): $_prev_count -> $_valid; keeping previous valid copy"
      echo "ERROR ($_id): caída anómala de dominios ($_prev_count -> $_valid); se conserva la cache valida anterior." >&2
      rm -f "$_raw" "$_norm"; return 1
    fi
  fi
  _invalid=$(( _total - _valid )); [ "$_invalid" -lt 0 ] && _invalid=0
  _shalist=$(sec_sha256 "$_norm")
  # 10) preservar cache/metadata anteriores y reemplazar la normalizada con mv
  # en el mismo filesystem. Si metadata o manifest fallan, restaurar ambas.
  _had_prev=0
  if [ -f "$_cached" ]; then
    _btmp="$CAT_CACHE_DIR/$_id.list.prev.tmp.$$"
    cp -f "$_cached" "$_btmp" && mv -f "$_btmp" "$CAT_CACHE_DIR/$_id.list.prev" || {
      rm -f "$_btmp" "$_raw" "$_norm"; echo "ERROR ($_id): no se pudo guardar rollback." >&2; return 1; }
    _had_prev=1
  fi
  _oldrow=$(cat_success_row "$_id")
  if [ -n "$_oldrow" ]; then printf '%s\n' "$_oldrow" > "$CAT_CACHE_DIR/$_id.meta.prev.tmp.$$" && mv -f "$CAT_CACHE_DIR/$_id.meta.prev.tmp.$$" "$CAT_CACHE_DIR/$_id.meta.prev"
  else rm -f "$CAT_CACHE_DIR/$_id.meta.prev"; fi
  _new="$CAT_CACHE_DIR/$_id.list.new.$$"
  cat "$_norm" > "$_new" && mv -f "$_new" "$_cached" || {
    rm -f "$_new" "$_raw" "$_norm"; echo "ERROR ($_id): no se pudo reemplazar la cache atómicamente." >&2; return 1; }
  chmod 0600 "$_cached" 2>/dev/null
  _when=$(sec_now)
  if ! cat_success_write "$_id" "$_url" "$_sha" "$_shalist" "$_sz" "$_total" "$_valid" "$_invalid" "$_when" "-"; then
    if [ "$_had_prev" = "1" ]; then
      _restore="$CAT_CACHE_DIR/$_id.list.restore.$$"
      cp -f "$CAT_CACHE_DIR/$_id.list.prev" "$_restore" \
        && mv -f "$_restore" "$_cached" \
        || { rm -f "$_restore"; log_msg "[BLOCKLIST] ERROR metadata write failed and cache restore failed ($_id)"; }
    else rm -f "$_cached"; fi
    _row_restore="$CAT_SUCCESS.restore.$$"
    awk -F'\t' -v id="$_id" '$1 != id' "$CAT_SUCCESS" 2>/dev/null > "$_row_restore"
    [ -f "$CAT_CACHE_DIR/$_id.meta.prev" ] && cat "$CAT_CACHE_DIR/$_id.meta.prev" >> "$_row_restore"
    mv -f "$_row_restore" "$CAT_SUCCESS" && chmod 0600 "$CAT_SUCCESS" 2>/dev/null \
      || { rm -f "$_row_restore"; log_msg "[BLOCKLIST] ERROR metadata rollback failed ($_id)"; }
    rm -f "$_raw" "$_norm"; echo "ERROR ($_id): no se pudo escribir metadata; cache anterior conservada." >&2; return 1
  fi
  srcst_write "$_id" verified "$_http" "$_sz" "$_shalist" "$_total" "$_valid" "$_invalid" "$_partial" "" "$_url" 1
  if [ "${CAT_DEFER_MANIFEST:-0}" != "1" ] && ! cat_manifest_generate; then
    if [ "$_had_prev" = "1" ]; then
      cp -f "$CAT_CACHE_DIR/$_id.list.prev" "$CAT_CACHE_DIR/$_id.list.restore.$$" && mv -f "$CAT_CACHE_DIR/$_id.list.restore.$$" "$_cached"
      awk -F'\t' -v id="$_id" '$1 != id' "$CAT_SUCCESS" > "$CAT_SUCCESS.restore.$$"
      [ -f "$CAT_CACHE_DIR/$_id.meta.prev" ] && cat "$CAT_CACHE_DIR/$_id.meta.prev" >> "$CAT_SUCCESS.restore.$$"
      mv -f "$CAT_SUCCESS.restore.$$" "$CAT_SUCCESS"
    else
      rm -f "$_cached"
      cat_success_clear "$_id"
    fi
    cat_manifest_generate >/dev/null 2>&1
    srcst_write "$_id" validation_failed "$_http" "$_sz" "$_sha" "$_total" "$_valid" "$_invalid" "$_partial" "metadata manifest fallo" "$_url" 0
    rm -f "$_raw" "$_norm"; echo "ERROR ($_id): no se pudo guardar manifest; se restauró la cache anterior." >&2; return 1
  fi
  rm -f "$_raw" 2>/dev/null
  log_msg "[BLOCKLIST] Updated $_id: downloaded $_sz bytes, parsed $_total rules, kept $_valid valid DNS domains, ignored $_invalid"
  if [ "$_partial" = "1" ]; then
    echo "OK ($_id): $_valid dominios (formato ABP: cobertura DNS parcial)."
  else
    echo "OK ($_id): $_valid dominios validos ($_invalid ignorados)."
  fi
  log_msg "catalog update $_id: OK ($_valid dominios, fmt=$_fmt)"
  return 0
}

# Descarga únicamente el cuerpo de una fuente para permitir I/O concurrente.
# El parseo, validación y publicación de caché siguen serializados en el worker
# padre, evitando carreras en source-success.tsv y en el manifiesto.
cat_download_fetch_worker() (
  _id="$1"; _raw="$2"; _result="$3"
  _url=$(cat_field "$_id" 8)
  # $$ se mantiene igual dentro de shells POSIX en subshells; incluir el ID
  # evita que las transferencias simultáneas compartan headers/status de curl.
  CAT_FETCH_TOKEN="download-all.$_id.$$"
  export CAT_FETCH_TOKEN
  if cat_fetch_raw "$_url" "$_raw"; then
    printf '1\t%s\n' "${CAT_FETCH_HTTP:-200}" > "$_result"
  else
    printf '0\t%s\n' "${CAT_FETCH_HTTP:-unknown}" > "$_result"
    rm -f "$_raw" 2>/dev/null
  fi
)

cat_download_parallelism() {
  case "$CAT_DOWNLOAD_JOBS" in ''|*[!0-9]*) CAT_DOWNLOAD_JOBS=4 ;; esac
  [ "$CAT_DOWNLOAD_JOBS" -ge 1 ] || CAT_DOWNLOAD_JOBS=1
  [ "$CAT_DOWNLOAD_JOBS" -le 6 ] || CAT_DOWNLOAD_JOBS=6
  case "$CAT_DOWNLOAD_RESERVE_KB" in ''|*[!0-9]*) CAT_DOWNLOAD_RESERVE_KB=524288 ;; esac
  case "$CAT_MAX_SOURCE_BYTES" in ''|*[!0-9]*) CAT_MAX_SOURCE_BYTES=268435456 ;; esac
  _free=$(cat_free_kb); case "$_free" in ''|*[!0-9]*) _free=0 ;; esac
  _budget=$((_free - CAT_DOWNLOAD_RESERVE_KB))
  _one_kb=$(((CAT_MAX_SOURCE_BYTES + 1023) / 1024))
  [ "$_one_kb" -gt 0 ] || _one_kb=1
  _by_space=$((_budget / _one_kb))
  [ "$_by_space" -ge 1 ] || _by_space=1
  [ "$CAT_DOWNLOAD_JOBS" -le "$_by_space" ] && printf '%s\n' "$CAT_DOWNLOAD_JOBS" || printf '%s\n' "$_by_space"
}

cat_download_drain_ready() {
  _active="$1"; _remain="$_active.pending.$$"
  CAT_DLW_READY_COUNT=0
  : > "$_remain" || return 1
  while IFS="$(printf '\t')" read -r _id _pid _raw _result; do
    [ -n "$_id" ] || continue
    if [ -f "$_result" ]; then
      wait "$_pid" 2>/dev/null
      _fetch_state=$(awk -F '\t' '{print $1; exit}' "$_result" 2>/dev/null)
      _fetch_http=$(awk -F '\t' '{print $2; exit}' "$_result" 2>/dev/null)
      case "$_fetch_state" in 1) _fetch_ok=1 ;; *) _fetch_ok=0 ;; esac
      [ -n "$_fetch_http" ] || _fetch_http=unknown
      CAT_PREFETCH_ATTEMPTED=1
      CAT_PREFETCH_RAW="$_raw"
      CAT_PREFETCH_HTTP="$_fetch_http"
      CAT_PREFETCH_OK="$_fetch_ok"
      if cat_update_one "$_id" >> "$CAT_DOWNLOAD_LOG" 2>&1; then
        CAT_DLW_OK=$((CAT_DLW_OK + 1))
      else
        CAT_DLW_FAILED=$((CAT_DLW_FAILED + 1))
      fi
      unset CAT_PREFETCH_ATTEMPTED CAT_PREFETCH_RAW CAT_PREFETCH_HTTP CAT_PREFETCH_OK
      rm -f "$_result" 2>/dev/null
      CAT_DLW_DONE=$((CAT_DLW_DONE + 1))
      CAT_DLW_PROCESSED=$((CAT_DLW_PROCESSED + 1))
      CAT_DLW_INFLIGHT=$((CAT_DLW_INFLIGHT - 1))
      CAT_DLW_READY_COUNT=$((CAT_DLW_READY_COUNT + 1))
      cat_download_job_write running "$CAT_DLW_JOB" "$CAT_DLW_DONE" "$CAT_DLW_TOTAL" "$CAT_DLW_OK" "$CAT_DLW_FAILED" "$CAT_DLW_SKIPPED" "validando $_id"
    else
      printf '%s\t%s\t%s\t%s\n' "$_id" "$_pid" "$_raw" "$_result" >> "$_remain"
    fi
  done < "$_active"
  mv -f "$_remain" "$_active" || { rm -f "$_remain"; return 1; }
}

# El usuario puede preparar las cachés verificadas de todas las fuentes
# compatibles sin activarlas. El estado es persistente para que la WebUI pueda
# consultar progreso solo mientras esta tarea explícita está en curso.
cat_download_job_write() {
  CAT_DJW_STATE="$1"; CAT_DJW_JOB="$2"; CAT_DJW_DONE="$3"; CAT_DJW_TOTAL="$4"; CAT_DJW_OK="$5"
  CAT_DJW_FAILED="$6"; CAT_DJW_SKIPPED="$7"; CAT_DJW_CURRENT="$8"; CAT_DJW_WHEN="$(sec_now)"
  CAT_DJW_TMP="$CAT_DOWNLOAD_STATUS.tmp.$$"
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$CAT_DJW_STATE" "$CAT_DJW_JOB" "$CAT_DJW_DONE" "$CAT_DJW_TOTAL" "$CAT_DJW_OK" "$CAT_DJW_FAILED" "$CAT_DJW_SKIPPED" "$CAT_DJW_CURRENT" "$CAT_DJW_WHEN" > "$CAT_DJW_TMP" \
    && mv -f "$CAT_DJW_TMP" "$CAT_DOWNLOAD_STATUS" || { rm -f "$CAT_DJW_TMP"; return 1; }
  chmod 0600 "$CAT_DOWNLOAD_STATUS" 2>/dev/null
}

cat_download_job_field() {
  awk -F '\t' -v n="$2" '{print $n; exit}' "$CAT_DOWNLOAD_STATUS" 2>/dev/null
}

cat_download_all_status_json() {
  if [ -d "$CAT_DOWNLOAD_LOCK" ] && ! cat_download_all_running; then
    _state=$(cat_download_job_field x 1)
    case "$_state" in queued|running)
      _job=$(cat_download_job_field x 2); _done=$(cat_download_job_field x 3)
      _total=$(cat_download_job_field x 4); _ok=$(cat_download_job_field x 5)
      _failed=$(cat_download_job_field x 6); _skipped=$(cat_download_job_field x 7)
      _current=$(cat_download_job_field x 8)
      cat_download_job_write partial "$_job" "$_done" "$_total" "$_ok" "$_failed" "$_skipped" interrumpida
      printf '[BLOCKLIST] ERROR download-all worker interrupted; previous valid copies retained.\n' >> "$CAT_DOWNLOAD_LOG"
      rm -rf "$CAT_DOWNLOAD_LOCK" 2>/dev/null ;;
    esac
  fi
  if [ ! -s "$CAT_DOWNLOAD_STATUS" ]; then
    printf '{"state":"idle","job_id":"","done":0,"total":0,"success":0,"failed":0,"skipped":0,"current":""}\n'
    return 0
  fi
  _state=$(cat_download_job_field x 1); _job=$(cat_download_job_field x 2)
  _done=$(cat_download_job_field x 3); _total=$(cat_download_job_field x 4)
  _ok=$(cat_download_job_field x 5); _failed=$(cat_download_job_field x 6)
  _skipped=$(cat_download_job_field x 7); _current=$(cat_download_job_field x 8)
  case "$_done" in ''|*[!0-9]*) _done=0 ;; esac
  case "$_total" in ''|*[!0-9]*) _total=0 ;; esac
  case "$_ok" in ''|*[!0-9]*) _ok=0 ;; esac
  case "$_failed" in ''|*[!0-9]*) _failed=0 ;; esac
  case "$_skipped" in ''|*[!0-9]*) _skipped=0 ;; esac
  printf '{"state":"%s","job_id":"%s","done":%s,"total":%s,"success":%s,"failed":%s,"skipped":%s,"current":"%s"}\n' \
    "$(cat_json_escape "$_state")" "$(cat_json_escape "$_job")" \
    "$_done" "$_total" "$_ok" "$_failed" "$_skipped" "$(cat_json_escape "$_current")"
}

cat_download_all_running() {
  [ -d "$CAT_DOWNLOAD_LOCK" ] || return 1
  _state=$(cat_download_job_field x 1)
  case "$_state" in queued)
    _when=$(cat_download_job_field x 9); _now=$(sec_now)
    case "$_when" in ''|*[!0-9]*) return 1 ;; esac
    [ $((_now - _when)) -le 120 ] 2>/dev/null && return 0
    return 1 ;;
    running)
      _pid=$(cat "$CAT_DOWNLOAD_LOCK/worker.pid" 2>/dev/null)
      case "$_pid" in ''|*[!0-9]*) return 1 ;; esac
      kill -0 "$_pid" 2>/dev/null || return 1
      if [ -r "/proc/$_pid/cmdline" ]; then
        tr '\0' ' ' < "/proc/$_pid/cmdline" 2>/dev/null | grep -q 'catalog download-all-worker' || return 1
      fi
      return 0 ;;
  esac
  return 1
}

cat_download_all_start() {
  [ "${1:-}" = "--confirmed" ] || {
    echo "Acción global. Usá: dnscrypt-manager catalog download-all --confirmed" >&2
    return 2
  }
  if cat_download_all_running; then
    echo "OK: ya hay una descarga global en curso."
    cat_download_all_status_json
    return 0
  fi
  mkdir -p "$CAT_DIR" "$RUN_DIR" 2>/dev/null || return 1
  if [ -d "$CAT_DOWNLOAD_LOCK" ]; then
    _lock_started=$(cat "$CAT_DOWNLOAD_LOCK/started" 2>/dev/null)
    _now=$(sec_now)
    case "$_lock_started" in
      ''|*[!0-9]*) echo "OK: otra acción está inicializando la descarga global."; return 0 ;;
      *)
        if [ $((_now - _lock_started)) -le 120 ] 2>/dev/null; then
          echo "OK: otra acción está inicializando la descarga global."
          cat_download_all_status_json
          return 0
        fi
        rm -rf "$CAT_DOWNLOAD_LOCK" 2>/dev/null ;;
    esac
  fi
  mkdir "$CAT_DOWNLOAD_LOCK" 2>/dev/null || {
    echo "OK: otra acción está iniciando la descarga global."
    cat_download_all_status_json
    return 0
  }
  printf '%s\n' "$(sec_now)" > "$CAT_DOWNLOAD_LOCK/started"
  _job="$(sec_now)-$$"
  cat_download_job_write queued "$_job" 0 0 0 0 0 preparando || {
    rm -rf "$CAT_DOWNLOAD_LOCK"; return 1;
  }
  if command -v nohup >/dev/null 2>&1; then
    if command -v nice >/dev/null 2>&1; then
      nohup nice -n 10 "$DCM_SELF" catalog download-all-worker "$_job" </dev/null >/dev/null 2>&1 &
    else
      nohup "$DCM_SELF" catalog download-all-worker "$_job" </dev/null >/dev/null 2>&1 &
    fi
  else
    if command -v nice >/dev/null 2>&1; then
      nice -n 10 "$DCM_SELF" catalog download-all-worker "$_job" </dev/null >/dev/null 2>&1 &
    else
      "$DCM_SELF" catalog download-all-worker "$_job" </dev/null >/dev/null 2>&1 &
    fi
  fi
  echo "OK: descarga global iniciada. Se guardan cachés verificadas; las fuentes nuevas no se activan."
  echo "ID: $_job"
  return 0
}

cat_download_all_worker() {
  CAT_DLW_JOB="${1:-}"
  case "$CAT_DLW_JOB" in ''|*[!0-9-]*) echo "ERROR: identificador de tarea inválido." >&2; return 2 ;; esac
  [ "$(cat_download_job_field x 2)" = "$CAT_DLW_JOB" ] || {
    echo "ERROR: no coincide la tarea global pendiente." >&2; return 1;
  }
  CAT_DOWNLOAD_ALL_WORKER=1
  echo "$$" > "$CAT_DOWNLOAD_LOCK/worker.pid" 2>/dev/null
  CAT_DLW_ALL="$RUN_DIR/catalog.download-all.ids.$$"
  CAT_DLW_WORK="$RUN_DIR/catalog.download-all.work.$$"
  cat_all_ids > "$CAT_DLW_ALL" || return 1
  : > "$CAT_DLW_WORK"
  if [ -s "$CAT_DOWNLOAD_LOG" ]; then
    tail -n 500 "$CAT_DOWNLOAD_LOG" > "$CAT_DOWNLOAD_LOG.trim.$$" 2>/dev/null \
      && mv -f "$CAT_DOWNLOAD_LOG.trim.$$" "$CAT_DOWNLOAD_LOG"
  else : > "$CAT_DOWNLOAD_LOG"; fi
  CAT_DLW_TOTAL=0; CAT_DLW_SKIPPED=0
  while IFS= read -r CAT_DLW_ID; do
    [ -n "$CAT_DLW_ID" ] || continue
    CAT_DLW_TOTAL=$((CAT_DLW_TOTAL + 1))
    CAT_DLW_DECL=$(cat_field "$CAT_DLW_ID" 10)
    case "$CAT_DLW_DECL" in
      broken|archived)
        CAT_DLW_SKIPPED=$((CAT_DLW_SKIPPED + 1))
        printf '[BLOCKLIST] SKIP %s: upstream=%s.\n' "$CAT_DLW_ID" "$CAT_DLW_DECL" >> "$CAT_DOWNLOAD_LOG"
        continue ;;
    esac
    if cat_activation_check "$CAT_DLW_ID" >/dev/null 2>&1; then
      case "$(cat_field "$CAT_DLW_ID" 8)" in https://*|file://*) printf '%s\n' "$CAT_DLW_ID" >> "$CAT_DLW_WORK" ;;
        *) CAT_DLW_SKIPPED=$((CAT_DLW_SKIPPED + 1)); printf '[BLOCKLIST] SKIP %s: invalid transport URL.\n' "$CAT_DLW_ID" >> "$CAT_DOWNLOAD_LOG" ;; esac
    else
      CAT_DLW_SKIPPED=$((CAT_DLW_SKIPPED + 1))
      printf '[BLOCKLIST] SKIP %s: source format or transport needs technical review.\n' "$CAT_DLW_ID" >> "$CAT_DOWNLOAD_LOG"
    fi
  done < "$CAT_DLW_ALL"
  CAT_DLW_CANDIDATES=$(wc -l < "$CAT_DLW_WORK" | tr -d ' '); case "$CAT_DLW_CANDIDATES" in ''|*[!0-9]*) CAT_DLW_CANDIDATES=0 ;; esac
  CAT_DLW_DONE="$CAT_DLW_SKIPPED"; CAT_DLW_OK=0; CAT_DLW_FAILED=0; CAT_DLW_PROCESSED=0; CAT_DLW_SPACE_SHORT=0
  CAT_DLW_JOBS=$(cat_download_parallelism)
  case "$CAT_DLW_JOBS" in ''|*[!0-9]*) CAT_DLW_JOBS=1 ;; esac
  CAT_DEFER_MANIFEST=1
  export CAT_DEFER_MANIFEST
  CAT_DLW_ACTIVE="$RUN_DIR/catalog.download-all.active.$$"
  : > "$CAT_DLW_ACTIVE"
  CAT_DLW_INFLIGHT=0
  CAT_DLW_NEXT=1
  cat_download_job_write running "$CAT_DLW_JOB" "$CAT_DLW_DONE" "$CAT_DLW_TOTAL" "$CAT_DLW_OK" "$CAT_DLW_FAILED" "$CAT_DLW_SKIPPED" preparando
  printf '[BLOCKLIST] Download-all started: %s compatible sources, %s skipped; up to %s concurrent downloads.\n' \
    "$CAT_DLW_CANDIDATES" "$CAT_DLW_SKIPPED" "$CAT_DLW_JOBS" >> "$CAT_DOWNLOAD_LOG"
  while [ "$CAT_DLW_NEXT" -le "$CAT_DLW_CANDIDATES" ] || [ "$CAT_DLW_INFLIGHT" -gt 0 ]; do
    CAT_DLW_LAUNCHED=0
    while [ "$CAT_DLW_NEXT" -le "$CAT_DLW_CANDIDATES" ] && [ "$CAT_DLW_INFLIGHT" -lt "$CAT_DLW_JOBS" ]; do
      CAT_DLW_FREE=$(cat_free_kb); case "$CAT_DLW_FREE" in ''|*[!0-9]*) CAT_DLW_FREE=0 ;; esac
      case "$CAT_DOWNLOAD_RESERVE_KB" in ''|*[!0-9]*) CAT_DOWNLOAD_RESERVE_KB=524288 ;; esac
      if [ "$CAT_DLW_FREE" -lt "$CAT_DOWNLOAD_RESERVE_KB" ] 2>/dev/null; then
        if [ "$CAT_DLW_INFLIGHT" -eq 0 ]; then
          CAT_DLW_REMAINING=$((CAT_DLW_CANDIDATES - CAT_DLW_NEXT + 1))
          CAT_DLW_SKIPPED=$((CAT_DLW_SKIPPED + CAT_DLW_REMAINING)); CAT_DLW_DONE=$((CAT_DLW_DONE + CAT_DLW_REMAINING)); CAT_DLW_SPACE_SHORT=1
          printf '[BLOCKLIST] ERROR low free space (%s KiB); skipped remaining %s source(s).\n' "$CAT_DLW_FREE" "$CAT_DLW_REMAINING" >> "$CAT_DOWNLOAD_LOG"
          cat_download_job_write running "$CAT_DLW_JOB" "$CAT_DLW_DONE" "$CAT_DLW_TOTAL" "$CAT_DLW_OK" "$CAT_DLW_FAILED" "$CAT_DLW_SKIPPED" espacio-insuficiente
          CAT_DLW_NEXT=$((CAT_DLW_CANDIDATES + 1))
        fi
        break
      fi
      CAT_DLW_ID=$(sed -n "${CAT_DLW_NEXT}p" "$CAT_DLW_WORK" 2>/dev/null)
      CAT_DLW_NEXT=$((CAT_DLW_NEXT + 1))
      [ -n "$CAT_DLW_ID" ] || continue
      CAT_DLW_RAW="$RUN_DIR/cat.download-all.$CAT_DLW_JOB.$CAT_DLW_ID.raw"
      CAT_DLW_RESULT="$RUN_DIR/cat.download-all.$CAT_DLW_JOB.$CAT_DLW_ID.result"
      rm -f "$CAT_DLW_RAW" "$CAT_DLW_RESULT" 2>/dev/null
      cat_download_fetch_worker "$CAT_DLW_ID" "$CAT_DLW_RAW" "$CAT_DLW_RESULT" </dev/null >> "$CAT_DOWNLOAD_LOG" 2>&1 &
      CAT_DLW_PID=$!
      printf '%s\t%s\t%s\t%s\n' "$CAT_DLW_ID" "$CAT_DLW_PID" "$CAT_DLW_RAW" "$CAT_DLW_RESULT" >> "$CAT_DLW_ACTIVE"
      CAT_DLW_INFLIGHT=$((CAT_DLW_INFLIGHT + 1))
      CAT_DLW_LAUNCHED=$((CAT_DLW_LAUNCHED + 1))
      cat_download_job_write running "$CAT_DLW_JOB" "$CAT_DLW_DONE" "$CAT_DLW_TOTAL" "$CAT_DLW_OK" "$CAT_DLW_FAILED" "$CAT_DLW_SKIPPED" "descargando $CAT_DLW_INFLIGHT fuente(s)"
    done
    cat_download_drain_ready "$CAT_DLW_ACTIVE" || {
      printf '[BLOCKLIST] ERROR no se pudo actualizar el estado de descargas activas.\n' >> "$CAT_DOWNLOAD_LOG"
      return 1
    }
    if [ "$CAT_DLW_READY_COUNT" -eq 0 ] && [ "$CAT_DLW_LAUNCHED" -eq 0 ]; then sleep 1; fi
  done
  rm -f "$CAT_DLW_ALL" "$CAT_DLW_WORK" "$CAT_DLW_ACTIVE"
  CAT_DEFER_MANIFEST=0
  if ! cat_manifest_generate >> "$CAT_DOWNLOAD_LOG" 2>&1; then
    CAT_DLW_FAILED=$((CAT_DLW_FAILED + 1))
    printf '[BLOCKLIST] ERROR final manifest update failed; valid per-source caches remain available.\n' >> "$CAT_DOWNLOAD_LOG"
  fi
  CAT_DLW_FINAL=done
  if [ "$CAT_DLW_FAILED" -gt 0 ] || [ "$CAT_DLW_SPACE_SHORT" = 1 ]; then CAT_DLW_FINAL=partial; fi
  cat_download_job_write "$CAT_DLW_FINAL" "$CAT_DLW_JOB" "$CAT_DLW_DONE" "$CAT_DLW_TOTAL" "$CAT_DLW_OK" "$CAT_DLW_FAILED" "$CAT_DLW_SKIPPED" listo
  printf '[BLOCKLIST] Download-all %s: %s/%s valid, %s failed, %s skipped.\n' \
    "$CAT_DLW_FINAL" "$CAT_DLW_OK" "$CAT_DLW_TOTAL" "$CAT_DLW_FAILED" "$CAT_DLW_SKIPPED" >> "$CAT_DOWNLOAD_LOG"
  rm -rf "$CAT_DOWNLOAD_LOCK" 2>/dev/null
  return 0
}

# Restaura la última caché verificada y su fila de metadata. La operación en
# caché y source-success.tsv es atómica por archivo; el manifest se regenera al
# terminar y nunca se modifica blocked-names.txt directamente.
cat_restore_previous() {
  _id="$1"; _cached="$CAT_CACHE_DIR/$_id.list"
  _prev="$CAT_CACHE_DIR/$_id.list.prev"
  if [ -s "$_prev" ]; then
    _tmp="$CAT_CACHE_DIR/$_id.list.restore.$$"
    cp -f "$_prev" "$_tmp" && mv -f "$_tmp" "$_cached" || { rm -f "$_tmp"; return 1; }
  else
    rm -f "$_cached"
  fi
  _t="$CAT_SUCCESS.restore.$$"
  awk -F'\t' -v id="$_id" '$1 != id' "$CAT_SUCCESS" 2>/dev/null > "$_t"
  [ -f "$CAT_CACHE_DIR/$_id.meta.prev" ] && cat "$CAT_CACHE_DIR/$_id.meta.prev" >> "$_t"
  mv -f "$_t" "$CAT_SUCCESS" && chmod 0600 "$CAT_SUCCESS" 2>/dev/null || return 1
  cat_manifest_generate
}

# Rollback manual de una fuente: PREPARE cache/metadata, compilar, y si falla
# devolver los artefactos que estaban activos al inicio de la operación.
cat_rollback_one() {
  _id="$1"
  cat_exists "$_id" || { echo "ERROR: id desconocido: '$_id'" >&2; return 1; }
  _prev="$CAT_CACHE_DIR/$_id.list.prev"
  [ -s "$_prev" ] || { echo "ERROR: no hay copia anterior para '$_id'." >&2; return 1; }
  _cur="$CAT_CACHE_DIR/$_id.list"
  _curbak="$CAT_CACHE_DIR/$_id.list.rollback-current.$$"
  [ -f "$_cur" ] && cp -f "$_cur" "$_curbak"
  _row=$(cat_success_row "$_id")
  _rowbak="$CAT_CACHE_DIR/$_id.meta.rollback-current.$$"
  [ -n "$_row" ] && printf '%s\n' "$_row" > "$_rowbak"
  cat_restore_previous "$_id" || { rm -f "$_curbak" "$_rowbak"; return 1; }
  if cat_is_enabled "$_id" && ! cat_compile; then
    if [ -f "$_curbak" ]; then mv -f "$_curbak" "$_cur"
    else rm -f "$_cur"; fi
    _t="$CAT_SUCCESS.rollback.$$"
    awk -F'\t' -v id="$_id" '$1 != id' "$CAT_SUCCESS" 2>/dev/null > "$_t"
    [ -f "$_rowbak" ] && cat "$_rowbak" >> "$_t"
    mv -f "$_t" "$CAT_SUCCESS"; cat_manifest_generate >/dev/null 2>&1
    cat_compile >/dev/null 2>&1
    rm -f "$_rowbak"
    echo "ERROR: rollback de '$_id' rechazado por la compilación; se restauró el estado previo." >&2
    return 1
  fi
  rm -f "$_curbak" "$_rowbak"
  log_msg "[BLOCKLIST] ROLLBACK $_id restored previous validated copy"
  echo "OK: '$_id' restaurada a la copia verificada anterior."
}

# ---------------------------------------------------------------------------
# Compilacion a escala (fusion de activas). Lock + espacio libre. El pipeline
# atomico/rollback real vive en sec_regen_and_reload (que llama sec_merge_blocked
# -> cat_append_active). Aca se agrega control operativo.
# ---------------------------------------------------------------------------
cat_free_kb() {
  # Override SOLO para pruebas: valor estrictamente numerico y con TEST_MODE=1.
  # En produccion se ignora por completo y se usa df real.
  if [ "${DNSCRYPT_TEST_MODE:-0}" = "1" ]; then
    case "${DNSCRYPT_TEST_FREE_KB:-}" in
      ''|*[!0-9]*) : ;;
      *) printf '%s\n' "$DNSCRYPT_TEST_FREE_KB"; return 0 ;;
    esac
  fi
  df -k "$DATA_DIR" 2>/dev/null | awk 'NR==2 {print $4; found=1} END{ if(!found) print 0 }'
}

# Marcador para identificar procesos de compilacion de este modulo (evita matar
# procesos ajenos por reuso de PID).
CAT_PROC_MARK="dnscrypt-manager"

# ¿El lock corresponde a una compilacion REALMENTE viva de este modulo?
_cat_lock_live() {
  _p=$(cat "$CAT_COMPILE_LOCK/pid" 2>/dev/null)
  [ -n "$_p" ] || return 1
  kill -0 "$_p" 2>/dev/null || return 1
  if [ -r "/proc/$_p/cmdline" ]; then
    tr '\0' ' ' < "/proc/$_p/cmdline" 2>/dev/null | grep -q "$CAT_PROC_MARK" && return 0
    return 1   # PID reutilizado por otro proceso ajeno -> lock huerfano
  fi
  return 0      # sin /proc: conservador
}

# ¿Un PID dado es un proceso de compilacion de este modulo? (para cancelar)
_cat_pid_is_ours() {
  _p="$1"; [ -n "$_p" ] || return 1
  kill -0 "$_p" 2>/dev/null || return 1
  if [ -r "/proc/$_p/cmdline" ]; then
    tr '\0' ' ' < "/proc/$_p/cmdline" 2>/dev/null | grep -q "$CAT_PROC_MARK"
    return $?
  fi
  return 0
}

# Mata un PID y TODOS sus descendientes recorriendo /proc por PPID (portable,
# sin pkill/killall/patrones amplios). Solo toca el subarbol del PID indicado.
_cat_kill_tree() {
  _root="$1"; _sig="${2:-TERM}"
  [ -n "$_root" ] || return 0
  # Congelar el root ANTES de recolectar: asi no puede salir (y reparentar sus
  # hijos a init) ni forkear nuevos procesos mientras armamos el subarbol. Es la
  # clave para no perder un hijo (p.ej. el proceso pesado) por una carrera.
  kill -STOP "$_root" 2>/dev/null
  # Recolectar TODO el subarbol (BFS por PPID) antes de matar nada.
  _pending="$_root"; _all=""
  while [ -n "$_pending" ]; do
    _next=""
    for _p in $_pending; do
      _all="$_all $_p"
      for _st in /proc/[0-9]*/stat; do
        [ -r "$_st" ] || continue
        # campo 4 = PPID (tras "pid (comm) state"); comm puede tener espacios/())
        set -- $(sed 's/([^)]*)/X/' "$_st" 2>/dev/null)
        _cpid="$1"; _cppid="$4"
        [ "$_cppid" = "$_p" ] && _next="$_next $_cpid"
      done
    done
    _pending="$_next"
  done
  # Señalar por PID todo lo recolectado (si algo se reparentó despues de la
  # recoleccion, igual lo alcanzamos porque su PID no cambia).
  for _p in $_all; do kill -"$_sig" "$_p" 2>/dev/null; done
  # Descongelar el root para que procese la señal pendiente (TERM/KILL) y muera.
  kill -CONT "$_root" 2>/dev/null
}

cat_progress_set() {
  printf '%s\t%s\t%s\n' "$1" "$(sec_now)" "${2:-}" > "$CAT_COMPILE_PROGRESS" 2>/dev/null
}

# Aplica nice/ionice AL PROPIO proceso pesado (no a un comando vacio) y corre el
# pipeline atomico real. Fallback silencioso si nice/ionice no existen.
cat_compile_heavy() {
  command -v renice >/dev/null 2>&1 && renice -n 10 -p "$$" >/dev/null 2>&1
  command -v ionice >/dev/null 2>&1 && ionice -c 3 -p "$$" >/dev/null 2>&1
  cat_validate_active_limit || return 1
  # Hook de prueba CONTROLADO (solo bajo TEST_MODE): valores numericos/booleanos,
  # nunca ejecucion de comandos arbitrarios. Permite probar cancelacion/timeout/
  # fallo/exito a traves de la CLI real sin tocar el pipeline de produccion.
  if [ "${DNSCRYPT_TEST_MODE:-0}" = "1" ]; then
    _ts="${DNSCRYPT_TEST_COMPILE_SLEEP:-}"
    case "$_ts" in ''|*[!0-9]*) : ;; *) sleep "$_ts" ;; esac
    [ "${DNSCRYPT_TEST_COMPILE_FAIL:-0}" = "1" ] && return 1
    : > "$BL_BLOCKED" 2>/dev/null
    cat_append_active "$BL_BLOCKED" 2>/dev/null
    sort -u "$BL_BLOCKED" -o "$BL_BLOCKED" 2>/dev/null
    return 0
  fi
  if command -v sec_regen_and_reload >/dev/null 2>&1; then
    sec_regen_and_reload --verify-dns
  else
    return 1
  fi
}

# Compilacion completa (accion explicita). NO se ejecuta en boot.
cat_compile() {
  if cat_download_all_running; then
    echo "ERROR: no se puede compilar mientras la descarga global modifica cachés. Reintentá cuando termine." >&2
    return 1
  fi
  _to="${CAT_COMPILE_TIMEOUT:-$CAT_COMPILE_TIMEOUT_DEFAULT}"
  case "$_to" in ''|*[!0-9]*) _to="$CAT_COMPILE_TIMEOUT_DEFAULT" ;; esac

  # 1) Lock ATOMICO via mkdir. Si existe: distinguir vivo vs huerfano.
  if ! mkdir "$CAT_COMPILE_LOCK" 2>/dev/null; then
    if _cat_lock_live; then
      echo "ERROR: ya hay una compilacion en curso (pid $(cat "$CAT_COMPILE_LOCK/pid" 2>/dev/null))." >&2
      echo "       Consultá 'catalog compile-status' o cancelá con 'catalog compile-cancel'." >&2
      return 1
    fi
    # Lock huerfano (proceso muerto o PID reutilizado): recuperar.
    log_msg "catalog compile: lock huerfano recuperado"
    rm -rf "$CAT_COMPILE_LOCK" 2>/dev/null
    mkdir "$CAT_COMPILE_LOCK" 2>/dev/null || { echo "ERROR: no se pudo tomar el lock de compilacion." >&2; return 1; }
  fi
  echo "$$" > "$CAT_COMPILE_LOCK/pid" 2>/dev/null
  echo "$(sec_now)" > "$CAT_COMPILE_LOCK/started" 2>/dev/null
  # Trap: limpiar el lock ante cualquier salida/senal. No borra la ultima lista.
  trap 'rm -rf "$CAT_COMPILE_LOCK" 2>/dev/null' EXIT INT TERM HUP
  cat_progress_set running "inicio"

  # 2) Espacio libre.
  _free=$(cat_free_kb)
  if [ -n "$_free" ] && [ "$_free" -lt "$CAT_MIN_FREE_KB" ] 2>/dev/null; then
    cat_progress_set failed "espacio insuficiente (${_free}KB)"
    rm -rf "$CAT_COMPILE_LOCK" 2>/dev/null; trap - EXIT INT TERM HUP
    echo "ERROR: espacio libre insuficiente (${_free}KB < ${CAT_MIN_FREE_KB}KB)." >&2; return 1
  fi

  _t0=$(sec_now)
  echo "Compilando listas activas (categorias legacy + catalogo)…"
  cat_progress_set merging "fusionando y validando fuentes"

  # 3) Operacion pesada en un HIJO propio. No usar `set -m`: en shells POSIX
  #    no interactivos (incluido dash, usado por CI) puede bloquear el script.
  #    La cancelacion recorre y mata exclusivamente el subarbol del PID registrado.
  ( cat_compile_heavy ) &
  _child=$!
  echo "$_child" > "$CAT_COMPILE_LOCK/child" 2>/dev/null
  # Watchdog portable. Se despierta como maximo cada 1 s, de modo que al cancelar
  # no queda un `sleep $_to` huerfano que obligue al padre a esperar todo el timeout.
  ( _cat_wd_n=0
    while [ "$_cat_wd_n" -lt "$_to" ] 2>/dev/null; do
      sleep 1
      _cat_wd_n=$((_cat_wd_n + 1))
    done
    _cat_kill_tree "$_child" TERM
    sleep 3
    _cat_kill_tree "$_child" KILL ) &
  _wd=$!
  wait "$_child" 2>/dev/null; _rc=$?
  kill "$_wd" 2>/dev/null; wait "$_wd" 2>/dev/null
  _t1=$(sec_now)

  # ¿Cancelado/expirado? (rc por senal = 128+n)
  if [ "$_rc" -ge 128 ] 2>/dev/null; then
    _dur=$((_t1 - _t0))
    if [ "$_dur" -ge "$_to" ] 2>/dev/null; then
      cat_progress_set timeout "excedio ${_to}s"
      echo "ERROR: compilacion abortada por timeout (${_to}s). Se conserva la ultima lista valida." >&2
    else
      cat_progress_set cancelled "cancelada por el usuario"
      echo "Compilacion cancelada. Se conserva la ultima lista valida." >&2
    fi
    rm -rf "$CAT_COMPILE_LOCK" 2>/dev/null; trap - EXIT INT TERM HUP
    return 1
  fi

  rm -rf "$CAT_COMPILE_LOCK" 2>/dev/null; trap - EXIT INT TERM HUP
  _cnt=0; [ -f "$BL_BLOCKED" ] && _cnt=$(wc -l < "$BL_BLOCKED" | tr -d ' ')
  if [ "$_rc" = "0" ]; then
    cat_progress_set done "$_cnt dominios en $((_t1 - _t0))s"
    echo "OK: compilacion terminada. $_cnt dominios activos en $((_t1 - _t0))s."
    log_msg "catalog compile: OK ($_cnt dominios, $((_t1 - _t0))s)"
    if ! cat_provenance_generate; then
      log_msg "[BLOCKLIST] ERROR could not regenerate source provenance after compile"
      echo "AVISO: lista activa compilada, pero no se pudo actualizar source-provenance.tsv." >&2
    fi
    if ! cat_manifest_generate; then
      log_msg "[BLOCKLIST] ERROR could not regenerate blocklists-manifest.json after compile"
      echo "AVISO: lista activa compilada, pero no se pudo actualizar blocklists-manifest.json." >&2
    fi
    # Estadisticas de aporte unico (best-effort; no altera el catalogo canonico).
    command -v cat_stats_compute >/dev/null 2>&1 && cat_stats_compute 2>/dev/null
  else
    cat_progress_set failed "rc=$_rc"
    echo "ERROR: la compilacion fallo (rc=$_rc). Se conserva la ultima lista valida." >&2
  fi
  return "$_rc"
}

# Estado consultable de la compilacion.
cat_compile_status() {
  if [ -d "$CAT_COMPILE_LOCK" ] && _cat_lock_live; then
    _p=$(cat "$CAT_COMPILE_LOCK/pid" 2>/dev/null)
    _st=$(cat "$CAT_COMPILE_LOCK/started" 2>/dev/null)
    _el=$(( $(sec_now) - ${_st:-$(sec_now)} ))
    echo "estado    : EN CURSO (pid $_p, ${_el}s)"
  else
    echo "estado    : inactiva"
  fi
  if [ -f "$CAT_COMPILE_PROGRESS" ]; then
    _pl=$(cat "$CAT_COMPILE_PROGRESS" 2>/dev/null)
    echo "progreso  : $(printf '%s' "$_pl" | cut -f1) ($(printf '%s' "$_pl" | cut -f3-))"
    echo "timestamp : $(printf '%s' "$_pl" | cut -f2)"
  else
    echo "progreso  : (sin registro)"
  fi
}

# Cancelacion explicita: valida y mata SOLO el hijo registrado por el motor.
cat_compile_cancel() {
  if [ ! -d "$CAT_COMPILE_LOCK" ]; then echo "No hay compilacion en curso."; return 0; fi
  _child=$(cat "$CAT_COMPILE_LOCK/child" 2>/dev/null)
  _drv=$(cat "$CAT_COMPILE_LOCK/pid" 2>/dev/null)
  _killed=0
  if _cat_pid_is_ours "$_child"; then
    _cat_kill_tree "$_child" TERM; kill -TERM "-$_child" 2>/dev/null
    sleep 1
    _cat_kill_tree "$_child" KILL; kill -KILL "-$_child" 2>/dev/null
    _killed=1
  fi
  # El driver liberara el lock via su trap; si el driver ya no existe, limpiar.
  if [ -n "$_drv" ] && ! kill -0 "$_drv" 2>/dev/null; then rm -rf "$CAT_COMPILE_LOCK" 2>/dev/null; fi
  cat_progress_set cancelled "cancelada por el usuario"
  if [ "$_killed" = "1" ]; then echo "OK: compilacion cancelada."; else echo "No se encontro un proceso de compilacion propio para cancelar (lock limpiado si estaba huerfano)."; fi
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
        # Evitar el DUAL: si '_s' ya declara estar contenida en '_id', la relacion
        # se reporta desde el lado contained_by. Emitir una sola advertencia.
        _sc=$(cat_field "$_s" 15)
        case ",$_sc," in *",$_id,"*) continue ;; esac
        echo "  [sustitucion] '$_id' hace redundante a '$_s' (activa). Estas fuentes no son incompatibles, pero gran parte de su contenido ya esta incluido."
        _any=1
      fi
    done
    for _o in $_ovl; do
      [ -n "$_o" ] || continue
      # Relacion SIMETRICA: reportar una sola vez por par (id < otro).
      if cat_is_enabled "$_o" && [ "$_id" \< "$_o" ]; then
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
        # Simetrica: una sola vez por par.
        if cat_is_enabled "$_x" && [ "$_id" \< "$_x" ]; then
          echo "  [conflicto] '$_id' entra en conflicto con '$_x' (ambas activas)."
          _any=1
        fi ;;
      esac
    done
    IFS=$_oldIFS
  done < "$CAT_ENABLED"
  # Segunda pasada: estados/formatos de las activas + allowlist que neutraliza.
  while IFS= read -r _id; do
    [ -n "$_id" ] || continue
    cat_is_enabled "$_id" || continue
    _ups=$(cat_upstream_status "$_id"); _rt=$(cat_runtime_status "$_id")
    _fmt=$(cat_field "$_id" 7)
    case "$_ups" in
      archived) echo "  [archivada] '$_id' esta ACTIVA pero su upstream esta archivado; puede quedar sin actualizaciones."; _any=1 ;;
      broken)   echo "  [rota] '$_id' esta ACTIVA pero el catalogo la marca como rota; revisá si conviene desactivarla."; _any=1 ;;
    esac
    case "$_rt" in
      download_failed|validation_failed) echo "  [sin datos] '$_id' esta activa pero su ultima descarga fallo ($_rt); se usa la ultima copia valida si existe."; _any=1 ;;
    esac
    case "$_fmt" in
      abp) echo "  [formato parcial] '$_id' es ABP: solo se importan reglas de dominio inequivocas (cobertura DNS parcial)."; _any=1 ;;
    esac
  done < "$CAT_ENABLED"
  # Allowlist que neutraliza dominios bloqueados por controles de servicio activos.
  if command -v cat_svc_active_blocked >/dev/null 2>&1 && [ -f "$ALLOWLIST_FILE" ]; then
    _svcb="$RUN_DIR/conf.svcb.$$"; cat_svc_active_blocked 2>/dev/null | sort -u > "$_svcb"
    if [ -s "$_svcb" ]; then
      _aln="$RUN_DIR/conf.aln.$$"; sort -u "$ALLOWLIST_FILE" > "$_aln" 2>/dev/null
      comm -12 "$_svcb" "$_aln" 2>/dev/null | while IFS= read -r _d; do
        [ -n "$_d" ] || continue
        echo "  [allowlist neutraliza] '$_d' esta en la allowlist Y bloqueado por un control de servicio; la allowlist gana (el bloqueo no aplica a ese dominio)."
        _any=1
      done
      rm -f "$_aln"
    fi
    rm -f "$_svcb"
  fi
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
  _row="$_id	custom	$_name	usuario	$_catg	medium	$_fmt	$_url	LICENSE_UNKNOWN	custom	0	unknown	0				$(date '+%Y-%m-%d')	Fuente personalizada agregada por el usuario."
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
  _was=0; cat_is_enabled "$_id" && _was=1
  cat_disable "$_id"
  rm -f "$CAT_CACHE_DIR/$_id.list" "$CAT_CACHE_DIR/$_id.list.prev" "$CAT_CACHE_DIR/$_id.meta.prev" 2>/dev/null
  cat_success_clear "$_id"; srcst_clear "$_id"
  if [ "$_was" = "1" ]; then cat_compile || return 1; else cat_provenance_generate; cat_manifest_generate; fi
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
    sync)
      cat_sync_index || return 1
      echo "OK: index del catalogo sincronizado ($(cat_all_ids | wc -l | tr -d ' ') entradas)."
      ;;
    audit) cat_audit ;;

    groups)
      _json=0
      while [ $# -gt 0 ]; do
        case "$1" in
          --json) _json=1; shift ;;
          *) shift ;;
        esac
      done
      if [ "$_json" = "1" ]; then
        cat_groups_output
      else
        cat_groups_output
      fi
      ;;

    list)
      _json=0; _filter_cat=""; _filter_maint=""; _only_enabled=0; _only_recommended=0; _only_archived=0; _search=""; _source_group=""
      while [ $# -gt 0 ]; do
        case "$1" in
          --json) _json=1; shift ;;
          --category) _filter_cat="$2"; shift 2 ;;
          --maintainer) _filter_maint="$2"; shift 2 ;;
          --enabled) _only_enabled=1; shift ;;
          --recommended) _only_recommended=1; shift ;;
          --archived) _only_archived=1; shift ;;
          --search) _search=$(printf '%s' "$2" | tr 'A-Z' 'a-z'); shift 2 ;;
          --source-group) _source_group="$2"; shift 2 ;;
          *) shift ;;
        esac
      done
      case "$_source_group" in
        ""|Security|Privacy|ParentalControl|dcm|RethinkUnassigned|rethink_unassigned) : ;;
        *) echo "ERROR: grupo de fuente invalido: '$_source_group'" >&2; return 2 ;;
      esac
      [ "$_source_group" = "RethinkUnassigned" ] && _source_group="rethink_unassigned"
      _print_one() {
        _id="$1"
        _row=$(cat_row "$_id"); [ -n "$_row" ] || return 0
        _name=$(printf '%s' "$_row" | cut -f3); _maint=$(printf '%s' "$_row" | cut -f4)
        _cats=$(printf '%s' "$_row" | cut -f5); _agg=$(printf '%s' "$_row" | cut -f6)
        _fmt=$(printf '%s' "$_row" | cut -f7); _lic=$(printf '%s' "$_row" | cut -f9)
        _ups=$(cat_upstream_status "$_id"); _rt=$(cat_runtime_status "$_id"); _rec=$(printf '%s' "$_row" | cut -f11)
        _mob=$(printf '%s' "$_row" | cut -f12); _arch=$(printf '%s' "$_row" | cut -f13)
        _desc=$(printf '%s' "$_row" | cut -f19)
        _source_name=$(printf '%s' "$_row" | cut -f20)
        _source_group=$(printf '%s' "$_row" | cut -f21)
        _source_subgroup=$(printf '%s' "$_row" | cut -f22)
        _source_packs=$(printf '%s' "$_row" | cut -f23)
        _source_formats=$(printf '%s' "$_row" | cut -f24)
        _source_urls=$(printf '%s' "$_row" | cut -f25)
        _source_url_count=$(printf '%s' "$_row" | cut -f26); [ -n "$_source_url_count" ] || _source_url_count=0
        # filtros
        [ "$_only_enabled" = "1" ] && { cat_is_enabled "$_id" || return 0; }
        [ "$_only_recommended" = "1" ] && [ "$_rec" != "1" ] && return 0
        [ "$_only_archived" = "1" ] && [ "$_arch" != "1" ] && return 0
        [ -n "$_filter_cat" ] && { printf '%s' ",$_cats," | grep -q ",$_filter_cat," || return 0; }
        [ -n "$_filter_maint" ] && { printf '%s' "$_maint" | grep -qiF "$_filter_maint" || return 0; }
        [ -n "$_search" ] && { printf '%s' "$_id $_name $_desc $_cats" | tr 'A-Z' 'a-z' | grep -qF "$_search" || return 0; }
        _en=no; cat_is_enabled "$_id" && _en=si
        _dom=$(cat_success_field "$_id" 7); [ -n "$_dom" ] || _dom=$(srcst_field "$_id" 9); [ -n "$_dom" ] || _dom="-"
        _last_success=$(cat_success_field "$_id" 9); [ -n "$_last_success" ] || _last_success=$(srcst_field "$_id" 4); [ -n "$_last_success" ] || _last_success=0
        _sha_success=$(cat_success_field "$_id" 4)
        _bytes_success=$(cat_success_field "$_id" 5); [ -n "$_bytes_success" ] || _bytes_success=0
        if [ "$_json" = "1" ]; then
          _enb=false; cat_is_enabled "$_id" && _enb=true
          _recb=false; [ "$_rec" = "1" ] && _recb=true
          _arb=false; [ "$_arch" = "1" ] && _arb=true
          # La incertidumbre de licencia se conserva en el campo `license`;
          # no es un bloqueo tecnico para una activacion manual.
          _licblocked=false
          _actblocked=false; cat_activation_check "$_id" >/dev/null 2>&1 || _actblocked=true
          [ "$CAT_JSON_FIRST" = "0" ] && printf ','
          CAT_JSON_FIRST=0
          printf '{"id":"%s","name":"%s","source_name":"%s","source_group":"%s","source_subgroup":"%s","source_packs":"%s","source_formats":"%s","source_urls":"%s","source_url_count":%s,"activation_blocked":%s,"maintainer":"%s","categories":"%s","aggressiveness":"%s","format":"%s","license":"%s","license_blocked":%s,"upstream_status":"%s","runtime_status":"%s","mobile_suitability":"%s","recommended":%s,"archived":%s,"enabled":%s,"valid_domains":"%s","cache_domains":"%s","last_success":%s,"sha256":"%s","downloaded_bytes":%s}' \
            "$(cat_json_escape "$_id")" "$(cat_json_escape "$_name")" \
            "$(cat_json_escape "$_source_name")" "$(cat_json_escape "$_source_group")" \
            "$(cat_json_escape "$_source_subgroup")" "$(cat_json_escape "$(printf '%s' "$_source_packs" | tr ',' '|')")" \
            "$(cat_json_escape "$(printf '%s' "$_source_formats" | tr ',' '|')")" \
            "$(cat_json_escape "$(printf '%s' "$_source_urls" | tr ',' '|')")" "$_source_url_count" "$_actblocked" \
            "$(cat_json_escape "$_maint")" "$(cat_json_escape "$_cats")" "$_agg" "$_fmt" "$(cat_json_escape "$_lic")" "$_licblocked" "$_ups" "$_rt" \
            "$_mob" "$_recb" "$_arb" "$_enb" "$_dom" "$_dom" "$_last_success" \
            "$(cat_json_escape "$_sha_success")" "$_bytes_success"
        else
          printf '  [%s] %-34s %-12s %-9s %s/%s dom=%-8s %s%s\n' \
            "$_en" "$_id" "$_maint" "$_agg" "$_ups" "$_rt" "$_dom" \
            "$( [ "$_rec" = 1 ] && echo '(recomendada) ' )" \
            "$( [ "$_arch" = 1 ] && echo '(ARCHIVADA) ' )"
        fi
      }
      if [ "$_json" = "1" ]; then
        cat_list_output "$_filter_cat" "$_filter_maint" "$_only_enabled" \
          "$_only_recommended" "$_only_archived" "$_search" json "$_source_group" || return $?
      else
        cat_list_output "$_filter_cat" "$_filter_maint" "$_only_enabled" \
          "$_only_recommended" "$_only_archived" "$_search" text "$_source_group" || return $?
      fi
      # adult_advertising: no existe una fuente dedicada verificable.
      if [ "$_filter_cat" = "adult_advertising" ]; then
        echo "No se encontro una fuente mantenida y verificable dedicada exclusivamente a publicidad para adultos. La cobertura actual proviene de listas generales de anuncios, pop-ups y malvertising."
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
      echo "estado up.   : $(cat_upstream_status "$_id") (declarado por el catalogo)"
      echo "estado local : $(cat_runtime_status "$_id") (resultado en este equipo)"
      echo "movil        : $(printf '%s' "$_row" | cut -f12)"
      echo "recomendada  : $( [ "$(printf '%s' "$_row" | cut -f11)" = 1 ] && echo si || echo no )"
      echo "archivada    : $( [ "$(printf '%s' "$_row" | cut -f13)" = 1 ] && echo si || echo no )"
      echo "sustituye a  : $(printf '%s' "$_row" | cut -f14)"
      echo "contenida en : $(printf '%s' "$_row" | cut -f15)"
      echo "se solapa con: $(printf '%s' "$_row" | cut -f16)"
      echo "conflictos   : $(printf '%s' "$_row" | cut -f17)"
      echo "activa       : $( cat_is_enabled "$_id" && echo si || echo no )"
      echo "descripcion  : $(printf '%s' "$_row" | cut -f19)"
      echo "cache valida : $(cat_success_field "$_id" 7) dominios"
      echo "cache sha256 : $(cat_success_field "$_id" 4)"
      echo "cache bytes  : $(cat_success_field "$_id" 5)"
      echo "cache éxito  : $(cat_success_field "$_id" 9)"
      if [ -n "$(srcst_row "$_id")" ]; then
        echo "--- ultimo intento (persistente, source-status.tsv) ---"
        echo "  total_source   : $(srcst_field "$_id" 8)"
        echo "  valid_domains  : $(srcst_field "$_id" 9)"
        echo "  invalid_entries: $(srcst_field "$_id" 10)"
        echo "  http           : $(srcst_field "$_id" 5)"
        echo "  bytes          : $(srcst_field "$_id" 6)"
        echo "  sha256_list    : $(srcst_field "$_id" 7)"
        echo "  cobertura DNS  : $( [ "$(srcst_field "$_id" 11)" = 1 ] && echo 'parcial (ABP)' || echo completa )"
        echo "  last_attempt   : $(srcst_field "$_id" 3)"
        echo "  last_success   : $(srcst_field "$_id" 4)"
        _emsg=$(srcst_field "$_id" 12); [ -n "$_emsg" ] && echo "  error          : $_emsg"
      else
        echo "(aun no descargada: usa 'catalog update $_id')"
      fi
      ;;

    enable)
      _id="$1"
      cat_exists "$_id" || { echo "ERROR: id desconocido: '$_id'" >&2; return 1; }
      [ "$(cat_field "$_id" 13)" = "1" ] && echo "AVISO: '$_id' esta ARCHIVADA (legado). Se activa igual, pero no es recomendable."
      cat_enable "$_id" || return 1
      if [ ! -s "$CAT_CACHE_DIR/$_id.list" ]; then
        echo "'$_id' habilitada, pero aun sin descargar. Descargando…"
        cat_update_one "$_id" || {
          cat_disable "$_id"
          cat_compile >/dev/null 2>&1
          echo "ERROR: no se pudo validar la primera copia; fuente desactivada." >&2
          return 1
        }
      fi
      if ! cat_compile; then
        cat_disable "$_id"; cat_compile >/dev/null 2>&1
        echo "ERROR: la compilación falló; se revirtió la activación de '$_id'." >&2
        return 1
      fi
      echo "OK: '$_id' activada y compilada."
      ;;

    disable)
      _id="$1"
      cat_is_enabled "$_id" || { echo "'$_id' no estaba activa."; return 0; }
      cat_disable "$_id"
      if ! cat_compile; then
        cat_enable "$_id"; cat_compile >/dev/null 2>&1
        echo "ERROR: la compilación falló; se restauró la activación de '$_id'." >&2
        return 1
      fi
      echo "OK: '$_id' desactivada y recompilada."
      ;;

    update)
      _tgt="${1:-enabled}"
      if [ "$_tgt" = "enabled" ] || [ "$_tgt" = "all" ]; then
        _fails=0; _n=0; _updated="$RUN_DIR/cat.updated.$$"; : > "$_updated"
        while IFS= read -r _id; do
          [ -n "$_id" ] || continue
          _n=$((_n+1))
          if cat_update_one "$_id"; then printf '%s\n' "$_id" >> "$_updated"
          else _fails=$((_fails+1)); fi
        done < "$CAT_ENABLED"
        [ "$_n" = "0" ] && { rm -f "$_updated"; echo "(no hay fuentes activas para actualizar)"; return 0; }
        if ! cat_compile; then
          _fails=$((_fails+1))
          while IFS= read -r _rid; do [ -n "$_rid" ] && cat_restore_previous "$_rid" >/dev/null 2>&1; done < "$_updated"
          cat_compile >/dev/null 2>&1 || log_msg "[BLOCKLIST] ERROR rollback compile failed after source update batch"
        fi
        rm -f "$_updated"
        [ "$_fails" = "0" ] && echo "OK: $_n fuente(s) activa(s) actualizada(s) y compiladas." || { echo "ERROR: $_fails fallo(s)." >&2; return 1; }
      else
        cat_update_one "$_tgt" || return 1
        if cat_is_enabled "$_tgt" && ! cat_compile; then
          cat_restore_previous "$_tgt" >/dev/null 2>&1
          cat_compile >/dev/null 2>&1 || log_msg "[BLOCKLIST] ERROR rollback compile failed for $_tgt"
          echo "ERROR: la compilación falló; se restauró la caché previa de '$_tgt'." >&2
          return 1
        fi
      fi
      ;;

    download-all)
      case "${1:-}" in
        --confirmed) cat_download_all_start --confirmed ;;
        status)
          [ "${2:-}" = "--json" ] && cat_download_all_status_json || cat_download_all_status_json ;;
        *)
          echo "Acción global: descarga y valida las fuentes compatibles sin activarlas." >&2
          echo "Uso: dnscrypt-manager catalog download-all --confirmed" >&2
          echo "     dnscrypt-manager catalog download-all status --json" >&2
          return 2 ;;
      esac
      ;;
    download-all-worker) cat_download_all_worker "${1:-}" ;;

    rollback) cat_rollback_one "$1" ;;
    manifest)
      [ -s "$CAT_MANIFEST" ] || cat_manifest_generate || return 1
      cat "$CAT_MANIFEST" ;;
    provenance)
      [ -s "$CAT_PROVENANCE" ] || cat_provenance_generate || return 1
      cat "$CAT_PROVENANCE" ;;

    compile) cat_compile ;;
    compile-status) cat_compile_status ;;
    compile-cancel) cat_compile_cancel ;;
    conflicts) cat_conflicts_report ;;
    overlap)
      if [ -n "$1" ] && [ -n "$2" ]; then cat_overlap_exact "$1" "$2"; else echo "Uso: catalog overlap <fuente_a> <fuente_b>" >&2; return 1; fi ;;
    stats) cat_stats_show "$1" ;;
    metrics)
      _id="$1"; cat_exists "$_id" || { echo "ERROR: id desconocido" >&2; return 1; }
      echo "Metricas de '$_id' (source-status.tsv):"
      echo "  runtime_status  = $(srcst_status "$_id")"
      echo "  total_source    = $(srcst_field "$_id" 8)"
      echo "  valid_domains   = $(srcst_field "$_id" 9)"
      echo "  invalid_entries = $(srcst_field "$_id" 10)"
      echo "  sha256_list     = $(srcst_field "$_id" 7)"
      echo "  partial_dns     = $(srcst_field "$_id" 11)"
      echo "  last_attempt    = $(srcst_field "$_id" 3)"
      echo "  last_success    = $(srcst_field "$_id" 4)" ;;
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
      echo "Uso: dnscrypt-manager catalog {list [--json][--search S][--category C][--maintainer M][--enabled][--recommended][--archived]|info <id>|enable <id>|disable <id>|update [id|enabled|all]|download-all --confirmed|download-all status --json|rollback <id>|manifest|provenance|compile|conflicts [id1 id2]|metrics <id>|test <id>|custom ...|sync}" >&2
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

# cat_audit — auditoria OFFLINE de metadatos del catalogo (D.3). No descarga nada.
# Detecta: URLs duplicadas, licencia ausente, estado broken/archived, formato
# desconocido, duplicacion extrema (supersedes/contained_by).
cat_audit() {
  _idx="$DATA_DIR/catalog/blocklists.index.tsv"
  [ -f "$_idx" ] || _idx="$MODDIR/config/catalog/blocklists.index.tsv"
  [ -f "$_idx" ] || { echo "ERROR: indice de catalogo ausente" >&2; return 1; }
  _total=$(awk -F'\t' '!/^#/{c++} END{print c}' "$_idx")
  echo "total_sources        : $_total"
  # URLs duplicadas (columna 8)
  _dup=$(awk -F'\t' '!/^#/ && $8!="" {print $8}' "$_idx" | sort | uniq -d | wc -l | tr -d ' ')
  echo "duplicate_urls       : $_dup"
  [ "${_dup:-0}" -gt 0 ] && awk -F'\t' '!/^#/ && $8!="" {print $8}' "$_idx" | sort | uniq -d | sed 's/^/  dup: /'
  # licencia ausente (columna 9)
  _nolic=$(awk -F'\t' '!/^#/ && ($9=="" || $9=="-") {c++} END{print c+0}' "$_idx")
  echo "missing_license      : $_nolic"
  # estados declarados
  _broken=$(awk -F'\t' '!/^#/ && $10=="broken"{c++} END{print c+0}' "$_idx")
  _archived=$(awk -F'\t' '!/^#/ && $10=="archived"{c++} END{print c+0}' "$_idx")
  _legacy=$(awk -F'\t' '!/^#/ && $10=="legacy"{c++} END{print c+0}' "$_idx")
  echo "broken_sources       : $_broken"
  echo "archived_sources     : $_archived"
  echo "legacy_sources        : $_legacy"
  # formato desconocido (columna 3 vacia)
  _nofmt=$(awk -F'\t' '!/^#/ && ($3=="" ) {c++} END{print c+0}' "$_idx")
  echo "unknown_format       : $_nofmt"
  echo "note                 : auditoria de METADATOS (offline). 'verified' solo tras descarga runtime, nunca desde CI."
  # gate: fallar si hay duplicados de URL o formato desconocido
  [ "${_dup:-0}" -eq 0 ] && [ "${_nofmt:-0}" -eq 0 ]
}
