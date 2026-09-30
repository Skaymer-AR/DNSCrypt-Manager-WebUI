# DNSCrypt Manager Big Update 1.2.0 RC2

This candidate fixes the delay and stutters reported when opening Lists and Settings on Android.

## Changes

- Lists keeps the loaded catalog in memory, avoids repeating module queries whenever the screen is reopened, and computes filtered results only when the query or selection changes.
- Activity, catalog, download progress, and allowlist responses are parsed away from the UI thread. Progress checks no longer overlap.
- Settings lazily composes its sections so the first content appears sooner.
- Keeps RC1's Spanish/English translations and Activity scrolling fix.

## Versions

- Android app: 0.4.1, versionCode 9.
- Module: v1.2.0-rc2, versionCode 12002.
- v1.1.0 remains the stable release. This pre-release needs navigation testing on the Motorola Edge 40 Pro before it can be marked stable.

The workflow compares the APK certificate with RC1's Android 0.4.0 APK. Check the GitHub Actions summary to confirm whether Android can install it over the existing app; if the signing certificates differ, uninstall only the app before installing the new APK. The module and its settings are separate.
