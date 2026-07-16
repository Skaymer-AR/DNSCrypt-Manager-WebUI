#!/bin/bash
##############################################################################
# tests/smoke-test-catalog.sh   —  Creado por Skaymer AR
#
# Bateria funcional del CATALOGO RC2 (motor por metadatos), el importador
# BindHosts, los controles de servicio y el estado runtime persistente.
# AISLADA: monta el modulo y un DATA_DIR temporal, usa file:// (permitido solo
# bajo DNSCRYPT_TEST_MODE=1). No levanta el daemon: prueba las funciones del
# pipeline directamente (cat_update_one, cat_append_active, svc_*, bindhosts) y
# algunos comandos de solo lectura via CLI. Determinista.
#
# Uso:  bash tests/smoke-test-catalog.sh
# Exit: 0 todo OK, 1 fallo, 99 arnes roto.
##############################################################################
set -u
cd "$(dirname "$0")/.." || exit 1
SRC_ROOT="$(pwd)"
SH_BIN="$(command -v sh)"; PY="$(command -v python3)"
[ -n "$SH_BIN" ] || { echo "FATAL: falta sh" >&2; exit 99; }
[ -n "$PY" ] || { echo "FATAL: falta python3" >&2; exit 99; }

TR="$(mktemp -d /tmp/dcm-cat-test.XXXXXX)" || exit 99
export DNSCRYPT_TEST_MODE=1
export DNSCRYPT_TEST_ROOT="$TR"
export DNSCRYPT_TEST_DATA_DIR="$TR/data"
export DNSCRYPT_TEST_MODDIR="$TR/mod"
export DNSCRYPT_TEST_SHELL="$SH_BIN"
M="$TR/mod/system/bin/dnscrypt-manager"
DATA="$TR/data"

PASS=0; FAILN=0
ok()  { PASS=$((PASS+1)); printf '  OK   %s\n' "$1"; }
bad() { FAILN=$((FAILN+1)); printf '  FAIL %s\n' "$1"; }

( sleep 200; echo "FATAL: watchdog 200s" >&2; kill -TERM $$ 2>/dev/null ) & WD=$!
cleanup() { kill "$WD" 2>/dev/null; rm -rf "$TR"; }
trap 'cleanup; exit 99' INT TERM
trap cleanup EXIT

# --- montar modulo aislado (sin tests/tools) + binario fake + config ---
mkdir -p "$DATA/bin" "$DATA/config"
cp -a "$SRC_ROOT/." "$TR/mod/"
rm -rf "$TR/mod/tests" "$TR/mod/tools" "$TR/mod/.git"
cp "$SRC_ROOT/tests/fixtures/fake-dnscrypt-proxy" "$DATA/bin/dnscrypt-proxy" 2>/dev/null
chmod 0755 "$DATA/bin/dnscrypt-proxy" 2>/dev/null
cp "$SRC_ROOT/config/dnscrypt-proxy.toml" "$DATA/config/dnscrypt-proxy.toml"

# --- fixtures de listas ---
FX="$TR/fx"; mkdir -p "$FX"
printf 'ads1.tracker.net\nads2.tracker.net\nmetrics.tracker.net\nAD1.TRACKER.NET\nbeacon.tracker.net\n' > "$FX/domains.txt"
printf '0.0.0.0 h1.bad.net\n0.0.0.0 h2.bad.net\n127.0.0.1 localhost\n! c\n' > "$FX/hosts.txt"
printf '||abp1.bad.net^\n||abp2.bad.net^\n@@||ok.net^\nbad.net##.ad\n||path.net/x^\n||opt.net^$third-party\n' > "$FX/abp.txt"

# helper: correr la CLI en el shell de prueba
cli() { "$SH_BIN" "$M" "$@"; }
# helper: cargar libs y ejecutar una expresion en el contexto del modulo
inlib() { ( cd "$TR/mod" && "$SH_BIN" -c ". scripts/common.sh 2>/dev/null; . scripts/security.sh 2>/dev/null; . scripts/catalog.sh 2>/dev/null; $1" ); }

echo "=== Preparando entorno en $TR ==="
cli migrate >/dev/null 2>&1

