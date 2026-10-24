# SPEC: fix(widgets): enclose the confidence icon and label in a bordered Sun pill

## Problem

The confidence badge places its icon outside a stadium-shaped container that disappears against Sun's white surface, and the result screen omits the full confidence label required by redesign v11 §1.1, §1.4 and §3.14 (QA items 4 and 8).

## Design Decision

Place the icon and text in a minimal-width Row inside one decorated container with a 6 dp corner radius. Detect Sun through the existing `context.palette.isSun` flag and give only that palette a 2 dp `onSurface` border. Preserve each level's existing container foreground pair.

Add an optional `fullLabel` flag, defaulting to false, independently of compact density. The result's ClassificationHeader enables it to show `Confiança alta/média/baixa` followed by the floored percent. Store full labels in AppStrings. Allow the timestamp to wrap below the badge and the badge text to wrap within the available width at large text sizes. Keep compact labels, thresholds, null/non-finite handling and accessibility announcements unchanged.

## Alternatives Considered

- **Change all badge labels to full labels.** Rejected: home and compact surfaces still need the short labels.
- **Change palette colors to make Sun containers visible.** Rejected: the approved palette uses white containers with black borders; the missing border belongs to the badge.

## Scope

- Includes:
  - ConfidenceBadge layout, radius, Sun border and optional full label.
  - AppStrings full confidence labels and the result header's use of them.
  - Regression tests for geometry, themes, result copy, semantics, thresholds and contrast.
- Does NOT include:
  - Other QA divergences, theme palette changes or a result screen redesign.
  - Changes to classifier thresholds, percentage calculation or retry behavior.
  - Dependency upgrades or unrelated golden updates.

## Acceptance Criteria

- `icon_and_text_are_inside_the_pill`: the decorated container encloses both icon and label and has radius 6.
- `sun_pill_has_black_border`: every confidence level has a white container and a 2 dp onSurface black border in Sun; light and dark have no border.
- `full_labels_preserve_confidence_behavior`: the optional label shows all three approved full labels and floored percentages with the same semantics; default and compact labels remain short.
- `result_shows_full_confidence_label`: the result screen renders the full label with the percentage for each band.
- `badge_contrast_meets_minimum`: rendered text and icon colors have at least 4.5:1 contrast against their containers in every supported palette.
- Existing null/non-finite, threshold, percentage and semantics tests continue to pass.

## Reproducibility

```sh
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter test test/core/widgets/confidence_badge_test.dart test/features/details
flutter analyze
flutter test
```

Flutter 3.44.1, Dart 3.12.1.

## Risks and Assumptions

- The supplied card and approved redesign authorize the scope above; this document records those requirements before implementation.
- Longer labels consume more horizontal space beside the timestamp; verify the existing narrow-screen and large-text result tests.
- Contrast assertions measure palette colors, not real-device sunlight legibility.
