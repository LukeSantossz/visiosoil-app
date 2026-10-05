# SPEC: feat(theme): give high contrast solid fills where the alpha was doing the work

## Problem

High contrast still paints structure with a low alpha. SPEC 0135 made the edges solid and left the fills: the page against a card is 1.03 : 1 in the light palette, the history selection is `primary` at 30 %, the onboarding discs are an accent at 12 %, and the permission icon's disc is `warning` at 15 %. The design system defines the mode as the removal of that low-alpha decoration (`docs/design/ux-2026/05-design-system.md` §6).

## Design Decision

**In high contrast the page uses a fill that already exists, and the card stays `surface`.** The light page becomes `surfaceVariant`. The dark page becomes `scrim`. `copyWith` gains a `background` parameter to build them. Outside high contrast the pages are unchanged. The card edge from SPEC 0135 stays.

**A disc uses its accent's container, and the icon uses the container's ink.** `discFill(accent, alpha:)` is `accent` at `alpha` outside high contrast, and the matching container in it: `primaryContainer`, `secondaryContainer`, or `warningContainer`. `discInk(accent)` is the accent outside high contrast, and `onPrimaryContainer`, `onSecondaryContainer`, or `onWarningContainer` in it. The onboarding discs and the permission disc go through them. An accent that is none of those three keeps today's alpha, so a new accent cannot turn into the wrong container.

**A selected history thumbnail loses the translucent wash.** In high contrast the overlay is transparent and draws `primary` at `edgeWidth` around the photograph. Outside high contrast it stays `primary` at 30 %. The unselected check's fill is `surface` in high contrast and white at 80 % otherwise. The selected check stays `primary`.

## Alternatives Considered

- **Darken the page with a new colour.** Rejected: `surfaceVariant` and `scrim` are already in the palette, and a new hex would be a second page colour to keep in contrast.
- **Paint the selection as solid `primary`.** Rejected: the photograph would disappear. The border marks the selection and leaves the picture visible.
- **Leave the page, because the edge already separates the card.** Rejected for this slice: SPEC 0135 recorded that and left the fill. This spec is that fill.

## Scope

- Includes:
  - `lib/core/theme/app_palette.dart`: the high-contrast pages, `copyWith`'s `background`, `discFill` and `discInk`.
  - The onboarding discs, the permission disc, and the history selection overlay and unselected check.
  - Tests for each criterion.
- Does NOT include:
  - Edges, type, or anything outside high contrast.
  - The capture scrims. Their alpha is load-bearing for text on a photograph (`12-accessibility.md` §2.1).
  - The native launch screen.

## Acceptance Criteria

- `hc_page_separates_from_the_card`: in light high contrast the page is `surfaceVariant`, and in dark high contrast it is `scrim`. Each contrasts with `surface` by more than its base palette does. In `light` and `dark` the page is unchanged. The light high-contrast theme's scaffold uses that page.
- `hc_discs_are_solid`: in both high-contrast palettes, `discFill` of `primary`, `secondary` and `warning` is that accent's container, and `discInk` is the container's ink, at least 4.5 : 1 on the container. Outside high contrast, `discFill` is the accent at the given alpha and `discInk` is the accent. Under the light high-contrast theme, the first onboarding disc and the permission disc draw those colours.
- `hc_selection_is_a_border`: under the light high-contrast theme, a selected history thumbnail's overlay is transparent with a `primary` border of `edgeWidth`, and an unselected check is filled with `surface`. Under `light`, the overlay is `primary` at 30 % and the unselected check is white at 80 %.
- The existing tests pass. One changes: SPEC 0135's comparison of the high-contrast `ColorScheme` with the base is unchanged, because the page is not a `ColorScheme` field. The scaffold test is new.

## Reproducibility

`flutter test test/core/theme/app_palette_test.dart test/features/onboarding/onboarding_screen_test.dart test/features/history/history_screen_test.dart test/core/widgets/permission_denied_view_test.dart`

Flutter 3.44.1, Dart 3.12.1. If the permission view has no test file, the disc assertion lives in `app_palette_test.dart` and a widget test next to the view.

## Risks and Assumptions

- `surfaceVariant` on `surface` in the light palette is a small step. It is larger than today's 1.03 : 1, and the 2 dp edge remains the boundary.
- A disc whose accent is not `primary`, `secondary` or `warning` does not change in high contrast. The three steps and the permission view use only those.
