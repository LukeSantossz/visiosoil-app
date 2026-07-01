# SPEC: fix(share): delete temporary share card directory after sharing

## Problem

Every `ShareService.shareRecord` call creates a uniquely-named temp directory holding a
full-resolution PNG card (photo + GPS-derived address) that is never deleted, so sensitive
artifacts accumulate without bound on field devices (#74).

## Design Decision

Wrap the card write and the awaited `SharePlus.instance.share(...)` call in `try`/`finally`;
the `finally` deletes the temp directory recursively, so cleanup runs after the share
completes — on success, failure, or cancellation — never eagerly during it (`share_plus`
reads the file while the sheet is open). The delete is guarded by a narrow `catch` that logs
via `developer.log(name: 'ShareService')` — matching the #72 handler precedent — so a cleanup
failure cannot mask the share result. Tests inject a fake `SharePlatform` through the public
`SharePlatform.instance` setter (the share_plus 12.0.2 federated seam); no production seam is
added.

## Alternatives Considered

- **Fixed well-known path overwritten per share** — rejected: bounds growth to one file but
  permanently leaves the last card (photo + address) resident in temp and races overlapping
  shares, contradicting the privacy concern the issue raises.
- **Sweep-on-next-share / on-startup** — rejected: avoids any delete-after-share race but keeps
  sensitive artifacts resident between shares and never cleans up if the user stops sharing.

## Scope

- Includes:
  - `try`/`finally` cleanup around the card write and share in `shareRecord`.
  - `finally` deletes the temp directory `recursive: true`, inside a logged `catch`.
  - New `test/services/share_service_test.dart` using a fake `SharePlatform` to assert the
    card exists at share time and the directory is gone afterwards.
  - Update the stale "ShareService is not unit-tested" comment in the builder test.
  - Add `share_plus_platform_interface` as a dev-only dependency so the test can reference
    `SharePlatform` (not re-exported by `share_plus`); resolves to the already-locked 6.1.0,
    so the `pubspec.lock` change is limited to its `transitive` -> `direct dev` reclassification.
- Does NOT include:
  - Sweeping historical leaked `visiosoil_share*` directories from already-shipped installs
    (OS evicts app cache under pressure; a follow-up issue can add it if wanted).
  - Changes to card composition, caption, or the photo-missing branch behavior beyond
    asserting it creates no temp artifacts.
  - Surfacing share failures in the UI (#78); any runtime dependency change or unrelated
    transitive-version bumps in `pubspec.lock`.

## Acceptance Criteria

- `deletes_temp_dir_after_successful_share` (card file exists when the platform share runs;
  directory is gone after `shareRecord` returns)
- `deletes_temp_dir_and_rethrows_when_platform_share_throws`
- `shares_caption_only_and_creates_no_temp_artifacts_when_photo_is_missing`
- `flutter_analyze_clean_and_full_suite_green`

## Reproducibility

- `flutter analyze`; `flutter test test/services/share_service_test.dart` (+ full suite).
- Versions: Flutter 3.x / Dart 3.10.4+, share_plus 12.0.2. No randomness involved.

## Risks and Assumptions

- Assumption: an awaited `share()` return means the platform finished reading the card file
  (the issue's own premise); a target app that defers reading could lose it — accepted.
- Assumption: `SharePlus.instance` binds `SharePlatform.instance` lazily on first access, so a
  test installing the fake first is reliable (one isolate per test file).
- Risk: directories leaked by already-shipped builds remain until OS cache eviction. No ADR —
  this is a localized handler-level fix, not a hard-to-reverse decision.
