#!/bin/bash
##############################################################################
# tests/smoke-test-i18n.sh  —  Creado por Skaymer AR
# Verifica el sistema i18n (EN/ES) de la WebUI v0.3.0-RC1:
#  - JSON valido; conjuntos de claves identicos (sin faltantes ni extra);
#  - placeholders compatibles por clave ({x} y %s);
#  - toda referencia data-i18n* del HTML apunta a una clave existente;
#  - sin claves huerfanas (definidas y nunca usadas) — advertencia dura.
##############################################################################
set -u
cd "$(dirname "$0")/.." || exit 1
PY="$(command -v python3)"; [ -n "$PY" ] || { echo "FATAL: falta python3"; exit 99; }
PASS=0; FAILN=0
ok(){ PASS=$((PASS+1)); printf '  OK   %s\n' "$1"; }
bad(){ FAILN=$((FAILN+1)); printf '  FAIL %s\n' "$1"; }

EN=webroot/i18n/en.json; ES=webroot/i18n/es.json
"$PY" -c "import json;json.load(open('$EN'))" 2>/dev/null && ok "en.json es JSON valido" || bad "en.json invalido"
"$PY" -c "import json;json.load(open('$ES'))" 2>/dev/null && ok "es.json es JSON valido" || bad "es.json invalido"

"$PY" - "$EN" "$ES" webroot > /tmp/i18n.out 2>&1 << 'PYEOF'
import json, sys, re, os, glob
en_p, es_p, webroot = sys.argv[1], sys.argv[2], sys.argv[3]
en = json.load(open(en_p)); es = json.load(open(es_p))
ek, sk = set(en), set(es)
fails = []
missing = ek - sk; extra = sk - ek
if missing: fails.append("ES faltan claves: " + ", ".join(sorted(missing)))
if extra:   fails.append("ES claves extra: " + ", ".join(sorted(extra)))
def ph(s):
    return set(re.findall(r'\{[a-zA-Z0-9_]+\}', s)) | set(re.findall(r'%[sd]', s))
ph_mismatch = []
for k in ek & sk:
    if ph(en[k]) != ph(es[k]): ph_mismatch.append(k)
if ph_mismatch: fails.append("placeholders incompatibles en: " + ", ".join(sorted(ph_mismatch)))
html = ""
for f in glob.glob(os.path.join(webroot, "*.html")):
    html += open(f, encoding="utf-8").read()
refs = set(re.findall(r'data-i18n(?:-ph|-aria)?="([^"]+)"', html))
dangling = refs - ek
if dangling: fails.append("referencias HTML sin clave: " + ", ".join(sorted(dangling)))
js = ""
for f in glob.glob(os.path.join(webroot, "js", "*.js")):
    js += open(f, encoding="utf-8").read()
used = set(refs)
used |= set(re.findall(r"\bt\(\s*['\"]([^'\"]+)['\"]", js))
used |= set(re.findall(r"I18N\.t\(\s*['\"]([^'\"]+)['\"]", js))
orphan = ek - used
print("missing=%d" % len(missing))
print("extra=%d" % len(extra))
print("ph=%d" % len(ph_mismatch))
print("dangling=%d" % len(dangling))
print("orphan=%d" % len(orphan))
for f in fails: print("FAIL::" + f)
if orphan: print("WARN::claves aun no usadas en UI (%d): %s" % (len(orphan), ", ".join(sorted(list(orphan))[:8]) + (" ..." if len(orphan)>8 else "")))
PYEOF
grep -E '^(FAIL|WARN)::' /tmp/i18n.out | sed 's/^FAIL::/  [detalle] /; s/^WARN::/  [aviso] /'
# Convertir el resultado del bloque python en OK/FAIL de la suite
if grep -q "^missing=0" /tmp/i18n.out && grep -q "^extra=0" /tmp/i18n.out; then ok "EN y ES tienen el mismo conjunto de claves"; else bad "conjuntos de claves difieren"; fi
grep -q "^ph=0" /tmp/i18n.out && ok "placeholders compatibles por clave" || bad "placeholders incompatibles"
grep -q "^dangling=0" /tmp/i18n.out && ok "toda referencia data-i18n del HTML existe" || bad "referencias data-i18n colgantes"
rm -f /tmp/i18n.out
echo ""
echo "Resumen i18n: $PASS OK, $FAILN FAIL"
[ "$FAILN" -eq 0 ] && exit 0 || exit 1
