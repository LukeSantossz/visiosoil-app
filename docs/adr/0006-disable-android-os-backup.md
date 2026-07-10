# Disable Android OS backup and device transfer for confidential local data: `allowBackup="false"` plus full-exclude `dataExtractionRules`

VisioSoil excludes its local data from every Android off-device path. The data at
stake is confidential: the cleartext SQLite database (precise field coordinates
and addresses per record) and the captured soil photo originals under
`soil_images/`. The `<application>` element sets `android:allowBackup="false"`
(full disable on Android 11 and lower) and
`android:dataExtractionRules="@xml/data_extraction_rules"`, whose rules exclude
every data domain from both `<cloud-backup>` and `<device-transfer>` (Android
12+). Android's Auto Backup, `adb backup`, and device-to-device transfer are the
uncontrolled, app-opaque paths; the app's own Google Drive sync (#55, over Google
Sign-In + the Drive API) is the intended, app-governed replication path.
Disabling the OS paths does not touch that sync — they are independent systems.

## Status

Accepted. Implemented under issue #111 (SPEC `docs/specs/0003-android-exclude-data-from-backups.md`
approved at the Spec Gate). Prompted by the 2026-07-03 security audit; the R2
cross-provider review then caught that `allowBackup="false"` alone does not block
Android 12+ device-to-device transfer, which added the `dataExtractionRules`
requirement. Part of the Auth & Release Readiness milestone (M1).

### Decided
- **Cover every API level explicitly** — `allowBackup="false"` disables backup and `adb backup` on API ≤ 30; `dataExtractionRules` excludes all domains from cloud backup and device transfer on API 31+, where `allowBackup` no longer governs device-to-device transfer.
- **Full exclude, not scoped** — the rules exclude all domains (`root`, `file`, `database`, `sharedpref`, `external`) with `path="/"`, so no future file becomes backup-eligible by default.
- **Explicit and guarded** — the attributes and the rules file are set explicitly rather than relying on defaults, and a config test (`test/android_config_test.dart`, mirroring `test/ios_config_test.dart`) guards them.
- **Replication is the app's job, not the OS's** — durability of records is deferred to the app's Google Drive sync (#55–57), which the app controls, unlike the opaque OS backup/transfer.

## Considered Options

### How to keep confidential data off other devices and the cloud
- **`allowBackup="false"` alone** — rejected: on Android 12+ it disables cloud backup but not device-to-device transfer (verified against the Android backup docs), leaving the app data extractable during a phone migration.
- **Scoped exclusion** — exclude only `databases/` and `soil_images/` while keeping the rest backup-eligible. Rejected: leaves newly added files backup-eligible by default and still excludes the same data (so it does not preserve record durability either).
- **Leave the implicit default** — rejected: confidential field data is copied to the user's Google backup in cleartext.
- **Full disable across all API levels (chosen)** — `allowBackup="false"` plus a full-exclude `dataExtractionRules`.

## Consequences

- The cleartext database and soil images are no longer copied to the user's Google account backup, extractable via `adb backup`, or transferred during an Android 12+ device-to-device migration.
- Durability trade-off: until sync (#55–57) ships, a device reset, reinstall, or phone migration loses all local soil records — there is no OS safety net. Accepted because the data must not leave the device in cleartext and no user relies on backup restore in this pre-release app.
- The app's Google Drive sync is unaffected (`allowBackup`/`dataExtractionRules` govern OS backup and transfer only, not Google Sign-In or the Drive API).
- `flutter_secure_storage` tokens are Keystore-bound and would not decrypt off-device regardless, so they were never the exposure here.
- A future move to keep records durable before sync (e.g. an encrypted database or an in-app export) would revisit this; scoped exclusion would not help since it excludes the same data.
