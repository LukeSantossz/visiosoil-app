# SPEC: ci: align Flutter toolchain version across CI and local development

## Problem

CI pins Flutter 3.38.5 while local development runs 3.44.1, so the newer local SDK forces newer
SDK-pinned transitive packages and `flutter pub get` rewrites `pubspec.lock` on every local run,
leaving the working tree perpetually dirty and out of sync with CI.

## Design Decision

Adopt Flutter 3.44.1 as the single source of truth: set `flutter-version: "3.44.1"` in all three
CI jobs (`ci.yml` lines 25/42/62), regenerate `pubspec.lock` once on 3.44.1 and commit it, and
document 3.44.1 as the required toolchain (README Getting Started + CLAUDE.md). Chosen over
downgrading local because contributors already run 3.44.1, so this moves the toolchain forward
rather than forcing a downgrade plus an fvm dependency; verification is CI analyze/test/build going
green on the bumped version, observable on the PR.

## Alternatives Considered

- **(b) Pin local to 3.38.5 via a committed `.fvmrc`/`.flutter-version`** — rejected: keeps the
  known-green CI but forces every contributor onto an older SDK via fvm, a downgrade from what they
  already run.
- **(c) Committed version file consumed by both (fvm action / `flutter-version-file`)** — rejected as
  primary: mechanically the cleanest single-source, but depends on an unverified
  `subosito/flutter-action` capability; deferred as a follow-up once the version itself is aligned.
- **Do nothing / keep reverting the lock manually** — rejected: the drift recurs on the next local
  `pub get`; a standing tax, not a one-off.

## Scope

- Includes:
  - `flutter-version: "3.44.1"` in the analyze, test, and build jobs of `.github/workflows/ci.yml`.
  - A single `flutter pub get` on 3.44.1, committing the regenerated `pubspec.lock`.
  - Documenting 3.44.1 as the source-of-truth toolchain (README Getting Started, CLAUDE.md).
- Does NOT include:
  - Adopting fvm or a `flutter-version-file` mechanism (option c) — separate follow-up.
  - Any Dart source or `pubspec.yaml` constraint change beyond the lock regeneration.
  - The iOS build job (#90) or any other CI restructuring.

## Acceptance Criteria

- `single_flutter_version_documented_and_consumed_by_ci` — `ci.yml` uses `3.44.1` in all three jobs
  and the README/CLAUDE.md name it as the required version.
- `pub_get_leaves_lock_unchanged_on_the_chosen_version` — `flutter pub get` on 3.44.1 produces no
  diff in `pubspec.lock`.
- `ci_analyze_test_build_green_on_3_44_1` — the three jobs pass on the PR.

## Reproducibility

- Local (Flutter 3.44.1 / Dart 3.12.1): `flutter pub get` then `git status --porcelain pubspec.lock`
  is empty; `flutter analyze` and `flutter test` green.
- CI: the analyze/test/build jobs on the PR at `flutter-version: "3.44.1"`.
- Note: config change with no unit test; the "test-first" step maps to first demonstrating the lock
  drift on the current split, then showing it resolved on the aligned version.

## Risks and Assumptions

- Assumption: 3.44.1 is a released stable Flutter version fetchable by `subosito/flutter-action@v2`
  (contributors run it locally); if the action cannot fetch it, fall back to (b) or (c).
- Assumption: analyze/test/build stay green under the newer SDK-pinned packages (`test` 1.31.0,
  `material_color_utilities` 0.13.0, `meta`/`matcher`/`characters`); if the bump surfaces breakage,
  fixing it is in-scope or is the trigger to reconsider (b).
- Candidate ADR: "Flutter toolchain version as single source of truth" — a durable, mildly
  hard-to-reverse policy; promote to `docs/adr/` at the gate if approved.
