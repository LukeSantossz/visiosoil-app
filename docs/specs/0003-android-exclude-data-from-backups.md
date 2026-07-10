# SPEC: fix(android): exclude database and soil images from device backups

## Problem

Android backs up the app's documents directory by default (`allowBackup`
unset → treated as true), so the cleartext SQLite database (precise field
coordinates, addresses per record) and the captured soil photo originals under
`soil_images/` are copied off-device by Auto Backup and `adb backup`.

## Design Decision

Set `android:allowBackup="false"` on the `<application>` element in
`android/app/src/main/AndroidManifest.xml`. This is the master switch that
disables Auto Backup, device-to-device transfer, and `adb backup` on every API
level, so the database and soil images leave the backup set with a single
explicit declaration and no per-path rules to maintain. Chosen over scoped
exclusion because the app is offline-first — sync (#55–57), not OS backup, is the
intended replication path — and a full disable does not leave newly added files
backup-eligible by default.

## Alternatives Considered

1. Scoped exclusion — keep `allowBackup="true"` and exclude `databases/` and
   `app_flutter/soil_images/` via `dataExtractionRules` (API 31+) and
   `fullBackupContent` (legacy). REJECTED: partial rules leave any future file
   backup-eligible by default (a later sensitive file would leak unless someone
   remembers to exclude it) and require maintaining two files across API levels;
   it also still excludes the same confidential data, so it does not buy back the
   soil-record durability that full disable gives up.
2. Leave the implicit default (`allowBackup` unset → true) — REJECTED:
   confidential field data would be copied to the user's Google account backup in
   cleartext; this is the Problem.

## Scope

- Includes:
  - Add `android:allowBackup="false"` to the `<application>` tag in
    `android/app/src/main/AndroidManifest.xml`.
  - Add a config test asserting the manifest declares it (mirrors
    `test/ios_config_test.dart`).
- Does NOT include:
  - iOS backup exclusion (separate platform, not in this issue).
  - `dataExtractionRules` / `fullBackupContent` files (unnecessary once backup is
    fully disabled).
  - Any change to sync, the database, or image storage.

## Acceptance Criteria

- `manifest_declares_allow_backup_false`: `android/app/src/main/AndroidManifest.xml`
  sets `android:allowBackup="false"` on the `<application>` element — an explicit
  declaration, not the implicit default.
- `release_build_stays_green`: `flutter build apk --release` still succeeds
  (verified in CI).

## Reproducibility

`flutter test test/android_config_test.dart`; `flutter analyze`; CI runs
`flutter build apk --release`. Deterministic, no randomness. Toolchain Flutter
3.44.1 / Dart 3.12.1.

## Risks and Assumptions

- Assumption: sync (#55–57) is the intended replication and durability path, so
  removing the OS-backup path for app data is acceptable.
- Trade-off: the confidential database and images are excluded from backup (the
  intended effect), so until sync ships a device reset or reinstall loses all
  local soil records — there is no OS backup safety net. This is inherent to not
  backing up the data and is accepted because the data must not land in Google's
  cloud backup in cleartext. `flutter_secure_storage` tokens are Keystore-bound
  and would not decrypt off-device regardless, so they are not the concern.
- Invalidated if the product decides local records must survive a reset before
  sync ships; the scoped-exclusion alternative would not help (it excludes the
  same data), so that would instead require bringing sync forward or an in-app
  export.
