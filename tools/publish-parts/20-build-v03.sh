#!/usr/bin/env bash
set -euo pipefail

git checkout -B feature/v0.3.0-rc1 "$WIP3_HEAD"
git am -3 /tmp/v03.patch
test "$(git rev-parse HEAD)" = 'ab1307ffd17a0f35d6e548bec0268b1d435efdfc'

sed -i 's/^version=.*/version=v0.3.0-RC1-WIP-A/' module.prop
sed -i 's/^versionCode=.*/versionCode=300/' module.prop
sed -i 's/^description=.*/description=PREVIEW en pruebas. BindHosts debe estar desactivado; estable desde v1.0.0. KernelSU Next puede requerir Hybrid Mount./' module.prop

python3 - <<'PY'
from pathlib import Path
p = Path('README.md')
warning = (
    '> [!CAUTION]\n'
    '> **v0.3.0-RC1-WIP-A es una vista previa de desarrollo.** BindHosts debe permanecer '
    'desactivado y el dispositivo debe reiniciarse antes de habilitar DNSCrypt Manager; '
    'usarlos juntos puede causar pérdida de red o bootloop. En KernelSU Next puede ser '
    'necesario activar Hybrid Mount y reiniciar. El proyecto continúa en pruebas hasta '
    'v1.0.0.\n\n'
)
text = p.read_text(encoding='utf-8')
if 'v0.3.0-RC1-WIP-A es una vista previa de desarrollo' not in text:
    p.write_text(warning + text, encoding='utf-8')
PY

git add module.prop README.md
git commit -m 'chore(v0.3): mark Checkpoint A as development preview'
V03_HEAD="$(git rev-parse HEAD)"
echo "V03_HEAD=$V03_HEAD" >> "$GITHUB_ENV"
grep -qx 'version=v0.3.0-RC1-WIP-A' module.prop
grep -qx 'versionCode=300' module.prop
grep -q 'BindHosts debe permanecer desactivado' README.md
bash tests/run-syntax-checks.sh
bash tests/smoke-test-webui.sh
bash tests/smoke-test-i18n.sh
node tests/smoke-test-webui-v030.cjs

ZIP="$RUNNER_TEMP/releases/DNSCrypt-Manager-v0.3.0-RC1-WIP-A-Preliminary.zip"
DCM_SKIP_TESTS=1 DCM_OUTPUT="$ZIP" bash tools/build-module.sh
unzip -t "$ZIP"
unzip -p "$ZIP" module.prop | tr -d '\r' | grep -qx 'version=v0.3.0-RC1-WIP-A'
unzip -p "$ZIP" module.prop | tr -d '\r' | grep -qx 'versionCode=300'
if unzip -Z1 "$ZIP" | grep -Eq '^(tests|tools|fixtures|bootstrap|\.git)/'; then
  echo 'Development files leaked into v0.3 ZIP' >&2
  exit 1
fi
sha256sum "$ZIP" > "$ZIP.sha256"
cp /tmp/v03.patch "$RUNNER_TEMP/releases/DNSCrypt-Manager-v0.3.0-RC1-WIP-A.patch"
cp WORK_PROGRESS_v0.3.md "$RUNNER_TEMP/releases/WORK_PROGRESS_v0.3.md"
