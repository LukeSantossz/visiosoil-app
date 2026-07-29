# SPEC: feat(theme): close three design-system token gaps (warning, motion, destructive button)

## Problem

A design-system re-audit found three usage gaps where the app defines or hardcodes a value the design system already tokenizes: the moderate-confidence foreground color is a raw literal, there is no motion token layer, and the button component lacks the design system's `destructive` variant.

## Design Decision

Three additive, behavior-preserving changes, each closing one gap without touching layout:

1. Add `AppColors.onWarningContainer = Color(0xFF6D4C1D)` (the design system's `--vs-on-warning-container`) and point `ConfidenceLevel.moderate.foregroundColor` at it, matching the high/low branches that already use `onPrimaryContainer`/`onErrorContainer`.
2. Add an `AppMotion` token layer (`lib/core/theme/app_motion.dart`) mirroring the design system's `motion.css` — durations `instant 90 / fast 140 / base 220 / slow 380 / reveal 640` ms and curves `standard / emphasized / out` — and point the three real UI animations at it: splash intro → `reveal`, onboarding page transition → `slow`, history thumbnail switch → `base`.
3. Add `VisioButtonVariant.destructive` rendering a `TextButton` with `colorScheme.error` foreground, and route the hand-rolled delete action in `details_screen.dart` through it.

## Alternatives Considered

- **Keep the `0xFF6D4C1D` literal:** rejected — it is the one un-tokenized color in an otherwise fully tokenized confidence switch; a named token removes the drift risk.
- **Leave motion untokenized:** rejected — the design system ships a motion scale; three animations currently pick ad-hoc 800/300/200 ms that miss it. A token layer aligns them and gives future animations a home. (Non-animation timing — service timeouts, the search debounce, permission delays — is deliberately left alone; it is not motion.)
- **Snap splash to a new 800 ms token:** rejected — 800 exceeds the design system's `reveal` max (640); reusing `reveal` keeps the app on the published scale.
- **Keep the hand-rolled destructive `TextButton`:** rejected — it already matches the design system's destructive spec visually, so routing it through the component is zero-visual-risk and closes the component-coverage gap.

## Scope

- Includes:
  - `AppColors.onWarningContainer` constant; `ConfidenceLevel.moderate.foregroundColor` uses it.
  - `lib/core/theme/app_motion.dart` with the five durations and three curves; `splash_screen.dart` (800→`reveal`), `onboarding_screen.dart` (300→`slow`), `history_grid.dart` (200→`base`) reference `AppMotion`.
  - `VisioButtonVariant.destructive` + the `details_screen.dart` delete action routed through `VisioButton`.
- Does NOT include:
  - Any spacing or radius change (that is spec 0027).
  - Changing animation *curves* already in use beyond wiring the new curve tokens where a curve is set.
  - Retiming non-animation `Duration`s (timeouts, debounce, permission/gating delays).
  - The `share_content_builder.dart` canvas literals (it renders a PNG, not widgets, so `AppColors`/`AppTypography` — which return widget types — do not apply; documented exception).

## Acceptance Criteria

- warning_token_used: `AppColors.onWarningContainer == const Color(0xFF6D4C1D)` and `ConfidenceLevel.moderate.foregroundColor` returns it (no raw literal remains in `confidence_level.dart`).
- motion_tokens_match_ds: `AppMotion` exposes `instant/fast/base/slow/reveal` = 90/140/220/380/640 ms and `standard/emphasized/out` curves; the three animation sites reference `AppMotion`, not bare `Duration`s.
- destructive_variant: `VisioButton(variant: destructive)` renders a `TextButton` whose foreground is `colorScheme.error`; the details delete action is a `VisioButton`, not a hand-rolled button, and still triggers the same confirm-delete flow.
- analyze_clean: `flutter analyze` reports no new issues.
- tests_green: `flutter test` passes.

## Reproducibility

- Toolchain: Flutter 3.44.1 / Dart 3.12.1 (pinned per `ci.yml`).
- Token sources: design system `tokens/motion.css`, `tokens/colors.css` (`--vs-on-warning-container: #6D4C1D`), `components/buttons/` (destructive variant).
- Run: `flutter analyze && flutter test`.

## Risks and Assumptions

- Assumption: mapping splash 800→640 and onboarding 300→380 ms is an acceptable, minor timing change (validated by inspection on the emulator). Reversible by choosing a different token.
- Assumption: routing the details delete through `VisioButton(destructive)` preserves the exact confirm dialog + delete + navigation flow; guarded by the existing delete-flow widget test staying green.