# =====================================================================
echo "== A. Generador y paridad JSON/TSV (dev/CI) =="
"$PY" tools/build-catalog.py --check >/dev/null 2>&1 && ok "A1 catalogo reproducible (--check)" || bad "A1 catalogo NO reproducible"
"$PY" -c "import json;json.load(open('config/catalog/blocklists.json'))" 2>/dev/null && ok "A2 blocklists.json es JSON valido" || bad "A2 JSON invalido"
"$PY" -c "import json;json.load(open('config/catalog/service-controls.json'))" 2>/dev/null && ok "A3 service-controls.json valido" || bad "A3 JSON servicios invalido"
# IDs unicos + sin tabs raros en TSV
_dups=$(awk -F'\t' '!/^#/{print $1}' config/catalog/blocklists.index.tsv | sort | uniq -d | wc -l | tr -d ' ')
[ "$_dups" = "0" ] && ok "A4 IDs unicos en TSV" || bad "A4 IDs duplicados: $_dups"
_cols=$(awk -F'\t' '!/^#/{print NF}' config/catalog/blocklists.index.tsv | sort -u | tr '\n' ' ')
[ "$_cols" = "19 " ] && ok "A5 TSV tiene 19 columnas consistentes" || bad "A5 columnas inconsistentes: $_cols"
# URLs unicas
_udups=$(awk -F'\t' '!/^#/{print $8}' config/catalog/blocklists.index.tsv | sort | uniq -d | wc -l | tr -d ' ')
[ "$_udups" = "0" ] && ok "A6 sin URLs duplicadas" || bad "A6 URLs duplicadas: $_udups"

# =====================================================================
echo "== B. index sincronizado + list/info (solo lectura) =="
[ -f "$DATA/catalog/blocklists.index.tsv" ] && ok "B1 index copiado al dispositivo por migrate" || bad "B1 index no sincronizado"
cli catalog list --recommended > "$TR/o" 2>&1
grep -q "recomendada" "$TR/o" && ok "B2 list --recommended muestra recomendadas" || bad "B2 list recomendadas"
cli catalog list --archived > "$TR/o" 2>&1
grep -qi "antipopads\|ARCHIVADA" "$TR/o" && ok "B3 list --archived muestra archivadas" || bad "B3 list archivadas"
cli catalog info dandelionsprout_antimalware > "$TR/o" 2>&1
grep -q "Alternate%20versions%20Anti-Malware" "$TR/o" && ok "B4 URL de DandelionSprout corregida (completa)" || bad "B4 URL DandelionSprout"
cli catalog info hagezi_multi_pro > "$TR/o" 2>&1
grep -q "estado up." "$TR/o" && grep -q "estado local" "$TR/o" && ok "B5 info separa estado upstream vs runtime" || bad "B5 estados no separados"
# adult_advertising mensaje literal
cli catalog list --category adult_advertising > "$TR/o" 2>&1
grep -q "No se encontro una fuente mantenida y verificable" "$TR/o" && ok "B6 adult_advertising: mensaje literal" || bad "B6 adult_advertising"

# =====================================================================
echo "== C. Descarga/validacion + estado runtime persistente =="
# reescribir rc1_urlhaus -> file:// domains
awk -F'\t' -v OFS='\t' -v u="file://$FX/domains.txt" '$1=="rc1_urlhaus"{$7="domains";$8=u}1' "$DATA/catalog/blocklists.index.tsv" > "$TR/t" && mv "$TR/t" "$DATA/catalog/blocklists.index.tsv"
SHA_JSON_BEFORE=$(sha256sum config/catalog/blocklists.json | cut -d' ' -f1)
inlib "cat_update_one rc1_urlhaus" > "$TR/o" 2>&1
grep -q "OK (rc1_urlhaus): 5 dominios" "$TR/o" && ok "C1 descarga+valida+dedupe+minusculas (5 dominios)" || bad "C1 update ($(cat $TR/o))"
grep -q "^rc1_urlhaus	verified" "$DATA/catalog/source-status.tsv" && ok "C2 verified registrado en source-status.tsv" || bad "C2 verified no persistido"
SHA_JSON_AFTER=$(sha256sum config/catalog/blocklists.json | cut -d' ' -f1)
[ "$SHA_JSON_BEFORE" = "$SHA_JSON_AFTER" ] && ok "C3 catalogo generado inmutable (SHA JSON intacto)" || bad "C3 catalogo mutado"
# update del modulo no borra historial (source-status vive en DATA)
cli migrate >/dev/null 2>&1
grep -q "verified" "$DATA/catalog/source-status.tsv" && ok "C4 historial verified sobrevive re-migracion" || bad "C4 historial perdido"
# descarga fallida no destruye la ultima lista valida
LSHA1=$(sha256sum "$DATA/catalog/cache/rc1_urlhaus.list" | cut -d' ' -f1)
awk -F'\t' -v OFS='\t' -v u="file://$FX/noexiste.txt" '$1=="rc1_urlhaus"{$8=u}1' "$DATA/catalog/blocklists.index.tsv" > "$TR/t" && mv "$TR/t" "$DATA/catalog/blocklists.index.tsv"
inlib "cat_update_one rc1_urlhaus" > "$TR/o" 2>&1
LSHA2=$(sha256sum "$DATA/catalog/cache/rc1_urlhaus.list" | cut -d' ' -f1)
[ "$LSHA1" = "$LSHA2" ] && ok "C5 descarga fallida preserva ultima lista valida" || bad "C5 lista destruida"
grep -q "^rc1_urlhaus	download_failed" "$DATA/catalog/source-status.tsv" && ok "C6 fallo registrado como download_failed" || bad "C6 estado de fallo"
_ls=$(awk -F'\t' '$1=="rc1_urlhaus"{print $4}' "$DATA/catalog/source-status.tsv")
[ -n "$_ls" ] && [ "$_ls" -gt 0 ] 2>/dev/null && ok "C7 last_success preservado tras fallo" || bad "C7 last_success perdido"
# restaurar URL buena para el resto
awk -F'\t' -v OFS='\t' -v u="file://$FX/domains.txt" '$1=="rc1_urlhaus"{$8=u}1' "$DATA/catalog/blocklists.index.tsv" > "$TR/t" && mv "$TR/t" "$DATA/catalog/blocklists.index.tsv"

