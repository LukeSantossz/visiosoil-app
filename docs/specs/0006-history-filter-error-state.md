# SPEC: fix(history): surface texture-filter load errors instead of hiding the chip bar

## Problem

When `availableTextureClassesProvider` fails, the history chip-bar `error`
branch renders `SizedBox.shrink()`
(`lib/core/features/history/history_screen.dart:208`), silently hiding the
texture filter with no indication anything failed — a silent-failure pattern the
project's conventions forbid.

## Scope

- Includes:
  - Replace the chip-bar `error` branch with a compact inline error affordance
    (a visible message plus a retry control that invalidates
    `availableTextureClassesProvider`), sized for the chip-bar band rather than
    the full-screen `ErrorState` the records grid uses.
  - A widget test covering the error branch (provider overridden to fail) and
    the retry.
- Does NOT include:
  - The `loading` and `data` branches of the same `.when`.
  - The records-grid error handling (already covered).
  - A shared error-state redesign (#9) or changing the provider.

## Acceptance Criteria

- `filter_error_branch_renders_visible_feedback_and_retry`: when
  `availableTextureClassesProvider` errors, the chip-bar area shows a visible
  message and a retry control instead of `SizedBox.shrink()`.
- `filter_error_retry_invalidates_the_provider`: tapping retry re-reads
  `availableTextureClassesProvider` (a provider that first fails then succeeds
  shows the chips after retry).
- `existing_history_screen_tests_stay_green`.
