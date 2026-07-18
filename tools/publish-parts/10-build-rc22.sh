#!/usr/bin/env bash
set -euo pipefail

git checkout -B pre-release/v0.2.0-rc2.2 "$WIP3_HEAD"
git am -3 /tmp/rc22.patch
test "$(git rev-parse HEAD)" = '4214bbab59c4b9f36d7af982f4f9a57f886adf41'

python3 - <<'PY'
from pathlib import Path
p = Path('README.md')
warning = (
    '> [!WARNING]\n'
    '> **v0.2.0-RC2.2 es una versión preliminar en pruebas.** La RC2 original está '
    'descartada. BindHosts debe permanecer desactivado y el dispositivo debe reiniciarse '
    'antes de habilitar DNSCrypt Manager; usarlos juntos puede causar pérdida de red o '
    'bootloop. En KernelSU Next puede ser necesario activar Hybrid Mount y reiniciar. '
    'La primera versión estable será v1.0.0.\n\n'
)
text = p.read_text(encoding='utf-8')
if 'v0.2.0-RC2.2 es una versión preliminar en pruebas' not in text:
    p.write_text(warning + text, encoding='utf-8')

old = Path('.github/workflows/publish-release.yml')
if old.exists():
    text = old.read_text(encoding='utf-8')
    start = text.find('on:')
    permissions = text.find('\npermissions:')
    if start >= 0 and permissions > start:
        old.write_text(text[:start] + 'on:\n  workflow_dispatch:\n' + text[permissions:], encoding='utf-8')
PY

git add README.md .github/workflows/publish-release.yml
if ! git diff --cached --quiet; then
  git commit -m 'docs(rc2.2): mark preliminary status and preserve stable v0.1 release'
fi

RC22_HEAD="$(git rev-parse HEAD)"
echo "RC22_HEAD=$RC22_HEAD" >> "$GITHUB_ENV"
grep -qx 'version=v0.2.0-RC2.2' module.prop
grep -qx 'versionCode=204' module.prop
grep -qx 'author=Skaymer AR' module.prop
grep -q 'BindHosts debe permanecer desactivado' README.md
bash tests/run-syntax-checks.sh
bash tests/smoke-test-cli.sh
bash tests/smoke-test-catalog.sh
bash tests/smoke-test-environment-v030.sh

ZIP="$RUNNER_TEMP/releases/DNSCrypt-Manager-v0.2.0-RC2.2-Preliminary.zip"
DCM_SKIP_TESTS=1 DCM_OUTPUT="$ZIP" bash tools/build-module.sh
unzip -t "$ZIP"
unzip -p "$ZIP" module.prop | tr -d '\r' | grep -qx 'version=v0.2.0-RC2.2'
unzip -p "$ZIP" module.prop | tr -d '\r' | grep -qx 'versionCode=204'
if unzip -Z1 "$ZIP" | grep -Eq '^(tests|tools|fixtures|bootstrap|\.git)/'; then
  echo 'Development files leaked into RC2.2 ZIP' >&2
  exit 1
fi
sha256sum "$ZIP" > "$ZIP.sha256"
cp /tmp/rc22.patch "$RUNNER_TEMP/releases/DNSCrypt-Manager-v0.2.0-RC2.2.patch"
cp /tmp/AUDIT_RC2.2.md "$RUNNER_TEMP/releases/AUDIT_RC2.2.md"
cp /tmp/TEST_RESULTS_RC2.2.md "$RUNNER_TEMP/releases/TEST_RESULTS_RC2.2.md"
