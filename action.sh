#!/system/bin/sh
##############################################################################
# DNSCrypt Manager - action.sh
# Se dispara con el boton "Accion" del gestor de modulos (Magisk / KernelSU).
# Util sobre todo en Magisk, que no tiene WebUI nativa: alterna el servicio
# de forma rapida y segura, mostrando el resultado con ui_print/echo.
##############################################################################

MODDIR=${0%/*}
CLI="/system/bin/dnscrypt-manager"
[ -x "$CLI" ] || CLI="$MODDIR/system/bin/dnscrypt-manager"

# run_cli: ver definicion y justificacion completa en uninstall.sh.
run_cli() {
  if [ "${DNSCRYPT_TEST_MODE:-0}" = "1" ]; then
    "${DNSCRYPT_TEST_SHELL:-sh}" "$CLI" "$@"
  else
    "$CLI" "$@"
  fi
}

echo ""
echo "=== DNSCrypt Manager ==="

if [ ! -x "$CLI" ]; then
  echo "! No se encuentra la CLI dnscrypt-manager."
  exit 1
fi

if run_cli is-running >/dev/null 2>&1; then
  echo "- Servicio corriendo. Deteniendo..."
  run_cli redirect remove 2>/dev/null
  run_cli restore-network 2>/dev/null
  run_cli stop
  echo "- Detenido. Redireccion retirada y red restaurada."
else
  echo "- Servicio detenido. Arrancando..."
  run_cli start
  sleep 2
  if run_cli is-listening >/dev/null 2>&1; then
    echo "- dnscrypt-proxy escuchando en $(run_cli get listen 2>/dev/null)"
    echo "- (La redireccion global se controla desde la WebUI o con:"
    echo "   su -c dnscrypt-manager redirect apply )"
  else
    echo "! El proxy no logro escuchar. Revisa:"
    echo "   su -c dnscrypt-manager logs"
  fi
fi

echo "- Estado:"
run_cli status 2>/dev/null
echo "========================"
exit 0
