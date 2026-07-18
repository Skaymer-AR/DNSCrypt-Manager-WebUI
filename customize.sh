#!/system/bin/sh
##############################################################################
# DNSCrypt Manager - customize.sh
# Creado por Skaymer AR
# Se ejecuta durante la instalacion del modulo (Magisk / KernelSU / APatch).
#
# Variables provistas por el instalador (util_functions.sh / ksud):
#   MODPATH  -> ruta del modulo que se esta instalando
#   ARCH     -> arm | arm64 | x86 | x64
#   API      -> nivel de SDK de Android (33 = Android 13, 36 = Android 16)
#   IS64BIT  -> true/false
# Funciones disponibles: ui_print, abort, set_perm, set_perm_recursive
#
# Reglas de oro respetadas aqui:
#   - NUNCA romper la instalacion por algo recuperable (binario faltante = aviso).
#   - NUNCA pisar la configuracion del usuario en una actualizacion.
#   - Separar binarios (en el modulo) de config/datos (en /data/adb).
##############################################################################

# Directorio de datos persistente (SOBREVIVE a actualizaciones del modulo).
DATA_DIR=/data/adb/dnscrypt-manager
CONF_DIR="$DATA_DIR/config"
LOG_DIR="$DATA_DIR/logs"
BACKUP_DIR="$DATA_DIR/backups"
RUN_DIR="$DATA_DIR/run"
PERSIST_BIN_DIR="$DATA_DIR/bin"

# ---------------------------------------------------------------------------
# 0. Banner
# ---------------------------------------------------------------------------
ui_print ""
ui_print "  ####################################"
ui_print "  #        DNSCrypt Manager          #"
ui_print "  #   dnscrypt-proxy como servicio   #"
ui_print "  #      Creado por Skaymer AR       #"
ui_print "  ####################################"
ui_print ""
ui_print "  AVISO: BindHosts debe permanecer DESACTIVADO"
ui_print "  mientras DNSCrypt Manager este activo. Si usas"
ui_print "  BindHosts, desactivalo, reinicia el equipo y"
ui_print "  recien entonces continua. Usar ambos a la vez"
ui_print "  puede provocar perdida de conectividad o bootloop."
ui_print ""
ui_print "  Esta version continua EN PRUEBAS."
ui_print "  La primera version estable sera v1.0.0."
ui_print ""
# Deteccion informativa de BindHosts (no lo desactiva ni borra su carpeta).
if [ -d /data/adb/modules/bindhosts ] && [ ! -f /data/adb/modules/bindhosts/disable ] && [ ! -f /data/adb/modules/bindhosts/remove ]; then
  ui_print "  >> BindHosts parece ACTIVO: desactivalo antes de usar este modulo."
  ui_print ""
fi

# ---------------------------------------------------------------------------
# 1. Detectar gestor root (solo informativo, no bloquea)
# ---------------------------------------------------------------------------
ROOT_KIND="magisk"
if [ "$KSU" = "true" ]; then
  ROOT_KIND="kernelsu"
elif [ "$APATCH" = "true" ]; then
  ROOT_KIND="apatch"
fi
ui_print "- Gestor root detectado: $ROOT_KIND"
ui_print "- Arquitectura: ${ARCH:-desconocida}   SDK/API: ${API:-desconocido}"

# ---------------------------------------------------------------------------
# 2. Verificar arquitectura (prioridad arm64, se acepta arm de 32 bits)
# ---------------------------------------------------------------------------
case "$ARCH" in
  arm64) ABI_DIR="arm64" ;;
  arm)   ABI_DIR="arm"   ;;
  *)
    ui_print "!"
    ui_print "! Arquitectura '$ARCH' no soportada por este modulo."
    ui_print "! Este modulo provee binarios para arm64-v8a (prioridad) y armeabi-v7a."
    abort "! Instalacion cancelada."
    ;;
esac
ui_print "- Usando binarios de: bin/$ABI_DIR"

