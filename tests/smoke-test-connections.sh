#!/bin/bash
set -u
cd "$(dirname "$0")/.." || exit 1
. tests/_tp_common.sh
tp_setup
trap 'rm -rf "$TR"' EXIT
mkdir -p "$TR/proc"
cat > "$TR/proc/tcp" <<'EOF'
  sl  local_address rem_address   st tx_queue rx_queue tr tm->when retrnsmt   uid  timeout inode
   0: 0100007F:14E9 08080808:0035 01 00000000:00000000 00:00000000 00000000 10123 0 12345
   1: 00000000:0035 00000000:0000 0A 00000000:00000000 00:00000000 00000000 0 0 12346
EOF
cat > "$TR/proc/tcp6" <<'EOF'
  sl  local_address                         remote_address                        st tx_queue rx_queue tr tm->when retrnsmt   uid  timeout inode
   0: 00000000000000000000000001000000:14E9 00000000000000000000000008080808:0035 01 00000000:00000000 00:00000000 00000000 10124 0 22345
EOF
cat > "$TR/proc/udp" <<'EOF'
  sl  local_address rem_address   st tx_queue rx_queue tr tm->when retrnsmt   uid  timeout inode
   0: 0100007F:C000 08080808:0035 01 00000000:00000000 00:00000000 00000000 10125 0 32345
   1: 00000000:0035 00000000:0000 07 00000000:00000000 00:00000000 00000000 0 0 32346
EOF

R=$(DNSCRYPT_TEST_MODE=1 DNSCRYPT_TEST_ROOT="$TR" DNSCRYPT_TEST_DATA_DIR="$TR/data" DNSCRYPT_TEST_MODDIR="$M" DNSCRYPT_TEST_PROC_NET_DIR="$TR/proc" "$SH" "$M" connections)
[[ "$R" == *"TCPv4|08080808|0035|10123|01"* ]] && echo '  OK   TCP IPv4 conectado' || { echo '  FAIL TCP IPv4'; echo "$R"; exit 1; }
[[ "$R" == *"TCPv6|00000000000000000000000008080808|0035|10124|01"* ]] && echo '  OK   TCP IPv6 conectado' || { echo '  FAIL TCP IPv6'; echo "$R"; exit 1; }
[[ "$R" == *"UDPv4|08080808|0035|10125|01"* ]] && echo '  OK   UDP conectado' || { echo '  FAIL UDP'; echo "$R"; exit 1; }
[[ "$R" != *"|00000000|0000|"* && "$R" != *"|0A"* ]] && echo '  OK   omite sockets sin endpoint y listeners' || { echo '  FAIL sockets vacíos/listener'; exit 1; }
