#!/bin/bash
##############################################################################
# tests/run-syntax-checks.sh
#
# Chequeos ESTATICOS (sin ejecutar el daemon ni tocar red/firewall real):
#   - bash -n / dash -n sobre todos los scripts shell del modulo
#   - node --check sobre todo el JS de la WebUI
#   - tomllib sobre el TOML por defecto y su copia en defaults/
#   - parser HTML real (Python html.parser) + deteccion de ids duplicados
#   - balance de llaves y variables --custom en CSS
#   - referencias cruzadas: ids que usa app.js deben existir en index.html;
#     todo DCM.run('x') debe tener su 'x' definido en api.js COMMANDS
#
# Uso:  bash tests/run-syntax-checks.sh   (desde la raiz del modulo)
# Exit: 0 si todo paso, 1 si algo fallo.
##############################################################################
set -u
cd "$(dirname "$0")/.." || exit 1
ROOT="$(pwd)"
FAIL=0
SCRATCH="$(mktemp -d /tmp/dcm-syntax-check.XXXXXX)"
trap 'rm -rf "$SCRATCH"' EXIT

pass() { printf '  OK   %s\n' "$1"; }
fail() { printf '  FAIL %s\n' "$1"; FAIL=1; }

echo "=== 1) Sintaxis shell de PRODUCCION (sh -n primero: /bin/sh es dash en" 
echo "       este host, el POSIX real mas cercano al /system/bin/sh de Android;" 
echo "       bash -n se suma como red de seguridad adicional) ==="
SHELL_FILES=(
  customize.sh post-fs-data.sh service.sh boot-completed.sh uninstall.sh action.sh
  scripts/backup.sh scripts/common.sh scripts/validate-binary.sh scripts/redirect.sh
  scripts/remove-redirect.sh scripts/restart.sh scripts/restore.sh scripts/start.sh
  scripts/stop.sh scripts/test-dns.sh scripts/security.sh scripts/catalog.sh
  system/bin/dnscrypt-manager
  META-INF/com/google/android/update-binary
)
for f in "${SHELL_FILES[@]}"; do
  if [ ! -f "$f" ]; then fail "$f (NO EXISTE)"; continue; fi
  if sh -n "$f" 2>"$SCRATCH/synerr1" && bash -n "$f" 2>"$SCRATCH/synerr2"; then
    pass "$f"
  else
    fail "$f"; cat "$SCRATCH/synerr1" "$SCRATCH/synerr2" >&2
  fi
done