# ---------------------------------------------------------------------------
# 3. Verificar version de Android (aviso, no bloquea)
# ---------------------------------------------------------------------------
if [ -n "$API" ] && [ "$API" -lt 33 ] 2>/dev/null; then
  ui_print "!"
  ui_print "! Aviso: probado en Android 13-16 (API 33-36)."
  ui_print "! Tu API es $API. Puede funcionar, pero no esta validado."
fi

# ---------------------------------------------------------------------------
# 4. Crear estructura de datos persistente
# ---------------------------------------------------------------------------
ui_print "- Preparando almacenamiento persistente en $DATA_DIR"
mkdir -p "$CONF_DIR" "$LOG_DIR" "$BACKUP_DIR" "$RUN_DIR" "$PERSIST_BIN_DIR" \
         "$CONF_DIR/blocklists" 2>/dev/null

# ---------------------------------------------------------------------------
# 5. Sembrar configuracion por defecto SOLO si no existe (no pisar la del user)
# ---------------------------------------------------------------------------
seed_if_absent() {
  # $1 = archivo fuente en el modulo, $2 = destino persistente
  if [ -f "$2" ]; then
    ui_print "  · conservando existente: $(basename "$2")"
  else
    cp -f "$1" "$2" 2>/dev/null && ui_print "  · creado por defecto: $(basename "$2")"
  fi
}

if [ -f "$CONF_DIR/dnscrypt-proxy.toml" ]; then
  ui_print "- Configuracion existente detectada: se conserva intacta."
else
  ui_print "- Primera instalacion: sembrando configuracion por defecto."
fi
seed_if_absent "$MODPATH/config/dnscrypt-proxy.toml" "$CONF_DIR/dnscrypt-proxy.toml"
seed_if_absent "$MODPATH/config/public-resolvers.md" "$CONF_DIR/public-resolvers.md"
seed_if_absent "$MODPATH/config/relays.md" "$CONF_DIR/relays.md"

# Guardar SIEMPRE una copia "de fabrica" para el boton "restaurar por defecto".
mkdir -p "$CONF_DIR/defaults" 2>/dev/null
cp -f "$MODPATH/config/defaults/"* "$CONF_DIR/defaults/" 2>/dev/null

# Marca de version instalada (para diagnostico/actualizaciones).
grep '^version=' "$MODPATH/module.prop" | cut -d= -f2 > "$DATA_DIR/.module_version" 2>/dev/null

# ---------------------------------------------------------------------------
# 6. Binario dnscrypt-proxy: verificar presencia (NO romper si falta)
# ---------------------------------------------------------------------------
BIN_SRC="$MODPATH/bin/$ABI_DIR/dnscrypt-proxy"
if [ -f "$BIN_SRC" ] && [ -s "$BIN_SRC" ]; then
  ui_print "- Binario dnscrypt-proxy presente."
  # Copiar a la ruta persistente SOLO si el usuario no tiene ya uno propio.
  if [ ! -f "$PERSIST_BIN_DIR/dnscrypt-proxy" ]; then
    cp -f "$BIN_SRC" "$PERSIST_BIN_DIR/dnscrypt-proxy" 2>/dev/null
  fi
else
  ui_print "!"
  ui_print "! El binario dnscrypt-proxy NO esta incluido en este ZIP."
  ui_print "! El modulo se instala igual, pero el servicio no arrancara"
  ui_print "! hasta que lo agregues. Opciones:"
  ui_print "!   a) Con red en el telefono:"
  ui_print "!      su -c dnscrypt-manager fetch-binary"
  ui_print "!   b) Manual: copia el binario arm64 oficial a"
  ui_print "!      $PERSIST_BIN_DIR/dnscrypt-proxy"
  ui_print "!      y luego: su -c dnscrypt-manager fix-perms"
  touch "$DATA_DIR/.binary_missing" 2>/dev/null
fi

