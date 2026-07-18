#!/usr/bin/env bash
set -euo pipefail

git config user.name 'Skaymer AR'
git config user.email 'skaymer@users.noreply.github.com'
git fetch origin main feature/security-v0.2.0 --tags
mkdir -p "$RUNNER_TEMP/releases"

cat import-assets/repair-03-1-part-*.b64 > /tmp/repair-03-1.b64
echo '57422c4bdbde19234aa9131aed496a0036cb6e5721d3ee07b0994ec7af5b8b43  /tmp/repair-03-1.b64' | sha256sum -c -
cat \
  import-assets/wip3gz-part-00 \
  import-assets/wip3gz-part-01 \
  import-assets/wip3gz-part-02 \
  import-assets/repair-03-0.b64 \
  /tmp/repair-03-1.b64 \
  import-assets/repair-03-2.b64 \
  import-assets/wip3gz-part-04 \
  import-assets/repair-05-0.b64 \
  import-assets/repair-05-1.b64 \
  import-assets/repair-05-2.b64 \
  import-assets/wip3gz-part-06 \
  import-assets/repair-07-0.b64 \
  import-assets/repair-07-1.b64 \
  import-assets/repair-07-2.b64 \
  import-assets/wip3gz-part-08 \
  import-assets/wip3gz-part-09 > /tmp/wip3.b64
base64 --decode /tmp/wip3.b64 | gzip -dc > /tmp/wip3.patch
echo '8ed021ed038d7dd7f0c0c8f5a55ff1ffbbc365087242051ded8592c7ab53efae  /tmp/wip3.patch' | sha256sum -c -
test "$(grep -c '^From ' /tmp/wip3.patch)" -eq 21

cat \
  import-assets/rc22-part00-exact-500-00.b64 \
  import-assets/rc22-part00-exact-500-01.b64 \
  import-assets/rc22-part00-exact-500-02.b64 \
  import-assets/rc22-part00-exact-500-03.b64 \
  import-assets/rc22-exact-2k-part-01.b64 \
  import-assets/rc22-exact-2k-part-02.b64 \
  import-assets/rc22-exact-2k-part-03.b64 \
  import-assets/rc22-exact-2k-part-04.b64 \
  import-assets/rc22-exact-2k-part-05.b64 > /tmp/rc22.b64
echo '06ff8d74f2c86acb1b5a6787547c48dedc304b4217b956246ec890dc4b12f42b  /tmp/rc22.b64' | sha256sum -c -
base64 --decode /tmp/rc22.b64 > /tmp/rc22.patch.gz
echo '6dc12ce25f7089156e480971f9dec76a2aa5a78ea5599662ef7dea3cda3e8301  /tmp/rc22.patch.gz' | sha256sum -c -
gzip -dc /tmp/rc22.patch.gz > /tmp/rc22.patch
echo '70e9b4a8fcbc7992575219f01c1b9ee9beae548161603ba7ce9b4eccbca4bb86  /tmp/rc22.patch' | sha256sum -c -
test "$(grep -c '^From ' /tmp/rc22.patch)" -eq 3

cat import-assets/v03-exact-2k-part-*.b64 > /tmp/v03.b64
base64 --decode /tmp/v03.b64 > /tmp/v03.patch.gz
gzip -dc /tmp/v03.patch.gz > /tmp/v03.patch
echo 'a6fb245395ebb4d93e4d46bfb26879b95def90a77b0751330affe9f03e0c869a  /tmp/v03.patch' | sha256sum -c -
test "$(grep -c '^From ' /tmp/v03.patch)" -eq 4

cp import-assets/RELEASE_NOTES_RC22.md /tmp/RELEASE_NOTES_RC22.md
cp import-assets/RELEASE_NOTES_V03.md /tmp/RELEASE_NOTES_V03.md
cp import-assets/AUDIT_RC2.2.md /tmp/AUDIT_RC2.2.md
cp import-assets/TEST_RESULTS_RC2.2.md /tmp/TEST_RESULTS_RC2.2.md

git checkout -B reconstructed/rc2-wip3 bd2e0ab28922b3ed067f4a3c183a77fca714c243
git am -3 /tmp/wip3.patch
WIP3_HEAD="$(git rev-parse HEAD)"
test "$WIP3_HEAD" = '34df8e428bb76880d1887f01ffc5ec97956a030d'
echo "WIP3_HEAD=$WIP3_HEAD" >> "$GITHUB_ENV"
