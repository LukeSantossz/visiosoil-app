# SPEC: feat(feedback): collapse an error region when the correction arrives

## Problem

When a block that showed an error is replaced by the content that fixed it, the swap is one frame. The microinteraction catalogue asks the error region to collapse as the corrected content enters, over `AppMotion.base`, 220 ms (`docs/design/ux-2026/09-microinteractions.md` §3). Nothing in the app does that.

## Design Decision

**`CollapseOnCorrection` animates its child's height only when it leaves an error.** It takes `isError` and the child. While `isError` stays true, or stays false, the child changes size in no time. When `isError` goes from true to false, an `AnimatedSize` aligned to the top runs over `AppMotion.base` with `AppMotion.standard`. The new child is built on that first frame, so the correction is not delayed. Reduced motion uses `Duration.zero`.

**Two in-flow errors use it.** The history filter bar, where the error row is replaced by the chips, and the management-tips block, where `ErrorState` is replaced by the tips or the empty state. Both sit in a column, so the height change is the region.

## Alternatives Considered

- **Animate every swap, including loading into content.** Rejected: the catalogue names the correction, not the arrival of ordinary content.
- **Wrap the full-screen error routes** (home, the history grid, details, preview). Rejected: those bodies already fill the screen, so there is no region height to collapse. A crossfade there would be a different row of the catalogue.
- **Delay the new child until the collapse ends.** Rejected: the same rule as the verdict reveal. The correction is available on the first frame.

## Scope

- Includes:
  - `lib/core/widgets/collapse_on_correction.dart`.
  - `lib/core/features/history/widgets/history_filter_bar.dart` and `lib/core/features/details/management_tips_section.dart`: the two call sites.
  - Tests for each criterion.
- Does NOT include:
  - Full-screen error routes.
  - The filter chips' own colour transition (SPEC 0137).
  - The staggered verdict reveal and the desaturated rejection.

## Acceptance Criteria

- `error_region_collapses`: a region that leaves an error is between the old height and the new one halfway through 220 ms, and at the new height after it.
- `a_swap_that_is_not_a_correction_is_instant`: with `isError` staying false, a shorter child is already the new height on the next frame. An error appearing is instant too.
- `collapse_respects_reduced_motion`: with animations disabled, the frame after the correction is already the new height.
- `filter_error_is_in_the_region`: the history filter's error row is inside `CollapseOnCorrection`.
- `tips_error_is_in_the_region`: the management-tips `ErrorState` is inside `CollapseOnCorrection`.

## Reproducibility

`flutter test test/core/widgets/collapse_on_correction_test.dart test/features/history/history_screen_test.dart test/features/details/management_tips_section_test.dart`

Flutter 3.44.1, Dart 3.12.1.

## Risks and Assumptions

- A correction that is the same height as the error does not move. The two call sites change height.
- The tips block may pass through the loading row on the way to the tips. That row is the correction's first child, and it is what collapses in.
