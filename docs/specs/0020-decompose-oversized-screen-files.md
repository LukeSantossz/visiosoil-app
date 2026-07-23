# SPEC: refactor(ui): decompose oversized screen files and model capture state

## Problem
The four largest screen files concentrate layout, state, and orchestration in one
place, making them the hardest screens to change safely — and the least
widget-tested (#27). `capture_screen.dart` (614 lines) additionally spreads its
state across five mutable booleans (`_isLoading`, `_isClassifying`, `_isSaving`,
`_isCapturing`, `_classificationFailed`) plus a `_requestGeneration` token, set
across many `setState` calls.

## Design Decision

**Extraction strategy (home, details, history, capture layout).** Extract each
cohesive section into its own **feature-scoped public widget** under a
`widgets/` subfolder of the feature directory (e.g.
`home/widgets/hero_section.dart` exposing `class HeroSection`). Public (not
underscore-private) so each extracted widget is directly widget-testable — which
is the point, since these screens are the coverage gap (#27). They are imported
only within their feature, so they stay effectively feature-internal without a
`part`/`part of` split. Move magic ARGB color literals and ad-hoc sizes into the
existing theme tokens (`AppColors`, `AppSpacing`, `AppRadius`) as they are
extracted.

Per screen:
- **home_screen.dart** (504) → extract `HeroSection` (~116 lines, `:47-163`) and
  `LastAnalysisSection` (~140 lines, `:364-503`); move the raw ARGB literals
  (`:80,110,196,324,399`) to theme tokens.
- **details_screen.dart** (515) → extract `ClassificationHeader` (~90 lines,
  `:147-237`) and replace its inline low-confidence banner (`:212-233`) with the
  already-extracted `_LowConfidenceBanner` pattern (dedupe).
- **history_screen.dart** (598) → extract the filter bar (`_buildFilterBar`,
  ~83 lines) into a `HistoryFilterBar` widget.
- **capture_screen.dart** (614) → extract the permission-denied branch of
  `build` (`:337-358`) into a `CameraPermissionDeniedView`-style widget and the
  capture action column into its own widget, so `build` drops well under
  50 lines. (`_ImagePreview`/`_InfoChip` are already extracted within the file
  and move to `widgets/`.)

**Capture state model.** Replace the five scattered booleans + token with a
single immutable `CaptureUiState` value held in one field and updated via
`setState(() => _state = _state.copyWith(...))`. Because location and
classification run **concurrently** (`Future.wait([_fetchCurrentLocation,
_classifySoilTexture])`), a single flat mutually-exclusive enum would be wrong;
the state is composed of independent axes:

```
enum LocationStatus { idle, loading, resolved, unavailable }
enum ClassificationStatus { idle, running, done, failed }

class CaptureUiState {
  final LocationStatus location;      // replaces _isLoading (+ the lat/lng/address payload)
  final ClassificationStatus classification; // replaces _isClassifying + _classificationFailed
  final bool isCapturing;             // camera-picker re-entry guard
  final bool isSaving;                // save re-entry guard
  final int generation;               // stale-result token (was _requestGeneration)
  final AppPermissionStatus? cameraPermission;
  // + the resolved payloads: latitude/longitude/address, classificationResult
}
```

The location/classification payloads (`_latitude`, `_longitude`, `_address`,
`_classificationResult`) move into the state object alongside their status. This
removes every scattered `bool _x` field, makes the two concurrent operations'
status explicit and cohesive, and preserves the exact current transitions and
the generation-token stale-result rejection.

## Alternatives Considered
1. **A single flat `enum CaptureState`** (idle/capturing/classifying/saving/…).
   Rejected: location and classification are independent and run in parallel, so
   one mutually-exclusive enum cannot represent "locating **and** classifying at
   once" without either serializing them (a behavior change) or inventing product
   states (`locatingAndClassifying`, …) that combinatorially explode. The
   composite state above is the honest model. **This deviates from the issue's
   literal "sealed/enum state" wording — flagged for approval at the Gate.**
2. **`part` / `part of` to keep extracted widgets underscore-private.** Rejected:
   keeps them private but leaves them un-testable in isolation, defeating the
   #27 coverage goal that motivates the decomposition; feature-scoped public
   widgets are the more testable, more idiomatic choice.
3. **One big-bang PR for all four screens + the state model.** Rejected in favor
   of the execution split below: capture's state rewrite is behavior-sensitive
   and the screen is currently untested, so it must not ride in the same review
   as the low-risk pure extractions.

## Execution Plan (recommended: two PRs under this issue)
- **PR 1 — pure extractions + theme tokens (home, details, history):** mechanical
  section extraction and magic-literal → token moves, each extracted widget paired
  with a widget test (#27). Behavior-preserving; low risk.
- **PR 2 — capture decomposition + `CaptureUiState`:** FIRST add characterization
  widget tests for the current capture flows (capture → parallel locate/classify
  chips, retry, save, discard, permission-denied), then extract the layout and
  introduce `CaptureUiState` under those tests. Higher risk, isolated for review.

## Scope
- Includes: the extractions, theme-token moves, `ClassificationHeader` banner
  dedupe, the `CaptureUiState` model, and the widget tests paired with each slice.
- Does NOT include: changing any screen's behavior, routes, copy, or provider
  graph; touching `InferenceService`/the model; screens not listed
  (`preview` 305, `management_tips_section` 399, `settings` 274, `onboarding`,
  `splash`) — they are under the ~300-line bar or out of the issue's four.

## Acceptance Criteria
- No touched screen file exceeds ~300 lines; no `build` method in a touched
  screen exceeds ~50 lines.
- Capture state is the single `CaptureUiState` value object; the five booleans
  and the loose `_requestGeneration` field are gone from `_CaptureScreenState`.
- Behavior unchanged: the full existing suite stays green, plus the new widget
  tests added with each slice (extracted-widget render tests; capture flow
  characterization tests). Capture-flow tests are proven non-tautological by
  mutation where they assert an action ran.
- `flutter analyze` clean; `flutter test` green.

## Reproducibility
Toolchain Flutter 3.44.1 / Dart 3.12.1. `flutter analyze && flutter test`.

## Risks and Assumptions
- The capture state rewrite is the one behavior-sensitive change and the screen
  has no current widget tests. Mitigation: characterization tests are written and
  green against the *current* code before the state model is introduced, so any
  transition drift turns them red (PR 2 ordering above).
- `~300 lines` / `~50 lines` are guide rails, not hard gates; a screen a few
  lines over after honest extraction is acceptable and noted rather than padded
  with artificial files.
- Making extracted widgets public slightly widens the feature's surface; they are
  imported only within their feature and carry no public doc contract.
