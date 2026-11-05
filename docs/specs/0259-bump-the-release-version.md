# SPEC: build(release): bump the version to 3.0.0+3

## Problem

`pubspec.yaml` says `version: 2.0.0+2`, set by `e7348d5` for the `v2.0.0` release of 2026-05-03. Since then `main` has moved by close to two thousand commits, and the app a build reports is not the app `v2.0.0` was:

- the classifier is no longer a TFLite network but the descriptor path computed in Dart from `assets/models/spec.json` (ADR 0024, SPEC 0083), and the app no longer carries the TFLite runtime (SPEC 0083);
- the model's class list went from five classes to four (ADR 0016, SPEC 0046);
- the database went to schema v12, with migrations from every earlier version.

Every build still calls itself `2.0.0+2`: the Settings version tile, the error report a user shares from Settings (SPEC 0110), and the version name and code Android and iOS read from the pubspec. An error report from today's app and one from May's carry the same version, so they cannot be told apart.

On 2026-11-04 the Developer asked for the release version to be updated.

## Design Decision

- `pubspec.yaml`'s `version:` becomes `3.0.0+3`.
  - **Major**, by the rule `v2.0.0` set: its notes list "Texture classes reduced from 12 USDA classes to 5" under Breaking. Going from five classes to four, and from a TFLite model to a contract of numbers, is the same kind of change.
  - **Build 3**, one above the last. Android's `versionCode` and iOS's `CFBundleVersion` read it, and a store refuses a build number that does not grow.
- The README's Project Status line names the current version, `3.0.0`, beside the `v2.0.0` tag it follows, and still points at #265 for the first Play release.
- A guard, `test/standards/release_version_test.dart`:
  - `the_readme_names_the_pubspec_version`: the README's Project Status paragraph names the version `pubspec.yaml` declares, without its build number. It fails today, because the README names no current version.

## Alternatives Considered

- **Minor, `2.1.0`.** Rejected: `v2.0.0` treated a smaller class-list change as breaking, and a minor bump would say the classifier is compatible with the one before it.
- **Tag `v3.0.0` and publish a GitHub release in this change.** Rejected for this spec: a tag names a commit on `main`, which exists only after the merge, and a release is a public act the Developer takes. It is the step after this one, and the pull request says so.
- **Read the version from the pubspec at the README's render.** Not possible: GitHub renders the README as written.

## Scope

- Includes:
  - the `version:` line of `pubspec.yaml`;
  - the Project Status line of `README.md`;
  - the guard.
- Does NOT include:
  - a git tag, a GitHub release or release notes;
  - a Play or App Store upload, which ADR 0026 holds back until real photographs are classified;
  - any code, dependency or `pubspec.lock` change.

## Acceptance Criteria

- `release_version_test.dart` fails before the change and passes after.
- `flutter build apk --release` reports, in `build/app/outputs/apk/release/output-metadata.json`, `versionName` `3.0.0` and `versionCode` `3`.
- No produced text holds U+2013 or U+2014.
- `flutter test` shows no failures beyond those this machine has on `main`, and `mf check` passes.

## Reproducibility

Flutter 3.44.1 / Dart 3.12.1 in CI. Run `flutter test test/standards/release_version_test.dart`, then `flutter test` and `mf check`.

## Risks and Assumptions

- **The README line goes stale at the next bump.** The guard is what keeps it in step with the pubspec.
- **Assumption:** no build was uploaded to a store with a build number above 2. No Play release has happened (#265), so none was.
