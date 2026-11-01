# SPEC: fix(tips): quiet the tips disclaimer

## Problem

The Dicas page opens on a filled brown banner that weighs more than the tips under it.

- **What it draws.** `_DisclaimerBanner` fills the advisory disclaimer with `warningContainer`, with its icon and text in `onWarningContainer` (PNG 20, SPEC 0205). It sits above the first tip on every Dicas page.
- **Why it is too loud.** The corpus has no human review, so every grounded cell carries this disclaimer (SPEC 0227). The banner therefore shows on every page that has tips. A warning that shows every time stops reading as a warning, and the brown block becomes the first thing the eye lands on.
- **The visual review names it.** The unslop review of 2026-10-31 found it. Its direction is neutral olive-tinted surfaces, with colour kept for the texture classes and for real alerts.
- **Decision.** The Developer approved, on 2026-10-31, making it neutral with a hairline edge and only the icon in colour.

## Design Decision

**The disclaimer has no fill, a card's edge, its text in `onSurfaceVariant`, and only its icon in the warning colour.**

| Part | Today | After |
|---|---|---|
| Fill | `warningContainer` | none, the page shows through |
| Edge | none; in high contrast `bannerBorder(warning)` | `cardBorder` at `edgeWidth`: a hairline, solid and 2 dp in high contrast |
| Icon | `onWarningContainer` | `warningText` |
| Text | `onWarningContainer` | `onSurfaceVariant` |

- `warningText` is the warning tint made for drawing on a surface: 4.5 : 1 or more on white in light, `#FEB968` in dark and `#4A3417` in Modo Sol. The icon needs 3 : 1, so it is legible in every theme.
- Radius 12, padding 12, the 20 dp `info` icon and the 14/20 text stay as PNG 20 sets them.

## Alternatives Considered

- **Keep the fill and lighten it.** Rejected: any tint still reads as an alert block above every tip, which is what the review names.
- **Move the disclaimer to the end of the page.** Rejected: SPEC 0205 puts it first so it is read before the tips, and the review item is about its weight, not its place.

## Scope

- Includes:
  - `lib/core/features/details/management_tips_section.dart`, `_DisclaimerBanner` only;
  - `test/features/details/management_tips_section_test.dart`.
- Does NOT include:
  - the confidence banner and other warning banners, which show only when something is wrong;
  - the disclaimer's text.

## Acceptance Criteria

- `test/features/details/management_tips_section_test.dart`:
  - `disclaimer_comes_first`, amended: the banner is still above the first tip; its decoration has no fill colour and a 1 dp border in `cardBorder`;
  - `disclaimer_colours_only_its_icon`: the icon is `warningText` and the text is `onSurfaceVariant`;
  - `disclaimer_icon_reads_on_its_banner`, amended: in light, dark, both high-contrast palettes and Modo Sol the icon is `warningText`, at 3 : 1 or more on `background`, where SPEC 0127 measured `onWarningContainer` on the fill;
  - `hc_banner_edges_read: the tips disclaimer`, amended: in high contrast the border is `outline` at 2 dp, where SPEC 0135 pinned `onWarningContainer`.

## Reproducibility

Flutter 3.44.1, Dart 3.12.1. Run `flutter test test/features/details/management_tips_section_test.dart`, then `flutter test`, `flutter analyze` and `mf check`.

## Risks and Assumptions

- **Departs from the mock.** PNG 20 draws the filled banner. The Developer chose the review over the mock here, and the mock is not changed.
- **#465 (SPEC 0239) and #468 (SPEC 0242) edit the same file.** #465's hunks are above line 210 and #468's are in `_RecordHeader`, after this banner, so the three merge without a conflict.
