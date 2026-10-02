# SPEC: build(android): refuse to build a store bundle with the debug key

## Problem

When `android/key.properties` is absent, the `release` build type signs with
the debug key and logs a warning (SPEC 0004). That holds for the APK, which
contributors and CI build without secrets. It also holds for the app bundle, and
there it is always a mistake: the bundle's only consumer is the Play Console,
which rejects a debug-signed upload. A warning in a long Gradle log is easy to
miss, so the fallback makes the wrong file easy to produce and upload (#271).

## Design Decision

**`bundleRelease` fails when the release key is absent, unless an explicit,
named opt-out is set.** `flutter build appbundle --release` runs that task.

- **The check sits in `android/app/build.gradle.kts`**, in
  `gradle.taskGraph.whenReady`. When the graph holds a task named
  `bundleRelease`, `key.properties` is absent and the opt-out is not set, it
  throws a `GradleException`. The build stops before any task runs, so the
  refusal costs seconds, not a full R8 pass.
- **The message names `android/key.properties`**, says Play rejects a
  debug-signed bundle, points at the README's Release Signing section, and
  names the opt-out.
- **The opt-out is the environment variable `VISIOSOIL_ALLOW_DEBUG_BUNDLE`**,
  read as on only when it equals `true`. It reaches Gradle through
  `flutter build` unchanged, and its name says what it allows.
- **`assembleRelease` is untouched.** `flutter build apk --release` still falls
  back to the debug key with the warning, as SPEC 0004 requires.

**This amends SPEC 0004 for the bundle only.** SPEC 0004 rejected failing the
release build without `key.properties`, because contributors and CI build
without secrets. That reason still holds for the APK. For the bundle, the
default flips: failing is the default, and building a debug-signed bundle is
the act that has to be named.

**This also reverses the seam SPEC 0102 left.** SPEC 0102 asked that #271 gate
its refusal on an opt-in that a store build sets, so the unflagged CI command
kept building. The Developer chose the reverse on 2026-10-02: an opt-in that is
forgotten produces a debug bundle in silence, while an opt-out that is
forgotten produces a failed build that names the fix. So CI's bundle step now
sets `VISIOSOIL_ALLOW_DEBUG_BUNDLE: "true"`, and its comment says why.

**CI proves the refusal on every run.** Before the flagged bundle build, the
`build` job runs `flutter build appbundle --release` without the opt-out and
passes only if that fails with a message naming `key.properties`. It is the one
check that exercises Gradle's behaviour rather than the text of the script.

## Alternatives Considered

- **An opt-in a store build sets (SPEC 0102's seam).** Rejected by the
  Developer: forgetting the flag yields the debug bundle this spec exists to
  stop, with no error.
- **A Gradle project property (`flutter build appbundle -P...`) instead of an
  environment variable.** Workable, and rejected only on fit: CI sets an
  environment variable in the step's `env:` map, where it stands as a named key
  a config test can pin, while a `-P` argument hides inside the `run:` string.
- **Failing in a `doFirst` on `bundleRelease`.** Rejected. It would fail only
  after the whole release compile and R8 had run, minutes into the build.
- **Matching `gradle.startParameter.taskNames`.** Rejected. It sees only the
  names on the command line, so `:app:bundleRelease` or a task that depends on
  `bundleRelease` would slip past it; the task graph sees what will run.

## Scope

- Includes:
  - `android/app/build.gradle.kts`: the opt-out read and the task-graph check.
  - `.github/workflows/ci.yml`, job `build`: the refusal check and the opt-out
    on the bundle step.
  - `test/android_signing_test.dart`: config tests pinning the refusal, the
    opt-out and the APK fallback. `test/android_proguard_rules_test.dart`, if
    its bundle-step pin needs the new `env`.
  - `README.md`: the Release Signing section and the Known Issues line.
  - `docs/agents/project.md` (with `CLAUDE.md` regenerated): the `build` job's
    description.
- Does NOT include:
  - The upload key or `key.properties` itself (#269), or CI signing from
    secrets (#272).
  - Any change to how the APK is signed, or to a misconfigured
    `key.properties`, which already fails the build (SPEC 0004).

## Acceptance Criteria

- `bundle_release_refuses_the_debug_key_without_key_properties`:
  `build.gradle.kts` throws a `GradleException` naming `key.properties` when
  the task graph holds `bundleRelease`, the release keystore is absent, and the
  opt-out is not set.
- `debug_bundle_needs_the_named_opt_out`: the opt-out is read from
  `VISIOSOIL_ALLOW_DEBUG_BUNDLE` and compared with `true`.
- `apk_release_still_falls_back_to_the_debug_key`: the `release` build type
  still selects `signingConfigs.getByName("debug")` with the warning when the
  keystore is absent, and the refusal names no task but `bundleRelease`.
- `build_job_proves_the_refusal_and_opts_out_for_its_bundle`: `ci.yml`'s
  `build` job runs an unflagged `flutter build appbundle --release`, requires
  it to fail and its output to name `key.properties`, and sets
  `VISIOSOIL_ALLOW_DEBUG_BUNDLE: "true"` on the bundle build step.
- Locally, without `key.properties`: `flutter build appbundle --release` fails
  with the message; with `VISIOSOIL_ALLOW_DEBUG_BUNDLE=true` it builds and
  `keytool` prints the debug signer; `flutter build apk --release` builds with
  the warning.
- The pull request's CI run passes the refusal check and still uploads
  `release-aab`.

## Reproducibility

```sh
flutter test test/android_signing_test.dart test/android_proguard_rules_test.dart
flutter build appbundle --release            # fails, names key.properties
VISIOSOIL_ALLOW_DEBUG_BUNDLE=true flutter build appbundle --release
keytool -printcert -jarfile build/app/outputs/bundle/release/app-release.aab
flutter build apk --release                  # builds, with the warning
flutter analyze && flutter test && mf check
```

## Risks and Assumptions

- **Assumption: `flutter build appbundle` runs a task named `bundleRelease`.**
  The local run and CI's refusal check both confirm it; a Flutter that renamed
  the task would make the CI check fail, not pass silently.
- **Risk: a maintainer exports the opt-out in a shell profile.** It would turn
  the refusal off on that machine. The README names it as a CI-only switch.
- **Risk: CI time.** The refusal check configures Gradle once more and stops
  before any task runs; the PR's CI run measures it.
- **Merge order:** 0111 merges after 0106–0110, since `main`'s contiguity check
  fails on a gap.