echo
echo "=== 1b) Sintaxis shell de TESTS (son #!/bin/bash a proposito: bash -n) ==="
for f in tests/*.sh tests/fixtures/fake-firewall-bin/iptables tests/fixtures/fake-firewall-bin/nft; do
  [ -f "$f" ] || continue
  if bash -n "$f" 2>"$SCRATCH/synerr1b"; then pass "$f"; else fail "$f"; cat "$SCRATCH/synerr1b" >&2; fi
done

echo
echo "=== 2) Sintaxis JS (node --check) ==="
for f in webroot/js/*.js tests/fixtures/webui-harness.cjs; do
  [ -f "$f" ] || continue
  if node --check "$f" 2>"$SCRATCH/synerr3"; then pass "$f"; else fail "$f"; cat "$SCRATCH/synerr3" >&2; fi
done

echo
echo "=== 3) TOML (tomllib real) ==="
if python3 -c "
import tomllib
for f in ['config/dnscrypt-proxy.toml', 'config/defaults/dnscrypt-proxy.toml']:
    d = tomllib.load(open(f, 'rb'))
    assert 'listen_addresses' in d and d['listen_addresses'], f'{f}: falta listen_addresses'
    assert 'static' in d and d['static'], f'{f}: falta [static]'
print('  claves static:', sorted(d['static']))
" 2>"$SCRATCH/synerr4"; then pass "config/dnscrypt-proxy.toml + defaults/"; else fail "TOML"; cat "$SCRATCH/synerr4" >&2; fi

echo
echo "=== 4) HTML (parser real, no regex) ==="
python3 << 'PYEOF' || FAIL_HTML=1
from html.parser import HTMLParser
import re, sys

VOID = {"area","base","br","col","embed","hr","img","input","link","meta","source","track","wbr"}

class Checker(HTMLParser):
    def __init__(self):
        super().__init__(); self.stack = []; self.errors = []
    def handle_starttag(self, tag, attrs):
        if tag not in VOID: self.stack.append(tag)
    def handle_endtag(self, tag):
        if tag in VOID: return
        if not self.stack or self.stack[-1] != tag:
            self.errors.append(f"cierre inesperado </{tag}>")
        else:
            self.stack.pop()

html = open("webroot/index.html", encoding="utf-8").read()
c = Checker(); c.feed(html)
if c.stack: c.errors.append(f"tags sin cerrar: {c.stack}")
ids = re.findall(r'id="([^"]+)"', html)
dups = {i for i in ids if ids.count(i) > 1}
if dups: c.errors.append(f"ids duplicados: {dups}")
if c.errors:
    print("  FAIL webroot/index.html:")
    for e in c.errors: print("    -", e)
    sys.exit(1)
else:
    print(f"  OK   webroot/index.html ({len(ids)} ids, arbol balanceado)")
PYEOF
[ "${FAIL_HTML:-0}" = "1" ] && FAIL=1

echo
echo "=== 5) CSS (balance de llaves + variables) ==="
python3 << 'PYEOF' || FAIL=1
import re, sys
css = open("webroot/css/style.css", encoding="utf-8").read()
o, cl = css.count("{"), css.count("}")
ok = (o == cl)
print(f"  {'OK  ' if ok else 'FAIL'} llaves: {o} abiertas / {cl} cerradas")
defined = set(re.findall(r'(--[a-zA-Z0-9-]+)\s*:', css))
used = set(re.findall(r'var\((--[a-zA-Z0-9-]+)\)', css))
missing = used - defined
missing_str = str(missing) if missing else "ninguna"
ok2 = not missing
print(f"  {'OK  ' if ok2 else 'FAIL'} variables usadas sin definir: {missing_str}")
sys.exit(0 if (ok and ok2) else 1)
PYEOF

echo
echo "=== 6) Referencias cruzadas JS <-> HTML <-> api.js ==="
python3 << 'PYEOF' || FAIL=1
import re, sys
html = open("webroot/index.html", encoding="utf-8").read()
app  = open("webroot/js/app.js", encoding="utf-8").read()
api  = open("webroot/js/api.js", encoding="utf-8").read()

html_ids = set(re.findall(r'id="([^"]+)"', html))
js_ids = set(re.findall(r"\$\('([^']+)'\)", app))
missing_ids = js_ids - html_ids

run_calls = set(re.findall(r"DCM\.run\('([^']+)'\)", app))
commands_keys = set(re.findall(r'^\s*(\w+):\s*CLI', api, re.M))
missing_cmds = run_calls - commands_keys

ok = not missing_ids and not missing_cmds
print(f"  {'OK  ' if not missing_ids else 'FAIL'} ids ausentes en HTML: {missing_ids or 'ninguno'}")
print(f"  {'OK  ' if not missing_cmds else 'FAIL'} DCM.run(...) sin comando en api.js: {missing_cmds or 'ninguno'}")
sys.exit(0 if ok else 1)
PYEOF

echo
echo "=== 7) Ningun fixture debe estar entre los archivos destinados al ZIP ==="
python3 << 'PYEOF' || FAIL=1
import os, sys

EXCLUDE_DIRS = {"tests", "tools", ".git"}
FIXTURE_MARKER = "ARCHIVO DE PRUEBA"

installable = []
for root, dirs, files in os.walk("."):
    dirs[:] = [d for d in dirs if d not in EXCLUDE_DIRS]
    parts = root.split(os.sep)
    if any(p in EXCLUDE_DIRS for p in parts):
        continue
    for f in files:
        installable.append(os.path.join(root, f))

bad = []
for p in installable:
    if "/tests/" in p or p.startswith("./tests/") or "/tools/" in p or p.startswith("./tools/"):
        bad.append((p, "ruta dentro de tests/ o tools/"))
        continue
    try:
        with open(p, "rb") as fh:
            head = fh.read(4096)
        if FIXTURE_MARKER.encode() in head:
            bad.append((p, "contiene el marcador de fixture"))
    except Exception:
        pass

if bad:
    print(f"  FAIL: {len(bad)} archivo(s) de fixture colarian en el instalable:")
    for p, why in bad:
        print(f"    - {p} ({why})")
    sys.exit(1)
else:
    print(f"  OK   {len(installable)} archivos instalables revisados, ninguno es un fixture")
PYEOF

if [ "$FAIL" -eq 0 ]; then
  echo "=== RESULTADO: TODOS los chequeos de sintaxis pasaron ==="
else
  echo "=== RESULTADO: HAY FALLOS (ver arriba) ==="
fi
exit "$FAIL"
