# SPEC: fix(capture): surface repository write failures when saving a record

## Problem

`_saveRecord` wraps the repository `create()` in `try`/`finally` with no `catch`, so a
save failure gives the user no feedback and silently re-enables the Save button,
leaving them unable to tell whether the record was persisted.

## Design Decision

Add a `catch (e)` to `_saveRecord` that logs via `developer.log(name: 'CaptureScreen')`
and, guarded by `mounted`, shows an error snackbar
(`Não foi possível salvar o registro. Tente novamente.`). On failure the image is kept
and navigation is skipped — `clearImage()` and `context.pop()` run only on success — so
the user retries by tapping Save again (the existing `finally` re-enables the button).
Mirrors the file's existing `_pickImage` / `_classifySoilTexture` error handling.

## Alternatives Considered

- **`SnackBarAction` "Tentar novamente" in the snackbar** — rejected: duplicates the
  Save button (which re-enables on failure) and adds an affordance the issue does not
  ask for, inconsistent with the app's simple-snackbar pattern.
- **Global error boundary (router `errorBuilder` / zone guard)** — rejected: too broad
  for a localized handler-level gap; router-level fallback is a separate concern (#77).

## Scope

- Includes:
  - `catch` in `_saveRecord`: `developer.log` + mounted-guarded error snackbar.
  - On failure: do NOT call `clearImage()` / `context.pop()`; keep the `finally` reset.
  - Widget test for the `create()`-failure path (fake repository whose `create()` throws
    via a provider override).
- Does NOT include:
  - Any retry `SnackBarAction`; changes to the success path; a router error boundary
    (#77); any change to `DriftSoilRecordRepository.create()` or the other handlers.

## Acceptance Criteria

- `save_failure_shows_an_error_snackbar`
- `save_failure_keeps_the_image_and_does_not_navigate_away`
- `save_failure_re_enables_the_save_button`
- `save_success_clears_image_shows_success_and_pops` (happy-path regression guard)
- `flutter_analyze_clean_and_full_suite_green`

## Reproducibility

- `flutter analyze`; `flutter test test/features/capture/capture_screen_test.dart` (+ full suite).
- The failure test extends `buildScreen` to override `soilRecordRepositoryProvider` with a
  fake whose `create()` throws. Versions: Flutter 3.38.5 (CI); local 3.44.1 (#100).

## Risks and Assumptions

- Assumption: `soilRecordRepositoryProvider` is overridable in the widget test.
- Risk: after #70/#71, `create()` can also throw from `saveCapturedImage` (copy failure /
  exclusive-write collision); the `catch` is intentionally broad (a UI boundary) to cover
  every save-failure cause. No ADR — this follows the established handler pattern, no new
  hard-to-reverse decision.
