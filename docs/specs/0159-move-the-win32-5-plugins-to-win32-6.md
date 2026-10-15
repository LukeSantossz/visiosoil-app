# SPEC: build(deps): move the win32 5 plugins to their win32 6 majors

## Problem

`share_plus` 12 and `package_info_plus` 8 pin `win32` 5. That keeps
`flutter_secure_storage` on a superseded major (SPEC 0158) and its Windows
package without 4.2.x's concurrency fixes (#381).

## Design Decision

**Move `share_plus` to 13.x, `package_info_plus` to 10.x and
`flutter_secure_storage` to 11.x in one change, and raise the Android Gradle
Plugin from 8.11.1 to 8.12.1, the floor they declare.**

**Why together.** None of these resolves alone. A trial resolve on 2026-10-12
showed the chain:

- `flutter_secure_storage` 11 and `share_plus` 13 both need `win32` ^6.0.1.
- `package_info_plus` 8 does not resolve beside `share_plus` 13.
- `package_info_plus` 9 and later declare AGP >= 8.12.1, Gradle >= 8.13 and
  Kotlin 2.2.0. `share_plus` 13.3.1 builds against AGP 8.12.1 as well.
- `geolocator_linux` follows: 0.2.3 requires `package_info_plus` ^8, so the lock
  moves it to 0.2.6, which requires ^10. `win32` 6.4.0 also brings a new regular
  dependency, `ffi_leak_tracker` 0.1.2, which only Windows builds load.
- The AGP floor is declared, not enforced: `share_plus` 12.0.2 already declared
  8.12.1, and the app built on 8.11.1. Meeting it is the safe reading, and CI's
  build is the proof.

**Why AGP 8.12.1, not Flutter's template 9.0.1.** Flutter 3.44.1 warns below
8.11.1 and accepts anything above it. Version 8.12.1 is the smallest move that
satisfies the plugins. AGP 9 is a new major, and Flutter's template pairs it with
Gradle 9.1, so it is a migration of its own. The app's Gradle 8.14, Kotlin 2.2.20 and CI's
JDK 17 already meet 8.12.1's requirements, so `android/settings.gradle.kts` is
the only build file that changes.

**The Dart APIs the app uses are unchanged.** Checked in the resolved sources:

- **`share_plus` 13** lists only the `win32` move as breaking. One behaviour
  changes, for the better: on an iPad, 12.0.2 refused a share with no
  `sharePositionOrigin` ("argument must be set"), and the app passes none. 13.x
  centres the popover instead, so iPad shares start working. The app is
  universal (`TARGETED_DEVICE_FAMILY` "1,2").
  `SharePlus.instance.share(ShareParams)` is unchanged, and so is
  `SharePlatform.share(ShareParams)`, which the share tests' fake extends.
  `share_plus_platform_interface` moves from 6 to 7 as a dev dependency.
- **`package_info_plus` 10** lists the `win32` move, iOS >= 13 (the app targets
  13.0) and macOS >= 10.15. 10.2.2 requires Flutter >= 3.38.1. `PackageInfo(appName:,
  packageName:, version:, buildNumber:)` and `PackageInfo.fromPlatform()` are
  unchanged.
- **`flutter_secure_storage` 11** keeps the calls `FlutterKeyValueSecureStorage`
  makes, as SPEC 0158 checked.

**Sessions.** 11.x reads what 10.x wrote: 10.x's defaults are RSA-OAEP and
AES-GCM, which 11 keeps, with the same preference file and key alias. A device
that goes from a 9.x build straight to this one cannot decrypt its stored
session. With no algorithm markers, 11 assumes its own defaults, the read fails,
`resetOnError` wipes the store, and the app starts signed out without notice.
`checkUpgradeStatus()` could detect it, and the app does not call it. No Play
release has shipped, so only development devices can take that path, and the
loss is accepted.

## Alternatives Considered

- **AGP 9.0.1, Flutter's template.** Rejected for this change. It is a major
  move paired with Gradle 9.1, and nothing here requires it.
- **Stay on `win32` 5.** Rejected. It keeps `flutter_secure_storage` 10 and its
  Windows package without the concurrency fixes, and every `plus_plugins` update
  from now on needs `win32` 6.
- **`dependency_overrides` forcing `win32` 6.** Rejected, as in SPEC 0158. It
  would run plugins against a `win32` major they were not built for.

## Scope

- Includes:
  - `pubspec.yaml`:
    - `share_plus: ^13.3.1`, `package_info_plus: ^10.2.2` and
      `flutter_secure_storage: ^11.2.0`;
    - the dev dependency `share_plus_platform_interface: ^7.2.0`.
  - `pubspec.lock`, regenerated on Flutter 3.44.1.
  - `android/settings.gradle.kts`: `com.android.application` 8.11.1 to 8.12.1.
  - The stale `android/app/proguard-rules.pro` comment that says Tink comes
    through `androidx.security-crypto`. Since 10.x the plugin declares
    `tink-android` itself. The comment changes; the rules do not.
  - Any app or test change the new APIs force. None is expected.
  - Comments that describe the Tink rule as defensive or name 10.3.4 alone:
    `test/android_proguard_rules_test.dart` and
    `test/services/secure_credential_store_test.dart`.
- Does NOT include:
  - AGP 9, Gradle or Kotlin changes.
  - The `google_sign_in` 7 migration (#119).
  - `connectivity_plus` or any other dependency that resolves today.
  - Any new option of these plugins.

## Acceptance Criteria

- `lock_resolves_the_win32_6_majors`: `pubspec.lock` resolves `share_plus` 13.x,
  `package_info_plus` 10.x, `flutter_secure_storage` 11.x and `win32` 6.x on
  Flutter 3.44.1. Checked from the lock diff.
- The existing share, settings (app version), secure-storage and auth tests pass
  unchanged, including SPEC 0158's three.
- CI's `build` job passes on AGP 8.12.1:
  - the release APK;
  - the R8 DEX checks for Tink and Play Services auth;
  - the release app bundle.
- CI's `smoke` job boots the release APK at API 34, 35 and 36, and `build-ios`
  passes.
- `flutter analyze`, the full suite and `mf check` pass.

## Reproducibility

```sh
flutter pub get   # Flutter 3.44.1
flutter analyze && flutter test && mf check
# Android build: CI's build and smoke jobs (this machine lacks Developer Mode)
```

## Risks and Assumptions

- **No red step.** This change moves versions and keeps behaviour, so no new test
  can fail first. The existing suites and CI's build and smoke jobs are the
  check. The suites include the share fake, the version tile and SPEC 0158's
  storage tests.
- **Risk: the Android build is not run locally.** Plugin builds need Developer
  Mode on this Windows machine. CI's `build` and `smoke` jobs are the only
  Android verification, and a failure there is fixed in this change.
- **Risk: a v9 session on a development device is lost.** It is accepted, as
  SPEC 0158 records.
- **Device check:** share on an iPad, which this change fixes, as well as on a
  phone.
- **Follow-up:** the Tink `-keep` rule now keeps a library nothing calls, and
  CI's Tink DEX check tests only that rule. Whether to drop both is a separate
  decision.
- **Merge order.** This merges after #382 (SPEC 0158), whose branch it builds
  on.