# =====================================================================
echo "== D. Formatos: hosts / domains / ABP =="
_h=$(inlib "sec_parse_domains '$FX/hosts.txt' hosts '$TR/hout'; cat '$TR/hout' | wc -l" 2>/dev/null | tail -1 | tr -d ' ')
[ "$_h" = "2" ] && ok "D1 hosts: 2 dominios (localhost/comentarios ignorados)" || bad "D1 hosts parse ($_h)"
_a=$(inlib "cat_abp_extract '$FX/abp.txt' '$TR/aout'" 2>/dev/null | tail -1 | tr -d ' ')
[ "$_a" = "2" ] && ok "D2 ABP: solo 2 reglas de dominio (excepcion/cosmetica/path/opciones ignoradas)" || bad "D2 ABP extract ($_a)"
inlib "cat_detect_format '$FX/abp.txt'" 2>/dev/null | grep -q abp && ok "D3 deteccion de formato ABP" || bad "D3 detect abp"
inlib "cat_detect_format '$FX/hosts.txt'" 2>/dev/null | grep -q hosts && ok "D4 deteccion de formato hosts" || bad "D4 detect hosts"

# =====================================================================
echo "== E. Compilacion (merge a escala, sin daemon) =="
# habilitar rc1_urlhaus + blacklist manual + verificar cat_append_active
inlib "cat_update_one rc1_urlhaus >/dev/null 2>&1; cat_enable rc1_urlhaus; echo manual.black.net >> \"\$CAT_BLACKLIST\"; cat_append_active '$TR/merged'; sort -u '$TR/merged' -o '$TR/merged'; cat '$TR/merged'" > "$TR/mo" 2>&1
grep -qx "ads1.tracker.net" "$TR/mo" && ok "E1 merge incluye dominios de fuente activa" || bad "E1 merge fuente"
grep -qx "manual.black.net" "$TR/mo" && ok "E2 merge incluye blacklist manual" || bad "E2 merge blacklist"
grep -qx "ad1.tracker.net" "$TR/mo" && ok "E3 merge normaliza a minusculas + dedupe" || bad "E3 merge normaliza"
# escala: generar 200k dominios y verificar dedupe por lote (rapido)
"$PY" -c "
import random
random.seed(1)
with open('$TR/big.txt','w') as f:
    for i in range(200000): f.write('d%d.scale.net\n'%(i%150000))
" 
_before=$(wc -l < "$TR/big.txt" | tr -d ' ')
_after=$(sort -u "$TR/big.txt" | wc -l | tr -d ' ')
[ "$_before" = "200000" ] && [ "$_after" = "150000" ] && ok "E4 dedupe por lote (sort -u) 200k->150k" || bad "E4 dedupe escala ($_before/$_after)"

# =====================================================================
echo "== F. Conflictos por metadatos =="
# activar pro y proplus (proplus supersedes pro) -> reporta sustitucion
inlib "cat_enable hagezi_multi_pro; cat_enable hagezi_multi_proplus; cat_conflicts_report" > "$TR/co" 2>&1
grep -qi "sustitucion\|redundante" "$TR/co" && ok "F1 detecta sustitucion/redundancia entre activas" || bad "F1 conflictos metadatos"

