# SPEC: feat(history): transition the filter chip's colour and border

## Problem

Selecting a history texture filter swaps the chip's label colour, label weight and border in one frame. The microinteraction catalogue asks for a colour and border transition over `AppMotion.fast`, 140 ms (`docs/design/ux-2026/09-microinteractions.md` §3). SPEC 0134 left that row out.

## Design Decision

**The chip stays a `FilterChip`, and a selection value from 0 to 1 drives the label and the border over `AppMotion.fast` with `AppMotion.standard`.** The value is 1 when the chip is selected and 0 when it is not. The label colour lerps from `colorScheme.onSurface` to `palette.primary`, and the weight from `FontWeight.normal` to `FontWeight.w600`. The border colour lerps from `colorScheme.outline` to `palette.primary`.

**The border is a foreground line on a `Container` around the chip's material, and the chip's own side is `BorderSide.none`.** `FilterChip` paints its side through a `Material` whose shape animation lasts 75 ms (`pressedAnimationDuration` in the framework's chip). Feeding it a lerped side would make the painted line lag the label and finish on that 75 ms clock, not on 140 ms. A foreground `BoxDecoration` border paints the colour it is given on that frame. The radius is `AppRadius.sm`, set on the chip's shape as well so the line and the chip cannot drift.

**The line wraps the material, not the padded tap target.** With `VisualDensity.compact`, the default padded chip is 40 dp tall and the material inside is shorter, centred in that box. A line on the outer box floats off the fill. The chip is `MaterialTapTargetSize.shrinkWrap`, so the container is the material. A slot around it keeps the 40 dp target and sends a tap in the padding to the chip, which is what the padded chip did.

**The first frame is the chip's current selection.** The tween starts at its end value, so a chip that opens selected does not travel in from the unselected colours.

**Reduced motion uses `Duration.zero`.** The catalogue's rule is that no animation runs. The framework would only shorten a normal controller to about 5 % of 140 ms, which is the same shortcut SPEC 0134 refused for the press scale.

The fill and the checkmark stay on `FilterChip`'s own selection animation, about 195 ms. SPEC 0134 already counted that fill as animated. This spec does not retune it. The selected state itself flips with the tap, so the checkmark, the semantics and the haptic are not waiting on the colour.

## Alternatives Considered

- **Replace `FilterChip` with an app-owned chip.** Rejected: the fill, the checkmark, the semantics and the haptic already come from `FilterChip`. A new chip would rebuild them to move two colours.
- **Pass the lerped colour as `FilterChip.side`.** Rejected: the chip's `Material` animates that side over 75 ms, so the line would not match the 140 ms label.
- **Leave the border to that 75 ms animation and tween only the label.** Rejected: the catalogue names the border, and 75 ms is not `AppMotion.fast`.

## Scope

- Includes:
  - `lib/core/features/history/widgets/history_filter_bar.dart`: the transition on `_FilterChip`.
  - `test/features/history/history_widgets_test.dart`: the tests below.
- Does NOT include:
  - Retiming `FilterChip`'s fill or checkmark.
  - `NavigationBar` and `SegmentedButton`. Both already animate their selection.
  - The Material buttons SPEC 0134 left on their own ink.
  - The staggered verdict reveal and the desaturated rejection.

## Acceptance Criteria

- `chip_colour_and_border_transition`: tapping a texture class moves that chip's label colour, label weight and border toward the selected values, and the chip that loses the selection toward the unselected ones. Halfway through 140 ms each is the lerp at `AppMotion.standard.transform(0.5)`. After 140 ms each is at its end. The chip's own side is `BorderSide.none`. The border's box equals the chip's material.
- `chip_padding_still_selects`: a tap in the padding above the material, inside the 40 dp target, selects the chip.
- `chip_transition_respects_reduced_motion`: with animations disabled, the frame after the tap already shows the end colours and weights.
- `chip_starts_on_its_selection`: on the first frame, "Todas" draws the selected colours and a class chip draws the unselected ones.
- `chip_retargets_mid_transition`: a selection that changes again halfway reverses. Halfway back, the label colour, the border and the weight are closer to the new end than they were before the reverse, and at the end they match the new selection.
- The existing history tests pass. The haptic test still finds a `FilterChip`.

## Reproducibility

`flutter test test/features/history/history_widgets_test.dart test/features/history/history_screen_test.dart`

Flutter 3.44.1, Dart 3.12.1.

## Risks and Assumptions

- The line and the chip share `AppRadius.sm`. A later change to one of them alone would split the outline.
- The fill and the checkmark finish after the label and the border, because they keep the chip's 195 ms animation. Accepted above.
