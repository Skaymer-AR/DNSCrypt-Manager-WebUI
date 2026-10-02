# DNSCrypt Manager v1.2.1 stable — Android 0.4.3

- New icon: mint shield on a dark background, inspired by the protected DNS status.
- Tap a domain in Activity to choose Allow or Block.
- Allow adds the domain to the allowlist and removes its manual block.
- Block adds a manual rule and removes the permanent allowance and temporary exception for the same domain.
- The module applies the rule through the DNS list pipeline and restores previous inputs if the update fails.

Versions: Android 0.4.3 (versionCode 11); module v1.2.1 (versionCode 12004).

Install the module ZIP and restart the phone, then install the APK. The APK alone does not add the module command. If the previous app uses a different signing certificate, Android requires uninstalling only that app before installing the new APK; this clears the app's private data and preserves the module and its configuration.

Verify each file against its accompanying SHA-256. Compilation and package integrity checks do not replace testing on the phone.

## Validation and published files

On October 2, 2026, the user reported testing this delivery, liking the result, and wanting it published as stable v1.2.1. No performance timings or exhaustive scenario coverage were reported.

The release preserves the exact APK and ZIP delivered through Drive. Checks covered the Android build, APK signature and alignment, modified shell script syntax, the binary's ARM64 architecture, and the ZIP's structure, permissions, and integrity. Automated functional tests were not run while building these files.

The APK 0.4.3 certificate differs from the previously delivered APK 0.4.2. Upgrading from that APK requires uninstalling only the app; the module's DNS configuration is preserved. If you already installed APK 0.4.3 from Drive, this release's APK is identical.

The .sha256 files match these exact packages. Build evidence and the user report are recorded in ARTIFACTS.json.