# =====================================================================
echo "== G. Importador BindHosts (dry-run seguro) =="
BH="$TR/bh"; mkdir -p "$BH"
printf 'https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts\nhttps://raw.githubusercontent.com/StevenBlack/hosts/master/hosts\nhttps://raw.githubusercontent.com/AdroitAdorKhan/antipopads-re/master/formats/hosts.txt\nhttps://mi-lista.net/l.txt\nhttp://insegura.net/x.txt\n' > "$BH/sources.txt"
printf 'ads.tracker.net\nhttps://click.redditmail.com\nevil.net; rm -rf /\nno_dominio\n' > "$BH/blacklist.txt"
printf 'midominio.org\nhttps://dns.nextdns.io/83d4a9\ns.youtube.com\n' > "$BH/whitelist.txt"
printf '0.0.0.0 bloquear.net\n192.168.1.5 real.net\n0.0.0.0 s.youtube.com.domain.name\n' > "$BH/custom.txt"
BLK_BEFORE=$(wc -l < "$DATA/catalog/blacklist.txt" 2>/dev/null | tr -d ' ')
cli import-bindhosts "$BH" --dry-run > "$TR/bo" 2>&1
grep -q "duplicadas:1" "$TR/bo" && ok "G1 detecta StevenBlack duplicado" || bad "G1 dup StevenBlack"
grep -q "archivadas             : 1" "$TR/bo" && ok "G2 detecta fuente archivada (antipopads-re)" || bad "G2 archivada"
grep -q "rotas/invalidas        : 1" "$TR/bo" && ok "G3 detecta URL rota (http)" || bad "G3 rota"
grep -q "s.youtube.com.domain.name" "$TR/bo" && ok "G4 marca sospechoso s.youtube.com.domain.name" || bad "G4 sospechoso"
BLK_AFTER=$(wc -l < "$DATA/catalog/blacklist.txt" 2>/dev/null | tr -d ' ')
[ "$BLK_BEFORE" = "$BLK_AFTER" ] && ok "G5 dry-run no modifica nada" || bad "G5 dry-run modifico ($BLK_BEFORE->$BLK_AFTER)"

# =====================================================================
echo "== H. Controles de servicio (YouTube) + reloj =="
cli service set youtube_no_history 1h > "$TR/so" 2>&1
grep -q "Control experimental de mejor esfuerzo" "$TR/so" && ok "H1 set muestra texto obligatorio" || bad "H1 texto obligatorio"
inlib "svc_is_blocking youtube_no_history && echo BLOCK" 2>/dev/null | grep -q BLOCK && ok "H2 modo 1h bloquea" || bad "H2 no bloquea"
# reloj: forzar block_until en el pasado -> expira -> modo normal
"$SH_BIN" -c "awk -F'\t' -v OFS='\t' '\$1==\"youtube_no_history\"{\$3=\"100\"}1' '$DATA/catalog/service-state.tsv' > '$TR/ss' && mv '$TR/ss' '$DATA/catalog/service-state.tsv'"
inlib "svc_current_mode youtube_no_history" 2>/dev/null | grep -qx normal && ok "H3 modo temporal EXPIRA al pasar el reloj" || bad "H3 expiracion"
# perm persiste
cli service set youtube_no_history perm >/dev/null 2>&1
inlib "svc_current_mode youtube_no_history" 2>/dev/null | grep -qx perm && ok "H4 modo permanente persiste" || bad "H4 perm"
# modo invalido
cli service set youtube_no_history 5m > "$TR/so" 2>&1
grep -qi "modo invalido" "$TR/so" && ok "H5 modo invalido rechazado" || bad "H5 modo invalido"
# conflicto allowlist: NO modifica datos del usuario
cli allowlist add s.youtube.com >/dev/null 2>&1
cli service conflicts > "$TR/so" 2>&1
grep -qi "conflicto" "$TR/so" && ok "H6 conflicto allowlist vs control reportado" || bad "H6 conflicto"
# normal no borra la entrada manual de allowlist
cli service set youtube_no_history normal >/dev/null 2>&1
cli allowlist list 2>/dev/null | grep -qi "s.youtube.com" && ok "H7 modo normal NO borra allowlist manual del usuario" || bad "H7 borro allowlist"
# el control usa su propio estado, no toca blacklist manual
grep -q "s.youtube.com" "$DATA/catalog/blacklist.txt" 2>/dev/null && bad "H8 control escribio en blacklist del usuario" || ok "H8 control no toca blacklist manual"

echo ""
echo "Resumen catalogo: $PASS OK, $FAILN FAIL"
[ "$FAILN" -eq 0 ] && exit 0 || exit 1
