# SPEC: ci: build the release app bundle alongside the APK

## Problem

Google Play requires an Android App Bundle for a new app. The CI `build` job
runs only `flutter build apk --release`, and the README documents only the APK,
so nothing has ever built the bundle (#270). The format the store accepts would
be built for the first time on release day, and a failure would surface then.

## Design Decision

**The `build` job builds the bundle after the APK and its DEX check, and
uploads it as its own artifact.**

- **`flutter build appbundle --release`** runs in the same job, so the bundle
  reuses the toolchain setup, the Drift code generation and Gradle's state.
- **`keytool -printcert -jarfile`** prints the bundle's signer into the log. A
  bundle carries a JAR signature, which `keytool` reads. `apksigner` does not
  apply to it.
- **The bundle is uploaded as `release-aab`**, beside `release-apk`. The smoke
  job keeps reading the APK.

**In CI the bundle is debug-signed, exactly as the APK is.** There is no
`android/key.properties`, so Gradle falls back to the debug key. The step
proves that the bundle builds, not that Play would accept its signature. That
needs the upload key (#269) and CI secrets (#272).

**The CI command carries no store opt-in, and #271 must keep it building.**
#271 will refuse to build a store bundle with the debug key. Its refusal has to
be gated on an explicit opt-in that a store build sets, so the unflagged CI
invocation keeps falling back to the debug key. That is the seam left here. The
other session, which owns #271, has been told.

**The README's release section gains the bundle.** It shows the command and how
to verify its signer, beside the APK's. The Known Issues line about
debug-signed builds names the bundle too.

## Alternatives Considered

- **A separate `bundle` job.** Rejected. It would repeat the Java and Flutter
  setup and the Drift generation, minutes per run, for a step that shares
  everything with the APK build.
- **Validating the bundle with `bundletool build-apks`.** Deferred. It is a
  stronger check, but it adds a tool download to CI, and Play validates the
  bundle on upload. It belongs with the store-upload work, if anywhere.
- **Asserting in CI that the signer is the debug key.** Rejected. It would fail
  the moment #272 gives CI the upload key, and it guards nothing a reader of the
  printed signer cannot see.

## Scope

- Includes:
  - `.github/workflows/ci.yml`, job `build`: the bundle step, the signer print
    and the `release-aab` upload.
  - `test/android_proguard_rules_test.dart`: a config test pinning the step, as
    the DEX check is pinned. `test/android_signing_test.dart`: a test pinning
    the README's bundle instructions.
  - `README.md`: the release section and the Known Issues line.
  - `docs/agents/project.md` (with `CLAUDE.md` regenerated): the `build` job's
    description.
- Does NOT include:
  - The upload key, CI signing from secrets, or refusing the debug key (#269,
    #272, #271).
  - Any Gradle change, or any upload to Play.

## Acceptance Criteria

- `build_job_builds_and_uploads_the_release_app_bundle`: `ci.yml` runs
  `flutter build appbundle --release`, prints the bundle's signer with
  `keytool -printcert -jarfile`, and uploads
  `build/app/outputs/bundle/release/app-release.aab` as `release-aab`.
- `readme_documents_building_and_verifying_the_bundle`: the README's release
  section shows `flutter build appbundle --release` and
  `keytool -printcert -jarfile build/app/outputs/bundle/release/app-release.aab`.
- The bundle builds locally with `flutter build appbundle --release`, and its
  signer prints.
- The pull request's CI run builds the bundle, logs a debug signer, and lists
  `release-aab` among its artifacts.

## Reproducibility

```sh
flutter test test/android_proguard_rules_test.dart test/android_signing_test.dart
flutter build appbundle --release
keytool -printcert -jarfile build/app/outputs/bundle/release/app-release.aab
flutter analyze && flutter test && mf check
```

## Risks and Assumptions

- **Risk: build time.** A second R8 and Gradle pass adds minutes to `build`. The
  PR's CI run measures it.
- **Assumption: the debug fallback signs bundles as it signs APKs.** The
  `release` build type's `signingConfig` applies to both outputs.
- **Merge order:** 0102 merges after the other session's 0100 (#313) and 0101
  (#314), and 0103 (#289) is stacked on it.
