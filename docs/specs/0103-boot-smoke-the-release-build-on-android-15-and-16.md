# SPEC: ci: boot-smoke the release build on Android 15 and 16

## Problem

The `smoke` job boots the release APK on API 34 only. The app targets API 36,
and CI never boots the behaviour that target switches on (#289):

- targeting API 35 enforces edge-to-edge;
- targeting API 36 makes predictive back the default.

Play requires new apps and updates to target API 36 from 31 August 2026. A
crash that only those versions trigger would merge green and reach a phone.

## Design Decision

**`smoke` runs as a matrix over API 34, 35 and 36.**

- **API 34 stays as the floor the job already proves**, and 35 and 36 join it.
- **`fail-fast: false`**, so each version reports on its own. A crash on 36 then
  does not hide whether 35 boots.
- **The target stays `default` on x86_64.** `sdkmanager --list` on 2026-10-01
  shows `system-images;android-35;default;x86_64` and
  `system-images;android-36;default;x86_64`, so all three run the same image
  family. Switching to `google_apis` would change what boots besides the
  version.
- **The script is unchanged.** It installs, launches, checks the process is
  alive and scans its PID's log for a fatal error. The 20-minute timeout applies
  to each leg, and the legs run in parallel.

**The checks are renamed `smoke (34)`, `smoke (35)` and `smoke (36)`.** `main`
has no branch protection and no ruleset (checked on 2026-10-01), so nothing
waits on a check named `smoke`.

## Alternatives Considered

- **The `google_apis` target.** Rejected while `default` images exist for every
  version. It would add Play Services to the image, which changes what the app
  meets at sign-in, besides the version under test.
- **Booting the three versions in sequence in one job.** Rejected. It triples
  the wall time of a job the pipeline already waits on.
- **Dropping API 34.** Rejected. The app's minimum is lower than 36, and 34 is
  the version the job has proven since #69.

## Scope

- Includes:
  - `.github/workflows/ci.yml`, job `smoke`: the matrix and `fail-fast: false`.
  - `test/android_proguard_rules_test.dart`: the smoke test covers the matrix.
  - `README.md` and `docs/agents/project.md` (with `CLAUDE.md` regenerated):
    the smoke job's description.
- Does NOT include:
  - Large-screen or foldable profiles. The emulator profile is a phone.
  - Fixing what a new version breaks, if anything does. That would be its own
    spec, with the failing log as its evidence.
  - Any app change.

## Acceptance Criteria

- `smoke_boots_the_release_on_api_34_35_and_36`: the `smoke` job's matrix lists
  34, 35 and 36, the emulator reads `${{ matrix.api-level }}`, and `fail-fast`
  is false. `has_a_release_boot_smoke_job_that_runs_the_apk` and
  `the_smoke_job_launches_the_final_id` keep passing.
- The pull request's CI run boots the release APK without a fatal log on all
  three versions.

## Reproducibility

```sh
flutter test test/android_proguard_rules_test.dart test/android_application_id_test.dart
flutter analyze && flutter test && mf check
```

The boot itself is evidenced by the pull request's three `smoke` checks.

## Risks and Assumptions

- **Risk: a new version fails to boot.** Then the PR shows it. The finding is
  the point of the change, and it is recorded rather than worked around.
- **Risk: runner time.** Three emulators run in parallel, each on its own
  runner, so wall time stays about one leg's.
- **Stacked on 0102 (#270)**, because both edit `ci.yml` and the same test
  group. It merges after 0102.
