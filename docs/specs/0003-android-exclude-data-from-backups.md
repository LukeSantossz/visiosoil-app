# SPEC: fix(android): exclude database and soil images from device backups

## Problem

Android backs up the app's documents directory by default (`allowBackup`
unset → treated as true), so the cleartext SQLite database (precise field
coordinates, addresses per record) and the captured soil photo originals under
`soil_images/` are copied off-device by Auto Backup, `adb backup`, and — on
Android 12+ — device-to-device transfer.

## Design Decision

Set both `android:allowBackup="false"` and
`android:dataExtractionRules="@xml/data_extraction_rules"` on the `<application>`
element. `allowBackup="false"` fully disables Auto Backup and `adb backup` on
Android 11 and lower (API ≤ 30). On Android 12+ (API 31+), `allowBackup="false"`
disables cloud backup but does **not** disable device-to-device transfer (that
path is governed only by `dataExtractionRules`), so
`res/xml/data_extraction_rules.xml` excludes every data domain (`root`, `file`,
`database`, `sharedpref`, `external`) from both `<cloud-backup>` and
`<device-transfer>`. Together they exclude the database and soil images from every
backup and transfer path on every API level. This is a full exclude, not a scoped
per-path allowlist, so no future file becomes backup-eligible by default.

## Alternatives Considered

1. `allowBackup="false"` alone — REJECTED: verified against the Android docs that
   on Android 12+ it disables cloud backup but not device-to-device transfer, so
   the database and images would still be copied during a phone transfer; leaves
   the API 31+ transfer path open.
2. Scoped exclusion — exclude only `databases/` and `soil_images/` paths and keep
   the rest backup-eligible. REJECTED: leaves any newly added file backup-eligible
   by default; excluding all domains is simpler and safer for data that is
   confidential by default.
3. Leave the implicit default (`allowBackup` unset → true) — REJECTED:
   confidential field data would be copied to the user's Google backup in
   cleartext; this is the Problem.

## Scope

- Includes:
  - Add `android:allowBackup="false"` and
    `android:dataExtractionRules="@xml/data_extraction_rules"` to the
    `<application>` tag in `android/app/src/main/AndroidManifest.xml`.
  - Add `android/app/src/main/res/xml/data_extraction_rules.xml` excluding all
    domains from `<cloud-backup>` and `<device-transfer>`.
  - Add a config test asserting the policy (mirrors `test/ios_config_test.dart`).
- Does NOT include:
  - iOS backup exclusion (separate platform, not in this issue).
  - Any change to sync, the database, or image storage.

## Acceptance Criteria

- `manifest_declares_allow_backup_false`: the `<application>` element sets
  `android:allowBackup="false"` (legacy/pre-12 path), not the implicit default.
- `manifest_references_data_extraction_rules`: the `<application>` element sets
  `android:dataExtractionRules="@xml/data_extraction_rules"` (API 31+ path).
- `rules_exclude_data_from_cloud_backup_and_device_transfer`:
  `data_extraction_rules.xml` declares both a `<cloud-backup>` and a
  `<device-transfer>` section, each excluding the app data domains.
- `release_build_stays_green`: `flutter build apk --release` still succeeds.

## Reproducibility

`flutter test test/android_config_test.dart`; `flutter analyze`; `flutter build
apk --release`. Deterministic, no randomness. Toolchain Flutter 3.44.1 / Dart
3.12.1.

## Risks and Assumptions

- Assumption: sync (#55–57) is the intended replication and durability path, so
  removing the OS-backup and transfer paths for app data is acceptable.
- Trade-off: the confidential database and images are excluded from backup and
  transfer (the intended effect), so until sync ships a device reset, reinstall,
  or phone-to-phone migration loses all local soil records — there is no OS
  safety net. Accepted because the data must not land in cloud backup or another
  device in cleartext. `flutter_secure_storage` tokens are Keystore-bound and
  would not decrypt off-device regardless.
- Invalidated if the product decides local records must survive a reset before
  sync ships; scoped exclusion would not help (it excludes the same data), so
  that would instead require bringing sync forward or an in-app export.
