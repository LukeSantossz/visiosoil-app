# SPEC: build(android): add R8 keep rules for the auth stack and a release boot smoke test

## Problem
R8 minification in the release build can strip the reflection-loaded Tink
(secure storage) and Play Services auth (`google_sign_in`) classes, and CI never
runs the release APK, so such a regression would only surface as a crash on a
user's device.

## Design Decision
Add `keep` + `dontwarn` rules to `android/app/proguard-rules.pro` for Tink and
the Google Play Services auth classes `google_sign_in` uses, as defensive
protection. Address the issue's two problems:
- Problem 1 (R8 strips the auth classes): a DEX-retention check in the `build`
  job asserts the minified release APK still defines the Tink and Play Services
  auth classes, as a regression guard on the outcome the issue cares about.
- Problem 2 (CI builds the release APK but never runs it): a `smoke` job installs
  and launches the release APK on an Android emulator and fails on a startup
  crash (a `FATAL EXCEPTION` in logcat or a dead app process after a short settle
  window).

Finding recorded during implementation (by the mutation below): R8 already
retains the auth *classes* without the explicit keep rules — dropping the Tink
`-keep` line left the DEX check and the boot green — because
`flutter_secure_storage`'s `androidx.security-crypto` dependency and the Play
Services AAR ship their own consumer rules. So the keep rules are defensive, not
load-bearing for class retention: they protect reflectively-accessed *members*
(which the class-presence check does not observe) and guard a future opt-in to
`encryptedSharedPreferences` or a dependency bump (#119). The DEX check therefore
stands as a regression guard on class presence, not as a proof the keep rules are
required. The boot smoke exercises general startup R8 integrity but not the auth
path — this app reads secure storage only on the `/settings` route
(`_AccountTile` -> `authNotifierProvider` -> `restoreSession`), and driving the UI
there in a headless release emulator is fragile and, for `google_sign_in`,
infeasible (release disables the Dart VM service Flutter integration driving
needs, and the Google account picker cannot run headless).

## Alternatives Considered
1. A full `integration_test` driving the sign-in entry point on an emulator (the
   issue's literal suggestion). Rejected: R8 minifies only release builds, but
   `integration_test`/`flutter drive` need the Dart VM service, which is disabled
   in release; and the Google account picker cannot run headless. So it cannot
   validate R8 as written.
2. Keep rules only, no CI validation. Rejected: the release APK's minified auth
   path would stay unexercised in CI (the issue's problem 2), so a keep-rule
   regression could still ship. A boot smoke closes that at low incremental cost.
3. Rebuild the release APK inside the smoke job. Rejected: the `build` job
   already produces `app-release.apk`; the smoke job depends on `build` and
   downloads that artifact, avoiding a duplicate multi-minute release build.
4. Broadly keep all of `com.google.android.gms.**`. Rejected as over-keeping (it
   bloats the APK and defeats shrinking); keep the auth/common subpackages
   `google_sign_in` actually uses, plus `-dontwarn` for optional transitive
   references.

## Scope
- Includes:
  - `proguard-rules.pro`: `keep` + `dontwarn` for `com.google.crypto.tink.**` and
    the Google Play Services auth classes used by `google_sign_in`; `-dontwarn`
    for the optional transitive references R8 reports.
  - A DEX-retention check in the `build` job: after `flutter build apk --release`,
    assert the APK still defines the Tink and Play Services auth classes (fail if
    absent).
  - A CI `smoke` job (`needs: [build]`) that downloads the `release-apk`
    artifact, boots an Android emulator (`reactivecircus/android-emulator-runner`),
    installs and launches the APK, and fails if a `FATAL EXCEPTION` appears in
    logcat or the app process is not alive after a short settle window.
- Does NOT include:
  - Driving or completing the interactive Google sign-in flow (needs a real
    account and cannot run headless in release).
  - `google_sign_in` 7.x / `flutter_secure_storage` 10.x migration (#119) — the
    rules target the current 6.x / 9.x stack.
  - An iOS smoke job (#90) or any non-auth keep rules.
  - Changing the release signing fallback (ADR 0004 / #68 territory).

## Acceptance Criteria
A versioned guard test (`test/android_proguard_rules_test.dart`) asserts the keep
rules and the CI release checks are present (following the `android_config_test.dart`
pattern), written test-first (red before each). Their runtime behaviour — R8
actually retaining the classes, the app actually booting — is verified on CI and
proven non-vacuous by mutation, since a running build-config change and a CI job
are not unit-testable by construction:
- `keep_rules_present`: `proguard-rules.pro` contains `keep` rules for
  `com.google.crypto.tink.**` and the `google_sign_in` Play Services auth
  classes, verified by `test/android_proguard_rules_test.dart`. Tink carries a
  `-dontwarn` for its compile-only optional deps (`javax.annotation`,
  `com.google.errorprone`); GMS deliberately carries no blanket `-dontwarn`, so a
  missing Play Services class stays a build failure rather than a runtime
  `NoClassDefFoundError` (per the R2 review).
- `release_build_succeeds`: `flutter build apk --release` completes with no
  unsuppressed R8 warning about the auth stack.
- `dex_retains_auth_classes`: the minified release APK defines the Tink and Play
  Services auth classes (the DEX-retention check passes) — a regression guard on
  the outcome the issue cares about.
- `smoke_job_passes_on_clean_boot`: the CI `smoke` job installs and launches the
  release APK and reports no `FATAL EXCEPTION` and a live process after the
  settle window.
- `smoke_job_fails_on_a_startup_crash`: proven non-vacuous by a one-off mutation —
  a temporary startup crash turns the smoke job red; the evidence is captured in
  the PR, then reverted.

Note: an earlier criterion asserting the DEX check goes red without the Tink keep
rule was dropped after the mutation showed it does not — R8 retains the classes
via the dependencies' own consumer rules (see the Design Decision finding), so
the keep rules are defensive and the DEX check is a class-presence guard.

## Reproducibility
- Local: `flutter build apk --release` (needs the Android SDK). The emulator
  smoke runs only in CI (Linux + KVM); it is not run on the Windows dev box.
- CI: the `smoke` job in `.github/workflows/ci.yml`. Toolchain Flutter 3.44.1 /
  Dart 3.12.1; emulator API level 34, `x86_64`, default target.
```bash
flutter build apk --release
# then, in CI only: install app-release.apk on the emulator, launch it, and
# assert no FATAL EXCEPTION / a live process after the settle window.
```

## Risks and Assumptions
- Resolved during design: a cold start does NOT read secure storage — this app
  reads it only on the `/settings` route (`_AccountTile`), and `MainScreen` is a
  two-tab `IndexedStack` (Home, History) that never builds Settings. So the boot
  smoke exercises general startup R8 integrity but not the Tink path; the
  DEX-retention check is what validates the auth keep rules, deterministically.
- Assumption: GitHub `ubuntu-latest` provides the KVM acceleration
  `android-emulator-runner` needs. Invalidated if the runner lacks nested
  virtualization, which would force a different runner or approach.
- Risk: emulator jobs are slow (several minutes) and occasionally flaky (boot
  timeouts). Mitigate with the action's AVD cache and a bounded settle window,
  and keep the job downstream of `build` so it never blocks `analyze`/`test`.
- Assumption: launching via the LAUNCHER intent
  (`monkey -p com.visiosoil.visiosoil_app -c android.intent.category.LAUNCHER 1`,
  or `am start -n com.visiosoil.visiosoil_app/.MainActivity`) reaches the first
  Flutter frame; `MainActivity` is exported with the LAUNCHER category (confirmed
  in `AndroidManifest.xml`).
- Note for the Gate: the "R8 minifies only release" versus "Flutter VM service is
  disabled in release" interaction is why a full sign-in drive is infeasible;
  this is a candidate for a short ADR to record for the next CI change (#90 iOS).
  Default proposal: record in the spec archive only, no new ADR.
