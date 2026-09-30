# DNSCrypt Manager Big Update 1.2.0-rc1

**Pre-release candidate.** v1.1.0 remains the stable version until this
candidate is physically tested on the Motorola Edge 40 Pro (`rtwo`/RETAR,
Android 16). CI checks do not count as a phone test.

## Changes

- Activity now gives every lazy-list row a unique key. Repeated queries with
  the same domain, result, and second no longer collide while scrolling.
- The Android app is available in Spanish and English. It follows the phone's
  language; Android 13 or later also lets users select a per-app language.
- The WebUI is available in Spanish and English, keeps a manual language
  choice, and follows the browser language when no preference has been saved.
- Dynamic action, validation, and event-log messages have also been translated.
- The RC8 Activity snapshot and its complete window of up to 200 events remain
  in place. The RC6 fast path avoids searching large DNS lists for each event
  and preserves the blocking rule.

## Files

- `DNSCrypt-Manager-Android-v0.4.0-debug.apk` — Android 0.4.0, versionCode 8.
- `DNSCrypt-Manager-v1.2.0-rc1.zip` — module v1.2.0-rc1, versionCode 12001.
- Both binaries include SHA-256 files. The workflow compares the APK
  certificate with the latest published APK and records the result in its
  summary.

## Installation and validation

Install the module ZIP and APK separately. This remains a pre-release until
Activity has been checked on the Motorola for successful loading and scrolling
without closing the app. This release does not claim to be installed or
physically tested.

The JVM regression test verifies that identical events receive distinct keys.
CI builds the APK, runs the module checks, and validates translations. A CI
build does not replace the physical test.
