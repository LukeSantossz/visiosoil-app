# Disable Android OS backup for confidential local data: `allowBackup="false"`, replication deferred to app sync

VisioSoil sets `android:allowBackup="false"` on the `<application>` element, so
Android's Auto Backup, device-to-device transfer, and `adb backup` no longer copy
the app's data off-device. The data at stake is confidential: the cleartext SQLite
database (precise field coordinates and addresses per record) and the captured
soil photo originals under `soil_images/`. OS Auto Backup is uncontrolled,
automatic, and app-opaque; the app's own Google Drive sync (#55, over Google
Sign-In + the Drive API) is the intended, app-governed replication path. Disabling
the OS backup does not touch that sync — they are independent systems — so this
removes the uncontrolled leak while leaving the controlled durability path intact.

## Status

Accepted. Implemented under issue #111 (SPEC `docs/specs/0003-android-exclude-data-from-backups.md`
approved at the Spec Gate). Prompted by the 2026-07-03 security audit. Part of the
Auth & Release Readiness milestone (M1).

### Decided
- **Full disable, not scoped exclusion** — `allowBackup="false"` is the master switch on every API level; it needs no `dataExtractionRules`/`fullBackupContent` files and does not leave future files backup-eligible by default.
- **Explicit declaration** — the attribute is set explicitly rather than relying on the implicit `true` default, and a config test (`test/android_config_test.dart`, mirroring `test/ios_config_test.dart`) guards it.
- **Replication is the app's job, not the OS's** — durability of records is deferred to the app's Google Drive sync (#55–57), which the app controls (what, when, and eventually how, e.g. encrypted blobs), unlike the opaque OS backup.

## Considered Options

### How to keep confidential data out of backups
- **Scoped exclusion** — keep `allowBackup="true"`, exclude `databases/` and `app_flutter/soil_images/` via `dataExtractionRules` (API 31+) and `fullBackupContent` (legacy). Rejected: partial rules leave any newly added file backup-eligible by default and require two files across API levels, while still excluding the same data (so it does not preserve record durability either).
- **Leave the implicit default** — rejected: confidential field data is copied to the user's Google backup in cleartext.
- **Full disable (chosen)** — one explicit attribute, all API levels, no future-file footgun.

## Consequences

- The cleartext database and soil images are no longer copied to the user's Google account backup or extractable via `adb backup`.
- Durability trade-off: until sync (#55–57) ships, a device reset or reinstall loses all local soil records — there is no OS backup safety net. Accepted because the data must not land in cloud backup in cleartext and no user relies on backup restore in this pre-release app.
- The app's Google Drive sync is unaffected (`allowBackup` governs OS Auto Backup only, not Google Sign-In or the Drive API).
- `flutter_secure_storage` tokens are Keystore-bound and would not decrypt off-device regardless, so they were never the exposure here.
- A future move to keep records durable before sync (e.g. an encrypted database or an in-app export) would revisit this, but the scoped-exclusion alternative would not help since it excludes the same data.