# ---------------------------------------------------------------------------
# 7. Detectar herramientas del sistema (aviso, no bloquea)
# ---------------------------------------------------------------------------
ui_print "- Verificando herramientas del sistema:"
check_tool() {
  if command -v "$1" >/dev/null 2>&1; then
    ui_print "  · $1: OK"
  else
    ui_print "  · $1: NO disponible ($2)"
  fi
}
check_tool iptables   "la redireccion IPv4 no funcionara"
check_tool ip6tables  "la redireccion IPv6 no funcionara"
check_tool nft        "fallback nftables no disponible"
check_tool curl       "algunas pruebas de diagnostico se limitaran"
check_tool busybox    "se usaran applets del sistema"

# ---------------------------------------------------------------------------
# 8. Permisos
# ---------------------------------------------------------------------------
ui_print "- Aplicando permisos"

# Binarios del modulo: 0755
[ -f "$MODPATH/bin/arm64/dnscrypt-proxy" ] && set_perm "$MODPATH/bin/arm64/dnscrypt-proxy" 0 0 0755
[ -f "$MODPATH/bin/arm/dnscrypt-proxy" ]   && set_perm "$MODPATH/bin/arm/dnscrypt-proxy"   0 0 0755

# CLI en system/bin: 0755 (queda en el PATH via montaje systemless)
set_perm "$MODPATH/system/bin/dnscrypt-manager" 0 0 0755

# Scripts del modulo: 0755
set_perm_recursive "$MODPATH/scripts" 0 0 0755 0755

# Scripts de ciclo de vida
for s in service.sh post-fs-data.sh boot-completed.sh uninstall.sh action.sh customize.sh; do
  [ -f "$MODPATH/$s" ] && set_perm "$MODPATH/$s" 0 0 0755
done

# Datos persistentes: binarios 0755, config sensible 0600, dirs accesibles a root
[ -f "$PERSIST_BIN_DIR/dnscrypt-proxy" ] && set_perm "$PERSIST_BIN_DIR/dnscrypt-proxy" 0 0 0755
set_perm "$CONF_DIR/dnscrypt-proxy.toml" 0 0 0600 2>/dev/null
chmod 0700 "$DATA_DIR" 2>/dev/null
chmod 0755 "$LOG_DIR" 2>/dev/null

# Contexto SELinux del binario persistente (best-effort, no rompe si falla)
if command -v chcon >/dev/null 2>&1 && [ -f "$PERSIST_BIN_DIR/dnscrypt-proxy" ]; then
  chcon u:object_r:system_file:s0 "$PERSIST_BIN_DIR/dnscrypt-proxy" 2>/dev/null
fi

# ---------------------------------------------------------------------------
# 8b. Migracion versionada v0.1.0 -> v0.2.0 (best-effort; no rompe la install)
#     La CLI resuelve common.sh/security.sh de forma relativa a $MODPATH, y en
#     modo produccion escribe en /data/adb/dnscrypt-manager (persistente). Si
#     algo falla aca, el primer boot vuelve a intentarlo desde service.sh.
# ---------------------------------------------------------------------------
if [ -x "$MODPATH/system/bin/dnscrypt-manager" ]; then
  if [ ! -f "$DATA_DIR/schema_version" ] || [ "$(cat "$DATA_DIR/schema_version" 2>/dev/null)" != "2" ]; then
    ui_print "- Migrando datos a esquema v0.2.0..."
    if sh "$MODPATH/system/bin/dnscrypt-manager" migrate >/dev/null 2>&1; then
      ui_print "  · Migracion OK (ajustes previos conservados)."
    else
      ui_print "  · Migracion se reintentara en el primer arranque."
    fi
  fi
fi

# ---------------------------------------------------------------------------
# 9. Cierre
# ---------------------------------------------------------------------------
ui_print ""
ui_print "- Instalacion base completada."
ui_print "- Tras reiniciar:"
ui_print "    · WebUI (KernelSU/APatch): abrila desde el gestor de modulos."
ui_print "    · CLI:  su -c dnscrypt-manager status"
ui_print "    · Emergencia: su -c dnscrypt-manager panic"
ui_print ""
ui_print "- Por seguridad, la REDIRECCION global arranca DESACTIVADA."
ui_print "  Activala desde la WebUI cuando confirmes que el DNS resuelve."
ui_print ""
