#!/bin/bash
set -u
cd "$(dirname "$0")/.." || exit 1
. tests/_tp_common.sh
tp_setup
trap 'rm -rf "$TR"' EXIT
mkdir -p "$TR/cache"
export DNSCRYPT_TEST_APP_CACHE="$TR/cache"

"$SH" "$M" allowlist add example.com >/dev/null 2>&1
"$SH" "$M" set-flag query_days 7 >/dev/null 2>&1
"$SH" "$M" app-policy profile save "Viaje" "com.example.maps" >/dev/null 2>&1
mkdir -p "$TR/data/config/defaults"
printf '%s\n' 'no se incluye en la copia de preferencias' > "$TR/data/config/defaults/dnscrypt-proxy.toml"
R=$("$SH" "$M" backup --output "$TR/cache/dcm-backup-test.tar.gz" 2>&1)
[[ "$R" == *"OK: copia de configuración creada"* ]] && echo '  OK   exporta preferencias a ruta privada permitida' || { echo "  FAIL export: $R"; exit 1; }
R=$("$SH" "$M" backup inspect --input "$TR/cache/dcm-backup-test.tar.gz" 2>&1)
printf '%s\n' "$R" > "$TR/inspect.json"
python3 - "$TR/inspect.json" <<'PY' >/dev/null 2>&1
import json, sys
d=json.load(open(sys.argv[1], encoding='utf-8'))
assert d['valid'] is True and d['entry_count'] > 0
assert d['dns_config'] is True and d['allowlist'] is True
assert d['firewall_profiles'] is True and d['activity_included'] is False
PY
[ "$?" = "0" ] && echo '  OK   inspecciona el contenido antes de restaurar y confirma que no incluye actividad' || { echo "  FAIL inspect: $R"; exit 1; }
tar -tzf "$TR/cache/dcm-backup-test.tar.gz" | grep -qx 'config/dnscrypt-proxy.toml' && echo '  OK   copia la configuración DNS' || { echo '  FAIL falta TOML'; exit 1; }
tar -tzf "$TR/cache/dcm-backup-test.tar.gz" | grep -qx 'apppolicy/profiles.tsv' && echo '  OK   copia perfiles del firewall' || { echo '  FAIL faltan perfiles'; exit 1; }
tar -tzf "$TR/cache/dcm-backup-test.tar.gz" | grep -qx 'security/allowlist.txt' && echo '  OK   copia excepciones DNS' || { echo '  FAIL falta allowlist'; exit 1; }
! tar -tzf "$TR/cache/dcm-backup-test.tar.gz" | grep -q '^config/defaults/' && echo '  OK   no incluye los archivos internos sembrados en config/' || { echo '  FAIL incluyó archivos internos no restaurables'; exit 1; }

R=$("$SH" "$M" backup --output "$TR/not-private.tar.gz" 2>&1 || true)
[[ "$R" == *"ruta de copia no permitida"* ]] && echo '  OK   bloquea rutas de salida arbitrarias' || { echo "  FAIL ruta libre: $R"; exit 1; }

mkdir -p "$TR/unsafe/config"
ln -s ../../outside "$TR/unsafe/config/escape"
tar -czf "$TR/cache/dcm-backup-unsafe.tar.gz" -C "$TR/unsafe" config
R=$("$SH" "$M" backup inspect --input "$TR/cache/dcm-backup-unsafe.tar.gz" 2>&1 || true)
[[ "$R" == *"rutas no permitidas"* ]] && echo '  OK   la vista previa también rechaza enlaces simbólicos' || { echo "  FAIL inspect inseguro: $R"; exit 1; }
R=$("$SH" "$M" restore-app-backup "$TR/cache/dcm-backup-unsafe.tar.gz" 2>&1 || true)
[[ "$R" == *"rutas no permitidas"* ]] && echo '  OK   rechaza enlaces simbólicos antes de restaurar' || { echo "  FAIL archivo inseguro: $R"; exit 1; }
grep -qxF 'example.com' "$TR/data/security/allowlist.txt" && echo '  OK   archivo inseguro no modifica preferencias actuales' || { echo '  FAIL estado alterado'; exit 1; }

mkdir -p "$TR/wrong-type/config" "$TR/wrong-type/run/state.env"
cp "$TR/data/config/dnscrypt-proxy.toml" "$TR/wrong-type/config/dnscrypt-proxy.toml"
tar -czf "$TR/cache/dcm-backup-wrong-type.tar.gz" -C "$TR/wrong-type" config run
R=$("$SH" "$M" backup inspect --input "$TR/cache/dcm-backup-wrong-type.tar.gz" 2>&1 || true)
[[ "$R" == *"dañada o contiene rutas no permitidas"* ]] && echo '  OK   rechaza tipos de archivo incompatibles antes de restaurar' || { echo "  FAIL inspect tipo inválido: $R"; exit 1; }

mkdir -p "$TR/extra/config"
cp "$TR/data/config/dnscrypt-proxy.toml" "$TR/extra/config/dnscrypt-proxy.toml"
printf '%s\n' 'no debe instalarse' > "$TR/extra/config/startup.sh"
tar -czf "$TR/cache/dcm-backup-extra-file.tar.gz" -C "$TR/extra" config
R=$("$SH" "$M" restore-app-backup "$TR/cache/dcm-backup-extra-file.tar.gz" 2>&1 || true)
[[ "$R" == *"rutas no permitidas"* ]] && echo '  OK   rechaza archivos fuera del formato de copia antes de restaurar' || { echo "  FAIL archivo inesperado: $R"; exit 1; }
grep -qxF 'example.com' "$TR/data/security/allowlist.txt" && echo '  OK   copia rechazada no modifica preferencias actuales' || { echo '  FAIL estado alterado por archivo inesperado'; exit 1; }
