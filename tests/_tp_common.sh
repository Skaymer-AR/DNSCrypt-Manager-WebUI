# helper comun de setup para tests de transporte
tp_setup() {
  TR="$(mktemp -d /tmp/dcm-tp.XXXXXX)"; export DNSCRYPT_TEST_MODE=1 DNSCRYPT_TEST_ROOT="$TR" DNSCRYPT_TEST_DATA_DIR="$TR/data" DNSCRYPT_TEST_MODDIR="$TR/mod"
  mkdir -p "$TR/data/config" "$TR/mod/system/bin" "$TR/mod/scripts" "$TR/mod/config/transport"
  cp system/bin/dnscrypt-manager "$TR/mod/system/bin/"; cp scripts/*.sh "$TR/mod/scripts/"
  cp config/transport/relays.json "$TR/mod/config/transport/"; cp config/dnscrypt-proxy.toml "$TR/data/config/"
  M="$TR/mod/system/bin/dnscrypt-manager"; SH="$(command -v sh)"; "$SH" "$M" migrate >/dev/null 2>&1
}
