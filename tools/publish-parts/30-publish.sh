#!/usr/bin/env bash
set -euo pipefail

REPO="${GITHUB_REPOSITORY:-Skaymer-AR/DNSCrypt-Manager-WebUI}"
OUT="$RUNNER_TEMP/releases"
RC22_ZIP="$OUT/DNSCrypt-Manager-v0.2.0-RC2.2-Preliminary.zip"
V03_ZIP="$OUT/DNSCrypt-Manager-v0.3.0-RC1-WIP-A-Preliminary.zip"

git push --force-with-lease origin "$RC22_HEAD":refs/heads/pre-release/v0.2.0-rc2.2
git push --force-with-lease origin "$V03_HEAD":refs/heads/feature/v0.3.0-rc1
git fetch origin main
git merge-base --is-ancestor origin/main "$RC22_HEAD"
git push origin "$RC22_HEAD":refs/heads/main

git tag -f v0.2.0-rc2.2 "$RC22_HEAD"
git tag -f v0.3.0-rc1-wip-a "$V03_HEAD"
git push --force origin refs/tags/v0.2.0-rc2.2 refs/tags/v0.3.0-rc1-wip-a

gh release delete v0.2.0-rc2.2 --repo "$REPO" --yes >/dev/null 2>&1 || true
gh release create v0.2.0-rc2.2 \
  --repo "$REPO" --verify-tag --prerelease \
  --title 'DNSCrypt Manager v0.2.0-RC2.2 (Preliminary)' \
  --notes-file /tmp/RELEASE_NOTES_RC22.md \
  "$RC22_ZIP" \
  "$RC22_ZIP.sha256" \
  "$OUT/DNSCrypt-Manager-v0.2.0-RC2.2.patch" \
  "$OUT/AUDIT_RC2.2.md" \
  "$OUT/TEST_RESULTS_RC2.2.md"

gh release delete v0.3.0-rc1-wip-a --repo "$REPO" --yes >/dev/null 2>&1 || true
gh release create v0.3.0-rc1-wip-a \
  --repo "$REPO" --verify-tag --prerelease \
  --title 'DNSCrypt Manager v0.3.0-RC1-WIP-A (Preview)' \
  --notes-file /tmp/RELEASE_NOTES_V03.md \
  "$V03_ZIP" \
  "$V03_ZIP.sha256" \
  "$OUT/DNSCrypt-Manager-v0.3.0-RC1-WIP-A.patch" \
  "$OUT/WORK_PROGRESS_v0.3.md"

gh release view v0.2.0-rc2.2 --repo "$REPO" --json url,isPrerelease,assets > /tmp/verify-rc22.json
gh release view v0.3.0-rc1-wip-a --repo "$REPO" --json url,isPrerelease,assets > /tmp/verify-v03.json
python3 - <<'PY'
import json
checks = [
    ('/tmp/verify-rc22.json', 'DNSCrypt-Manager-v0.2.0-RC2.2-Preliminary.zip', 5),
    ('/tmp/verify-v03.json', 'DNSCrypt-Manager-v0.3.0-RC1-WIP-A-Preliminary.zip', 4),
]
for path, required, minimum in checks:
    with open(path, encoding='utf-8') as handle:
        data = json.load(handle)
    names = {asset['name'] for asset in data['assets']}
    assert data['isPrerelease'] is True
    assert required in names
    assert len(names) >= minimum
    print(data['url'])
PY

git fetch origin main
test "$(git show origin/main:module.prop | grep '^version=')" = 'version=v0.2.0-RC2.2'
test "$(git show origin/main:module.prop | grep '^versionCode=')" = 'versionCode=204'
echo 'Both prereleases and main were published and verified.'
