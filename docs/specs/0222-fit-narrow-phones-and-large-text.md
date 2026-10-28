# SPEC: fix(ui): keep rows, the history toggle and the onboarding whole on narrow phones and large text

## Problem

The visual audit of 2026-10-27 found three places where the app loses or distorts content on a narrow phone (320 × 568) or at 2.0× text.

- **Revealing a history row resizes it (D2).** `SwipeToDelete` makes room for "Excluir" by giving the row `margin: EdgeInsets.only(right: _dragExtent)`.
  - The row therefore gets narrower as it is dragged, up to 104 dp.
  - Its content re-lays out at the narrower width: the "Pendente" badge wraps onto a second line and the row grows taller while the finger moves.
  - PNG 34 keeps the row at its own width: it recedes 12 dp and "Excluir" covers its end.
- **The history toggle is cut at 2.0× text (D3).** The Análises | Coleção toggle sits in a horizontal `SingleChildScrollView` whose width is at least `280 × text scale`.
  - At 2.0× that is 560 dp on a 320 dp screen, so "Coleção" starts off screen and can only be reached by scrolling the toggle sideways.
  - The toggle's labels already shrink to fit their segment (SPEC 0197), so the floor is not needed for them to stay whole.
- **The onboarding leaves little room for its text on a small phone (D4).** `OnboardingPanel` is `376 dp + status bar` tall at every size.
  - At 320 × 568 the panel and the pinned actions take most of the screen, and the step's title and text sit in a sliver that scrolls.
  - §10 of the redesign caps the onboarding illustration at 200 dp on screens up to 360 × 640.

## Design Decision

**Each of the three keeps its size and its content within the screen, by the rule the mock or §10 already gives.**

- **D2: the row recedes, it does not shrink.** The row keeps its full width and recedes up to 12 dp as it is dragged, as today; "Excluir" is drawn over its end, as PNG 34 shows.
  - The row's height while revealed equals its height at rest.
  - Its drag, threshold, haptics, semantics, the 12 dp recede and the 104 dp action width are unchanged; only the margin that narrowed it goes.
- **D3: the toggle fills the list's width at any text size.** The horizontal scroll and its `280 × scale` floor are removed, and the toggle takes the width the list has.
  - Its labels shrink to fit their segment as they already do, and the pill grows in height with the text (`IntrinsicHeight`, as today).
  - Beside a detail pane it keeps fitting the 360 dp list (SPEC 0200).
- **D4: on a small screen the panel is 200 dp tall.** When the screen fits within 360 × 640 dp, at most 360 dp wide and at most 640 dp tall, `OnboardingPanel`'s height below the status bar is 200 dp instead of 376 dp.
  - The 200 × 180 art keeps its canvas and is scaled down to fit, centred, when the panel is shorter than it needs.
  - Larger screens are unchanged.
  - The content above the actions still scrolls, and the actions stay pinned (SPEC 0121).

## Alternatives Considered

- **D2: cover "Excluir" with a row that keeps its margin but clips its content.** Rejected. Clipping would cut the badge's text instead of wrapping it, which is still content lost.
- **D2: slide the whole row 104 dp left, uncovering "Excluir".** Rejected. PNG 34 keeps the row in place, receding 12 dp, with the action over its end.
- **D3: keep the scroll and drop the icons at large text.** Rejected. The toggle would still scroll sideways at 2.0×, and a hidden half of a two-choice control is the defect.
- **D4: shrink the panel in proportion to the text scale.** Rejected. §10 names the small screen, not the text size, and a fixed 200 dp is what it states.

## Scope

- Includes:
  - `SwipeToDelete`'s reveal;
  - the history toggle's width in `history_list.dart`;
  - `OnboardingPanel`'s height on small screens;
  - their tests.
- Does NOT include:
  - the segmented control's own layout, which settings also uses;
  - the other items of the audit: the login spinner (D5), capture's entry (D9), the P2 items, motion (D12), "/12" and the plurals (D8, D13).

## Acceptance Criteria

- `revealed_row_keeps_its_size`: in history at 320 × 568 and 2.0× text, a pending row's height and width are the same before and after a drag that reveals "Excluir", and the "Pendente" badge is one line in both.
- `revealed_row_recedes_under_the_action`: after the reveal, the row's content is offset left by 12 dp at its own width, and "Excluir" is 104 dp wide at the row's right edge.
- `history_toggle_fits_at_large_text`: at 320 × 568 and 2.0× text, both segments of the toggle lie within the screen, and no horizontal `Scrollable` contains the toggle.
- `history_toggle_fits_the_list_pane` (SPEC 0200) still passes.
- `onboarding_panel_is_short_on_small_screens`: at 320 × 568 the panel is 200 dp plus the status bar tall on every step, and at 390 × 844 it is 376 dp plus the status bar.
- `onboarding_fits_small_screens_at_large_text`: at 320 × 568 and 2.0× text, each of the four steps lays out without an overflow, its title is reachable by scrolling, and its actions are on screen.
- Existing tests pass.

## Reproducibility

Flutter 3.44.1, Dart 3.12.1. Run `flutter test`, `flutter analyze` and `mf check`.

## Risks and Assumptions

- **The action covers the row's end.** "Excluir" is painted over the trailing part of the row, its chevron or badge, as PNG 34 draws it; the row's leading thumbnail and title stay visible.
- **Labels shrunk to fit are smaller than the text scale asks.** At 2.0× on 320 dp a toggle label is drawn below 2.0×. That is SPEC 0197's rule for the control, and the alternative is a label off screen.
- **"≤ 360 × 640" is read as a screen that fits within both bounds.** A 360 × 780 phone, common on Android, keeps the tall panel: it is narrow but has the height the panel needs. Reading either bound alone would shorten the panel on most Android phones.
