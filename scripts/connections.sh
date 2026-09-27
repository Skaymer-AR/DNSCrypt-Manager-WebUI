#!/system/bin/sh
# Muestra puntual de sockets conectados. No guarda historial ni intenta
# atribuir dominios DNS; devuelve UID y endpoint remoto desde /proc/net.

connections_snapshot() {
  _cn_limit=300
  if [ "${1:-}" != "" ]; then
    echo "Uso: dnscrypt-manager connections" >&2
    return 1
  fi
  _cn_root=/proc/net
  if [ "${DNSCRYPT_TEST_MODE:-0}" = 1 ] && [ -n "${DNSCRYPT_TEST_PROC_NET_DIR:-}" ]; then
    _cn_root="$DNSCRYPT_TEST_PROC_NET_DIR"
  fi
  _cn_seen=0
  _cn_any=0
  for _cn_spec in tcp6:TCPv6 tcp:TCPv4 udp6:UDPv6 udp:UDPv4; do
    _cn_file=${_cn_spec%%:*}
    _cn_proto=${_cn_spec#*:}
    [ -r "$_cn_root/$_cn_file" ] || continue
    _cn_left=$((_cn_limit - _cn_seen))
    [ "$_cn_left" -gt 0 ] || break
    _cn_rows=$(awk -v proto="$_cn_proto" -v lim="$_cn_left" '
      NR > 1 {
        split($3, remote, ":")
        port = remote[2]
        uid = $8
        state = $4
        if (port !~ /^[0-9A-Fa-f]+$/ || port ~ /^0+$/) next
        if (state == "0A" || state == "07") next
        if (uid !~ /^[0-9]+$/) next
        printf "%s|%s|%s|%s|%s\n", proto, remote[1], port, uid, state
        emitted++
        if (emitted >= lim) exit
      }
    ' "$_cn_root/$_cn_file" 2>/dev/null)
    if [ -n "$_cn_rows" ]; then
      printf '%s\n' "$_cn_rows"
      _cn_added=$(printf '%s\n' "$_cn_rows" | wc -l | tr -d ' ')
      _cn_seen=$((_cn_seen + _cn_added))
      _cn_any=1
    fi
  done
  [ "$_cn_any" = 1 ] || echo ""
  return 0
}
