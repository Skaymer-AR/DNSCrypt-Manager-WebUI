# DNSCrypt Manager v1.1.0 — stable release

v1.1.0 adds a local DNS blocklist engine on top of the stable v1.0.0 base. It
keeps DNSCrypt Proxy as the only DNS engine: it does not integrate Rethink, add
another VPN, or use Rethink's `VpnService`.

## Highlights

- Browse the catalog in its original Security, Privacy, and Parental Control
  groups. Sections load on demand; users can select a whole category or
  individual feeds.
- Fetch feeds directly from their upstream URLs over HTTPS. The catalog keeps
  source attribution, declared categories, format, URL, and license status;
  feed contents are not bundled or executed.
- Parse domain lists, hosts files, and simple AdBlock rules that can be
  faithfully represented as DNS blocking. Normalize, validate, and deduplicate
  entries; corrupt responses and anomalous count drops retain the last valid
  cache.
- Download all compatible feeds in the background, with up to four concurrent
  transfers, reduced CPU priority, and one manifest rebuild at the end. Bulk
  download prepares caches; it **does not enable feeds or change the active DNS
  file**. Select sources and compile explicitly to apply changes.
- A prioritized personal allowlist, per-source disable controls, atomic
  replacement, and rollback of the active list.
- Configured capacity for up to 5,000,000 unique domains in the final DNS file,
  with byte limits, content validation, and free-space checks.
- A source audit based on `celzero/rethink-app`, its metadata, and upstreams
  identified directly in the code, documented in
  `docs/RETHINK_BLOCKLIST_AUDIT_ES.md`.

## Performance and known behavior

Bulk downloads can transfer substantial data, and large blocklists need CPU,
storage, and time to validate. On a phone, the WebUI may become slow or appear
stuck during a large operation. The job runs in the background at reduced CPU
priority; the active list remains the last compiled version until the user
applies and compiles changes. Automated tests verify bounded concurrency, but
do not measure every upstream's response time or DNS performance on the user's
Motorola device.

## Compatibility and scope

The user-reported physical validation covers a Motorola Edge 40 Pro (`rtwo`),
Android 16 / API 36, ARM64, KernelSU Next, and Hybrid Mount. DNSCrypt, Wi-Fi,
mobile data, hotspot, network changes, persistence, forced IPv4, and the WebUI
were tested. IPv6 was not exhaustively validated. See
`ANDROID_USER_VALIDATION_v1.1.0.md` for details and limits.

Labels such as `malware`, `spyware`, `tracking`, and `telemetry` reflect a
source's classification; they do not prove every listed domain is malicious.
False positives are possible. The module does not edit `/system/etc/hosts`,
inspect HTTPS, or replace antivirus software.

## Install and update

Install the ZIP through KernelSU Next as an update to the existing module. The
module ID remains `dnscrypt_manager`, and data migration is idempotent. New
feeds stay disabled until selected and confirmed. Verify the ZIP with the
`.sha256` file attached to this same release.
