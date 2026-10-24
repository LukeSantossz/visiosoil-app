# SPEC: feat(history): adopt the v11 analysis list

## Problem

History still presents thumbnail cards instead of the v11 date-grouped analysis list and lacks reversible swipe deletion, collection browsing, and offline feedback.

## Design Decision

Reuse AnalysisTile, SwipeToDelete, SegmentedControl, and StatCell/StatsRow with the existing theme tokens. Group records by local calendar date, retaining search, texture filtering, pagination, and selection/comparison. Hide a deleted row locally until the five-second undo snackbar closes; only then call the destructive repository operation, preserving the original record and stream order when undone. Minimally repair SwipeToDelete to keep its thumbnail visible, restore its internal state on undo, and expose snackbar completion; give AnalysisTile an optional history presentation for time/confidence and chevron, a long-press callback, and a wrapping layout for narrow rows and large text without changing existing callers. Add the deferred OfflineBanner shared component and keep the twelve USDA reference color tokens separate from the model vocabulary.

## Alternatives Considered

- Delete immediately and recreate on undo: rejected because deletion erases content and cached tips, and recreation changes identity and ordering.
- Implement a separate history swipe widget: rejected because it duplicates the base component and leaves its thumbnail defect unresolved.
- Retain thumbnail cards: rejected because they contradict the approved list design.

## Scope

- Includes: history screen and feature widgets, date headings, summaries, twelve reference collection classes, local earned-class indications, shared OfflineBanner with offline pending counts, loading/error/empty/filter states, reversible swipe deletion, existing selection/comparison and pagination, focused shared-component fixes, and widget tests.
- Does NOT include: field grouping or registration, sample fractions, alternate predictions, mock records, sync backend implementation, other screens, dependencies, commits, or publishing.

## Acceptance Criteria

- Light, dark, and Sun themes render populated, empty, loading, error, offline, and collection states with accessible labels.
- History groups by date, computes summaries from real records, and preserves filters, selection/comparison, and pagination.
- Swipe retains the entire thumbnail and exposes an Excluir semantics action; undo restores the same record at its original position without a repository write.
- Snackbar expiry commits deletion once; repository failure restores the row and reports an error.
- Offline copy distinguishes one pending analysis from zero or multiple pending analyses.
- Empty history offers Fazer primeira análise; filtered emptiness offers filter guidance.

## Reproducibility

Flutter 3.44.1 / Dart 3.12.1, with `$HOME/flutter/bin` on PATH:

```sh
dart run build_runner build --delete-conflicting-outputs
flutter analyze
flutter test
```

## Risks and Assumptions

- The supplied task and approved v11 design authorize this implementation scope.
- Collection shows reference USDA classes; earned classes are only exact recorded labels, never invented model outputs.
- Pending deletion is intentionally in memory until snackbar completion; process termination during that interval retains the record.
- Repository streams provide newest-first order and persisted record identifiers.

## Reference

Design: `/workspace/visiosoil-mocks/spec-dev/SPEC.md`, §3.7, §4, §8, §11, §14–§16; PNGs 16, 17, 18, and 34. Base components: SPEC 0183.
