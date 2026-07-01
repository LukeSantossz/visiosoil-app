# SPEC: perf(preview): replace synchronous existsSync gate with image errorBuilder

## Problem

`_ImageViewer.build` calls `imageFile.existsSync()` on the UI thread on every build to choose
between `Image.file` and a broken-image icon — synchronous filesystem I/O in build, redundant
with the `errorBuilder` that `Image` already provides.

## Design Decision

Remove the `existsSync()` gate and render `Image.file(imageFile, fit: BoxFit.contain,
errorBuilder: ...)` unconditionally, moving the existing
`Icon(Icons.broken_image, color: Colors.white54, size: 64)` into the `errorBuilder`. Mirrors the
established `_ThumbnailImage` pattern in `history_screen.dart`, preserving the exact fallback
visual suited to the black preview backdrop.

## Alternatives Considered

- **Move `existsSync` off the UI thread via a `FutureBuilder`** — rejected: adds a loading state
  and complexity for a check `errorBuilder` already subsumes, against the issue's idiomatic
  direction.
- **Adopt history's themed error container** (`surfaceContainerHighest` + error color) — rejected:
  the preview backdrop is black; the current white54 icon is the correct styling to keep, and
  changing visuals is out of scope.

## Scope

- Includes:
  - Remove the `existsSync()` gate in `_ImageViewer.build`.
  - Add an `errorBuilder` to `Image.file` returning the existing broken-image `Icon`.
  - New `test/features/preview/image_preview_screen_test.dart`.
- Does NOT include:
  - Changing the fallback styling, or adding a loading `frameBuilder`.
  - Touching `_ThumbnailImage`/history or any other screen.
  - Changes to record lookup, `_InfoPanel`, `_TopBar`, or `_RecordNotFoundView`.

## Acceptance Criteria

- `preview_image_file_has_error_builder_rendering_broken_image_fallback` (locate the `Image.file`;
  its `errorBuilder` is non-null and, when invoked, yields `Icons.broken_image`)
- `existsSync_gate_removed_from_image_viewer_build` (the synchronous `existsSync()` no longer
  appears in `_ImageViewer.build`; verified in the diff)
- `flutter_analyze_clean_and_full_suite_green`

## Reproducibility

- `flutter analyze`; `flutter test test/features/preview/image_preview_screen_test.dart`
  (+ full suite). The test overrides `soilRecordByIdProvider` (pattern from
  `details_screen_test.dart`) to supply a record whose `imagePath` is a real temp file, pumps
  `ImagePreviewScreen`, finds the `Image`, and invokes its `errorBuilder` directly. Flutter 3.x /
  Dart 3.10.4+.

## Risks and Assumptions

- Assumption: inspecting and directly invoking `Image.errorBuilder` is a sound, deterministic
  test — real `FileImage` load failures do not resolve under `flutter_test`'s fake-async
  `pumpAndSettle` without `runAsync`, so the builder is exercised directly rather than via I/O.
- Behavior preserved: a missing or undecodable file still shows the same broken-image icon; only
  the mechanism (errorBuilder vs pre-check) changes. No ADR — localized idiomatic refactor.
