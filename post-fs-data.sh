#!/system/bin/sh
##############################################################################
# DNSCrypt Manager - post-fs-data.sh
# Se ejecuta MUY temprano en el arranque. Regla de oro: hacer lo minimo
# posible aca. Nada que pueda colgar el boot ni provocar bootloop.
# El daemon y la red se manejan en service.sh (late_start), no aqui.
##############################################################################

MODDIR=${0%/*}
DATA_DIR=/data/adb/dnscrypt-manager
# Modo test (exclusivo de tests/*.sh, ver scripts/common.sh).
[ "${DNSCRYPT_TEST_MODE:-0}" = "1" ] && [ -n "${DNSCRYPT_TEST_DATA_DIR:-}" ] && DATA_DIR="$DNSCRYPT_TEST_DATA_DIR"
RUN_DIR="$DATA_DIR/run"

# Si el modulo esta deshabilitado por el flag de emergencia, no tocar nada.
[ -f "$DATA_DIR/disable" ] && exit 0

# Asegurar que exista el directorio de runtime (por si /data recien montado).
mkdir -p "$RUN_DIR" 2>/dev/null

# Limpiar pidfile viejo de un arranque anterior (el PID ya no es valido).
rm -f "$RUN_DIR/dnscrypt-proxy.pid" 2>/dev/null

# Registrar un marcador de arranque para el diagnostico.
echo "$(date '+%Y-%m-%d %H:%M:%S') boot: post-fs-data" >> "$DATA_DIR/logs/boot.log" 2>/dev/null

exit 0
