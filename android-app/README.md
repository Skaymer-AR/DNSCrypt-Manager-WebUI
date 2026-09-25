# DNSCrypt Manager Android app

This is the first native Android shell for the DNSCrypt Manager module.

Current scope:

- fixed root bridge to `dnscrypt-manager`;
- native dark dashboard;
- module status and provider;
- opt-in DNS activity toggle;
- activity filters for blocked, allowed, allowlisted and error entries;
- conceptual native navigation for Home, Activity, Lists and Settings.

The module remains the source of truth. This app does not create a VPN, does
not inspect HTTPS and does not claim per-application attribution yet.

## Build status

The `Build DNSCrypt Manager Android app` GitHub Actions workflow compiles a
debug APK with JDK 17, Gradle 8.9 and Android SDK 35. On the branch used for
this integration, pushing changes starts both the Android build and the
module's existing validation/package gate. The APK and its SHA-256 are uploaded
as `DNSCrypt-Manager-Android-debug`; the opt-in activity backend module ZIP and
its SHA-256 are uploaded separately as
`DNSCrypt-Manager-v1.1.1-rc2-candidate`. Artifacts are kept for 14 days.

The APK is a debug build and the module ZIP is an unpublished candidate; neither
is an official release or a physical validation. The first phone test must
verify root approval, module discovery, status refresh, activity opt-in/opt-out,
Wi-Fi, mobile data, hotspot, persistence and rollback through the existing TWRP
rescue path.

The first physical test must verify root approval, module discovery, status
refresh, activity opt-in/opt-out, Wi-Fi, mobile data, hotspot, persistence and
rollback through the existing TWRP rescue path.
