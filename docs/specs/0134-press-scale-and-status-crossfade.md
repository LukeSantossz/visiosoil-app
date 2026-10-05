# SPEC: feat(motion): scale buttons on press, and crossfade capture's status chips

## Problem

The microinteraction catalogue names two responses the app does not give yet (`docs/design/ux-2026/09-microinteractions.md` §3):
- **Touch recognised:** a press scale of 0.98 on buttons and 0.92 on icon buttons, over `AppMotion.instant`, 90 ms. Today a button shows only its ink.
- **Processing phase change:** a crossfade of the phase label over `AppMotion.base`, 220 ms, because "swapping one spinner for another reads as a stall; a changing label reads as progress". Today capture's classification chip swaps each phase's label in one frame (SPEC 0116), and so does the location chip when its address arrives.

Roadmap item 12 carries both. SPEC 0126 took item 12's haptics. Its other slices wait on other items: the staggered verdict reveal on item 2, and the desaturated rejection on item 6.

## Design Decision

**`PressScale` scales a button while it is pressed.** It lives in `lib/core/widgets/press_scale.dart`:
- it owns a `WidgetStatesController` and hands it to the button it builds;
- while the controller's states contain `WidgetState.pressed`, it scales the button to its `scale` through an `AnimatedScale`, over `AppMotion.instant` with `AppMotion.standard`;
- when the platform asks for reduced motion, the scale changes in no time (SPEC 0120's rule).

The pressed state is the one Material's ink already follows, so the scale starts and ends with the ink. A disabled button never enters it, so it never scales.

**The two shared buttons use it.** `VisioButton` builds its `ElevatedButton`, `OutlinedButton` or `TextButton` inside a `PressScale` of 0.98. `VisioIconButton` builds its `IconButton` inside one of 0.92. Since SPEC 0131, `VisioIconButton` builds every icon button in the app.

Nine Material buttons are still built directly, and keep their ink only:
- the actions of the two dialogs, `confirmDestructiveAction` and details' location choice;
- the home's "Ver tudo", settings' "Sair" and the history filter bar's "Tentar novamente";
- onboarding's "Pular" and its next button.

Moving them onto `VisioButton` is roadmap item 9's consolidation, not motion.

**Capture's two status chips crossfade.** In `CaptureImagePreview`, the location chip and the classification chip each sit in an `AnimatedSwitcher` over `AppMotion.base`, or no time under reduced motion. Each chip is keyed by its label, so a new phase, a result, a failure or an address crossfades in.

The chips sit in a `Wrap` aligned to the start, so the two chips of a crossfade are stacked aligned to the start too, and the incoming one does not move.

During the crossfade the outgoing chip is drawn but excluded from semantics. The classification chip is a live region (SPEC 0116), so the screen reader still announces only the new phase.

## Alternatives Considered

- **A `Listener` on pointer down and up.** Rejected: it would also scale a disabled button, and a scroll that starts on a button. The pressed state already settles both.
- **Scale every tappable surface,** such as the home's record row and the history thumbnails. Rejected: the catalogue names buttons and icon buttons. A row or a card shrinking reads as a layout shift, and their ink is their response.
- **Animate the history filter chips' label and border colours** as the catalogue's "chip or tab selection" row asks. Left out: `FilterChip` already animates its fill when selected, but it draws its label style and border from its values with no transition. Animating them means replacing `FilterChip` with the app's own chip, which is its own change. `NavigationBar` and `SegmentedButton` already animate their selection.

## Scope

- Includes:
  - `lib/core/widgets/press_scale.dart`.
  - `lib/core/widgets/visio_button.dart` and `lib/core/widgets/visio_icon_button.dart`: the press scale.
  - `lib/core/features/capture/widgets/capture_image_preview.dart`: the two crossfades.
  - Tests for each criterion.
- Does NOT include:
  - The staggered verdict reveal (item 2), the desaturated rejection (item 6), and the collapse of a corrected error.
  - The filter chips' colour transition, as above.
  - Any change to the chips' copy, which SPEC 0116 and SPEC 0105 set.
  - The nine Material buttons built directly, as above.

## Acceptance Criteria

- `button_press_scales`: pressing a `VisioButton` scales it to 0.98 over 90 ms, and releasing it returns it to 1.
- `icon_button_press_scales`: pressing a `VisioIconButton` scales it to 0.92, and releasing it returns it to 1.
- `disabled_button_does_not_scale`: pressing a `VisioButton` or a `VisioIconButton` whose `onPressed` is null leaves it at 1.
- `press_scale_respects_reduced_motion`: with animations disabled, the scale's duration is zero.
- `phase_label_crossfades`: when the classification chip moves from one phase to the next, both labels are drawn halfway through 220 ms, and only the new one after it. The location chip does the same when the address arrives.
- `crossfade_announces_only_the_new_label`: halfway through the crossfade, the old label is not in the semantics tree.
- `crossfade_respects_reduced_motion`: with animations disabled, the new label replaces the old one in the next frame.
- The existing tests pass unchanged.

## Reproducibility

`flutter test test/core/widgets/ test/features/capture/`

Flutter 3.44.1, Dart 3.12.1.

## Risks and Assumptions

- A scale of 0.98 on a full-width button moves its edges by about 4 dp each side, which is the visible part of the response. The button's layout size does not change, so nothing around it moves.
- While both chips of a crossfade are drawn, the switcher is as wide as the wider one. When the location chip's address arrives, the classification chip beside it moves at the start of the crossfade, where it moves today when the label swaps.
