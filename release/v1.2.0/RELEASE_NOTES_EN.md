# DNSCrypt Manager Big Update v1.2.0 — stable release

v1.2.0 is the stable release of the DNSCrypt Manager module and Android app.
The RC2 candidate is promoted after the user confirmed on their Motorola Edge
40 Pro that Activity loads its counters and Lists and Settings open smoothly
again.

## Changes

- Activity processes the complete snapshot in one pass, validates the JSON,
  and keeps its counters and events even if later temporary-file cleanup fails.
- The fast path avoids searching large lists for each query while preserving
  the blocking rule and detailed information where applicable.
- Activity uses a lazy list to prevent the app from closing while scrolling
  through records.
- Lists keeps loaded data in memory; Settings creates sections on demand.
  Parsing and progress checks no longer block the interface.
- The Android app and WebUI provide Spanish and English interfaces.
- `Error` means the DNS response code was not `NOERROR`; it does not by itself
  mean the domain was blocked. Export Activity as JSON and inspect
  `return_code` to see the specific response code.

## Versions

- Android app: **0.4.2**, versionCode **10** (debug APK).
- Module: **v1.2.0**, versionCode **12003**.

## Installation

Install the module ZIP as an update through KernelSU Next, then install the
Android APK separately. Check the GitHub Actions summary to see whether its
signing certificate allows an in-place update from RC2. If Android rejects the
signature, uninstall only the app before installing the new APK; this removes
the app's private data but does not uninstall the module or remove its DNS
settings. Verify each download with the SHA-256 file attached to this release.

## Validation

CI checks validate Spanish and English resources, JVM tests, the Android build,
the module, the ZIP, and its checksums. The user's reported physical check
covers Activity loading and navigation through Lists and Settings on their
Motorola Edge 40 Pro. This does not claim exhaustive testing of every feature,
network, or device.
