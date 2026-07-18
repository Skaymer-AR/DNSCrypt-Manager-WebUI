#!/system/bin/sh
# scripts/monitor.sh  —  DNSCrypt Manager v0.3.0-RC1  (CHECKPOINT C.3)
#
# Monitor LOCAL de actividad DNS sospechosa. Sin nube, sin telemetría. Analiza
# SOLO datos DNS que el módulo ya procesa. Heurístico: NUNCA afirma "malware
# confirmado". Clasificación: normal/unusual/suspicious/high-risk. audit-only por
# defecto; con rotación y retención.

MON_DIR="${DATA_DIR}/monitor"
MON_ALERTS="$MON_DIR/alerts.tsv"
MON_CONF="$MON_DIR/config.tsv"
MON_MAX_ALERTS=1000

monitor_init() {
  mkdir -p "$MON_DIR" 2>/dev/null; chmod 0700 "$MON_DIR" 2>/dev/null
  [ -f "$MON_ALERTS" ] || : > "$MON_ALERTS"
  [ -f "$MON_CONF" ] || printf 'mode\taudit\nretention_days\t7\n' > "$MON_CONF"
  chmod 0600 "$MON_ALERTS" "$MON_CONF" 2>/dev/null
}

# Entropía aproximada de una cadena (nº de caracteres distintos / longitud) *100.
_mon_entropy_pct() {
  printf '%s' "$1" | awk '{
    n=split($0,a,""); if(n==0){print 0; exit}
    for(i=1;i<=n;i++) seen[a[i]]=1; c=0; for(k in seen) c++;
    printf "%d", (c*100)/n
  }'
}

# Clasifica un dominio (heurística). Imprime: nivel|razón
monitor_classify_domain() {
  _d="$1"; [ -n "$_d" ] || { echo "normal|vacio"; return; }
  _len=${#_d}
  _label=$(printf '%s' "$_d" | awk -F. '{print $1}')
  _llen=${#_label}
  _ent=$(_mon_entropy_pct "$_label")
  # subdominio extremadamente largo
  if [ "$_llen" -ge 40 ]; then echo "suspicious|subdominio muy largo ($_llen)"; return; fi
  # entropía alta + longitud media-alta -> posible DGA
  if [ "$_ent" -ge 65 ] && [ "$_llen" -ge 16 ]; then echo "high-risk heuristic|entropia alta ($_ent%%), posible DGA"; return; fi
  if [ "$_ent" -ge 55 ] && [ "$_llen" -ge 12 ]; then echo "suspicious|entropia elevada ($_ent%%)"; return; fi
  # muchos guiones/dígitos
  _dig=$(printf '%s' "$_label" | tr -cd '0-9' | wc -c | tr -d ' ')
  if [ "$_llen" -gt 0 ] && [ "$(( _dig * 100 / _llen ))" -ge 50 ]; then echo "unusual|muchos digitos"; return; fi
  echo "normal|sin señales"
}

# monitor_add DOMAIN LEVEL REASON [UID]
monitor_add() {
  monitor_init
  _d="$1"; _lvl="$2"; _reason="$3"; _uid="${4:-}"
  case "$_d" in *[!a-zA-Z0-9_.-]*) return 1 ;; esac   # sanitizar
  _now=$(date +%s 2>/dev/null || echo 0)
  # ¿existe ya? actualizar last/cantidad
  if grep -q "	$_d	" "$MON_ALERTS" 2>/dev/null; then
    awk -F'\t' -v d="$_d" -v now="$_now" 'BEGIN{OFS="\t"} $2==d{ $5=now; $6=$6+1 } {print}' "$MON_ALERTS" > "$MON_ALERTS.new" && mv -f "$MON_ALERTS.new" "$MON_ALERTS"
  else
    printf '%s\t%s\t%s\t%s\t%s\t1\t%s\n' "$_lvl" "$_d" "$_reason" "$_now" "$_now" "$_uid" >> "$MON_ALERTS"
  fi
  # rotación por tamaño
  _n=$(wc -l < "$MON_ALERTS" 2>/dev/null | tr -d ' ')
  if [ "${_n:-0}" -gt "$MON_MAX_ALERTS" ]; then tail -n "$MON_MAX_ALERTS" "$MON_ALERTS" > "$MON_ALERTS.new" && mv -f "$MON_ALERTS.new" "$MON_ALERTS"; fi
}

# monitor_scan: clasifica una lista de dominios (uno por línea en stdin) y anota
# los no-normales. Uso real: alimentado por el historial/eventos del módulo.
monitor_scan() {
  monitor_init; _added=0
  while IFS= read -r _d; do
    [ -n "$_d" ] || continue
    _res=$(monitor_classify_domain "$_d"); _lvl=${_res%%|*}; _rs=${_res#*|}
    [ "$_lvl" = normal ] && continue
    monitor_add "$_d" "$_lvl" "$_rs" && _added=$((_added+1))
  done
  echo "scanned_alerts=$_added"
}

monitor_status() {
  monitor_init
  echo "mode           : $(grep -m1 '^mode' "$MON_CONF" | cut -f2)"
  echo "retention_days : $(grep -m1 '^retention_days' "$MON_CONF" | cut -f2)"
  echo "alerts_total   : $(wc -l < "$MON_ALERTS" 2>/dev/null | tr -d ' ')"
  echo "note           : heurístico; NUNCA afirma malware confirmado. Todo local, sin telemetría."
}

monitor_alerts() {
  monitor_init
  [ -s "$MON_ALERTS" ] || { echo "(sin alertas)"; return; }
  echo "nivel	dominio	razon	primera	ultima	cant	uid"
  cat "$MON_ALERTS"
}

monitor_export() {
  monitor_init
  case "$1" in
    json)
      printf '['
      _first=1
      while IFS='	' read -r lvl dom reason first last cnt uid; do
        [ $_first -eq 1 ] || printf ','
        printf '{"level":"%s","domain":"%s","reason":"%s","first":%s,"last":%s,"count":%s,"uid":"%s"}' "$lvl" "$dom" "$reason" "${first:-0}" "${last:-0}" "${cnt:-0}" "$uid"
        _first=0
      done < "$MON_ALERTS"
      printf ']\n' ;;
    csv)
      echo "level,domain,reason,first,last,count,uid"
      awk -F'\t' 'BEGIN{OFS=","} {print $1,$2,$3,$4,$5,$6,$7}' "$MON_ALERTS" ;;
    *) echo "Uso: monitor export json|csv" >&2; return 1 ;;
  esac
}

monitor_clear() { monitor_init; : > "$MON_ALERTS"; echo "cleared=yes"; }
