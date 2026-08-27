# SPEC: build(deps): raise the Dart SDK floor to 3.12 to match the lockfile

## Problem

`pubspec.yaml` declares `environment.sdk: ^3.11.0`, but `pubspec.lock` (rewritten when `shared_preferences` landed in #49) resolves `sdks: dart ">=3.12.0 <4.0.0"`. The declared floor and the committed resolution disagree: a `flutter pub get` on a Dart 3.11 SDK could not use the committed lockfile. R2 flagged this as a [P2] on the #49 PR and it was deliberately deferred there (issue #153) to keep that PR scoped to onboarding.

## Design Decision

Raise `environment.sdk` to `^3.12.0` so the declared floor matches the resolved lock. Bumping the constraint also raises the package's effective language version to 3.12, which activates `prefer_initializing_formals` on nine constructor initializer-list assignments (in `google_sign_in_gateway`, `management_tips_controller`, `proxy_research_service`, `sync_engine`) that `flutter analyze` — fatal-on-info in CI — would then report. Resolve each by converting the assignment to a private initializing formal (`required this._field`).

All nine flagged sites already have a parameter whose name matches its field stem (`tokenValidity`, `clock`, `repository`, `connectivity`, `appVersion`, `timeout`, `retryDelay`, `maxAttempts`, `backend`). A private initializing formal keeps the public named-parameter label identical (Dart derives the label from the field name without the leading underscore), so this is a purely internal change with **no call-site, provider, or test edits**. Existing defaults and `required` modifiers are preserved on the formals.

The three nearby initializer assignments the lint does not flag are left untouched: `_research = researchService` and `_local = localStore` have parameter names that differ from their field stems (converting them would rename the public label and break callers), and `_googleSignIn = googleSignIn ?? GoogleSignIn(...)` uses a fallback expression, not a bare parameter.

## Scope

- Includes:
  - `pubspec.yaml`: `environment.sdk: ^3.11.0` → `^3.12.0`.
  - The nine `prefer_initializing_formals` fixes in the four named service files (initializer-list `_field = param` → `required this._field`).
  - A regression guard asserting the declared floor is consistent with the lockfile's resolved Dart minimum.
- Does NOT include:
  - Any dependency version bump or `pubspec.lock` change beyond what the floor edit implies (the lock already requires dart >= 3.12; no `pub get` re-resolution is intended).
  - The three unflagged initializer assignments (`_research`, `_local`, `_googleSignIn`) — renaming their labels is out of scope.
  - Any behavior, API-label, or logic change.

## Acceptance Criteria

- sdk_floor_raised: `environment.sdk` is `^3.12.0`.
- floor_lock_consistent: a test asserts the `pubspec.yaml` floor's minor is >= the `pubspec.lock` `sdks.dart` minimum minor (so any SDK satisfying the declared constraint also satisfies the lock). This test is red at the current `^3.11.0` and green after the bump.
- floor_guard_still_passes: `test/dart_sdk_floor_test.dart` still passes (it requires minor >= 11; 12 satisfies it).
- lints_resolved: `flutter analyze` reports no issues at language version 3.12 (the nine `prefer_initializing_formals` infos are gone).
- no_regression: `flutter test` passes; no call-site or public named-parameter label changed.

## Reproducibility

- Toolchain: Flutter 3.44.1 / Dart 3.12.1 (pinned per `ci.yml`).
- Verify: `flutter analyze && flutter test`. The CI `analyze` job is fatal-on-info, so the nine lints would fail it at the raised floor unless resolved.

## Risks and Assumptions

- Assumption: no dependency needs re-resolution — `pubspec.lock` already declares `dart ">=3.12.0"`, so the floor edit only makes `pubspec.yaml` agree with it; `flutter pub get` after the edit should be a no-op on the lock. If `pub get` does rewrite the lock, that is out of this spec's scope and stops for review.
- Assumption: the nine conversions preserve every named-parameter label (verified: each flagged param name already matches its field stem), so no caller changes. If any conversion would change a label, that site is left as an explicit assignment instead.
