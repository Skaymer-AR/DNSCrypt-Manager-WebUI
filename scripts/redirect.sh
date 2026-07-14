#!/system/bin/sh
# Wrapper fino: delega en la CLI dnscrypt-manager (unico cerebro del modulo).
CLI="/system/bin/dnscrypt-manager"
[ -x "$CLI" ] || CLI="/data/adb/modules/dnscrypt_manager/system/bin/dnscrypt-manager"
# Produccion: exec directo (respeta el shebang real). Modo test (exclusivo
# de tests/*.sh): interprete explicito via DNSCRYPT_TEST_SHELL, mismo
# motivo que run_cli() en uninstall.sh/service.sh/boot-completed.sh/action.sh.
if [ "${DNSCRYPT_TEST_MODE:-0}" = "1" ]; then
  exec "${DNSCRYPT_TEST_SHELL:-sh}" "$CLI" redirect apply
else
  exec "$CLI" redirect apply
fi
