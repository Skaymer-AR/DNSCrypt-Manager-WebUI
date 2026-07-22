# DNSCrypt Manager v1.0.0 — Release notes (EN)

**First stable release.** The scope was deliberately narrowed to what is implemented,
tested and actually in use: experimental work was **removed** rather than relabelled
as stable.

- `version=v1.0.0` · `versionCode=10000` · same module ID (`dnscrypt_manager`).
- Installs on top of v0.3.0-RC1 / RC2.x **preserving configuration and data**.

## What v1.0.0 includes
- **DNSCrypt / DoH / NextDNS** with preset providers.
- Optional **DNS redirection** and **fail-closed**.
- **Stable IPv4**; Wi-Fi, mobile data and hotspot, switching networks without losing DNS.
- **Lists**: metadata-driven catalog, batch compilation, allowlist, blacklist,
  **temporary allow**, profiles and category protection.
- **BindHosts list import**.
- **Per-service privacy**: 9 real controls on the `service-control` backend with
  verified enforcement (their domains genuinely reach the compiled list), modes
  `off/15m/1h/until_reboot/permanent`, expiry and allowlist-conflict reporting. All
  **OFF** on a clean install.
- **On-demand events** (see below).
- **PANIC** and recovery; rollback and last-known-good; locks, timeouts, cancellation.
- **KernelSU Next + Hybrid Mount** (central CLI resolver with a 3-path allowlist).

## Highlights
### BindHosts: no longer asked to be disabled
The warning claiming BindHosts was incompatible or could break connectivity or cause a
bootloop has been removed entirely. **Nothing is blocked, nothing must be disabled, and
there is no red alert.**

Honest record: the user ran **DNSCrypt Manager and BindHosts simultaneously for one
week** on a **Motorola Edge 40 Pro (Android 16, KernelSU Next, Hybrid Mount, SELinux
Enforcing)** over Wi-Fi, mobile data and hotspot, with **no DNS loss, no connectivity
loss and no bootloop**. This is a **user-confirmed physical test**, not a guarantee of
universal compatibility on any device or version. Practical note: both filter
independently, so if a domain appears blocked and is not in your lists, check BindHosts
too.

### Events: lazy and collapsible
Previously the events list loaded during general initialization and could stall the
WebUI even before opening the Activity tab. Now:
- at WebUI startup, `events list` and `events stats` do **not** run, no rows are built
  and no history is fetched in the background;
- Activity shows only a compact, **collapsed** header;
- on expand: "Loading events…", **one** query, at most **20 rows**, with **Load more**
  when there are further results;
- on collapse: the list is **unmounted from the DOM**, late responses are ignored and
  querying stops. Refresh, Statistics, Clear history, Allow 5m/1h, Allowlist and Copy
  remain available.

### Experimental or incomplete features were removed
- **Anonymized DNSCrypt and ODoH**: out of stable scope. Their cards, buttons, inputs,
  status loading, polling and all EN/ES strings were removed, and they are no longer
  initialized. v1.0.0 does **not** promise them. The code stays internal, unexposed and
  marked experimental.
- **Legacy "Service controls" card** (RC2 `service` engine), which rendered empty and
  duplicated the real section: removed completely.
- Removed the "this version is still in testing" / "the first stable release will be
  v1.0.0" notices.

## Real limitations (no overpromising)
- This is a **DNS filter/manager**: not a VPN, no MITM, no CA installation, no HTTPS
  inspection, no cosmetic filters.
- DNS-based ad blocking is **best-effort**; it does not block everything (for example
  ads served from the same domains as the content).
- **IPv6** depends on the network and was not exhaustively validated; the confirmed
  stable usage is with **forced IPv4**.
- Per-app policies (`app-policy`) have **no enforcement**: they are recorded only,
  unexposed, and create no firewall rules.
- Documented pending items, with no invented data: forced physical rollback, long-term
  battery consumption, long-term RAM consumption.
- Linux/x86 results are **not** equivalent to Android; see
  `ANDROID_USER_VALIDATION_v1.0.0.md`.

## Updating
Install the ZIP over the previous version (same module ID). The schema migration is
**idempotent and backed up**: it preserves configuration, redirect, fail-closed, lists,
allowlist, blacklist, custom sources, profiles, exceptions, history within retention,
the YouTube control and the chosen language. No lists are downloaded at boot.
