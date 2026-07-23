# SPEC: ci(pipeline): add an iOS build job so iOS-only config breaks fail CI

## Problem
The repo targets iOS but CI compiles only Android (`flutter build apk --release`
on `ubuntu-latest`). An iOS-only platform-config break — like the missing
reversed-client-id URL scheme fixed in #66 — ships fully green because nothing in
CI runs `xcodebuild`. `test/ios_config_test.dart` guards a few specific
`Info.plist` keys but not broader iOS build/config regressions.

## Design Decision
Add a `build-ios` job to `.github/workflows/ci.yml` on a `macos-latest` runner
(the only environment that can run `xcodebuild`) that runs
`flutter build ios --release --no-codesign`, gated on `analyze` and `test` like
the existing `build` job. `--no-codesign` exercises the real Xcode/`Info.plist`
build without needing signing certificates or provisioning profiles, so no
secrets are required. It mirrors the existing `build` job's structure
(checkout → `subosito/flutter-action` pinned to the CI toolchain →
`flutter pub get` → build).

## Alternatives Considered
1. A Dart config-guard test that greps `ios/` for the expected settings, no
   macOS runner. Rejected: it can only assert the specific keys someone thought
   to guard (that is exactly what `ios_config_test.dart` already does and what
   #90 says is insufficient); it never runs the real compiler, so a novel iOS
   build break still passes.
2. A full signed iOS build / device job. Rejected: needs certificates and
   provisioning profiles in CI (secrets, cost, maintenance) for no extra signal
   about config correctness — `--no-codesign` already compiles the target.

## Scope
- Includes:
  - A `build-ios` job in `ci.yml`: `runs-on: macos-latest`,
    `needs: [analyze, test]`, checkout, Flutter action pinned to the same
    version the other jobs use, `flutter pub get`, then
    `flutter build ios --release --no-codesign`.
  - A guard test (extending the existing `ci.yml`-asserting test pattern, e.g.
    `test/ci_ios_build_test.dart` or the existing CI-config test) that fails
    before the job exists and asserts the executable tokens: `macos-latest`,
    `flutter build ios --release --no-codesign`, the `needs: [analyze, test]`
    gate, and a `flutter pub get` step — asserting tokens that also appear in
    comments is disallowed (per the config-guard lesson).
- Does NOT include:
  - Any iOS source/`Info.plist`/Podfile change; no signing setup.
  - Adding an iOS device/test job, or changing the Android `build`/`smoke` jobs.

## Acceptance Criteria
- `ci.yml` has a `build-ios` job on `macos-latest` running
  `flutter build ios --release --no-codesign`, gated on `analyze` + `test`, with
  `flutter pub get` before the build.
- The guard test asserts those tokens and is red before the job is added, green
  after.
- Reverting the #66 `Info.plist` keys in a way that breaks the build fails the
  pipeline on `build-ios` (verified by the job running on the PR's macOS runner —
  see Risks; not reproducible on this Windows host).

## Reproducibility
Toolchain Flutter 3.44.1 / Dart 3.12.1. Local: `flutter analyze && flutter test`
(the guard test). The actual iOS compile runs only on CI's `macos-latest`.

## Risks and Assumptions
- The iOS build itself CANNOT be verified locally (no macOS here) or by the
  Windows/Ubuntu jobs — its first real execution is the `macos-latest` job on
  this change's own PR. That run is the acceptance evidence for "an iOS config
  break fails the pipeline"; if that first run reveals a pre-existing iOS build
  problem unrelated to #90, it is reported, not silently worked around.
- Assumption: the current `main` iOS target already builds clean with
  `--no-codesign`. If it does not, the job will (correctly) go red on a real
  pre-existing break; that is the job doing its job, and the fix is scoped
  separately, not hidden by removing the job.
- macOS runners bill at a higher rate than Ubuntu; the issue accepts that cost
  for catching one-of-two-platform breaks.
