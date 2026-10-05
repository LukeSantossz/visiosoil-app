# SPEC: feat(theme): give high contrast solid lines, thicker edges and heavier body type

## Problem

The design system defines high contrast for sunlight as "maximum luminance contrast, heavier type weights, thicker borders, and the removal of low-alpha decoration" (`docs/design/ux-2026/05-design-system.md` §6). SPEC 0130 shipped the mode's first slice: a card's edge becomes the solid `outline` instead of a 50 % hairline. It left the rest to later slices.

In the high-contrast palettes on `main`, these still read below the 3 : 1 a component boundary needs:
- **`outlineVariant`, 1.67 : 1 against `surface`.** It draws the secondary button's outline, the onboarding's inactive step dots, the settings avatar's ring and the dividers. Material components that read `colorScheme.outlineVariant` draw with it too.
- **The two warning banners' edges.** The tips disclaimer and the details confidence banner draw their border in `warning` or `error` at 30 % alpha.

And the mode does not yet change:
- **the type.** Body text stays at Inter 400, the lightest weight the app ships.
- **the edges' width.** Every card and banner edge stays 1 dp.

The page against a card is 1.03 : 1 (`12-accessibility.md` §2.2). In high contrast the card's solid edge already separates them, at 4.27 : 1 against the page, so this spec leaves the fills alone.

## Design Decision

**In high contrast, `outlineVariant` is `outline`.** The two high-contrast palettes take their base palette's `outline` as their `outlineVariant`. `copyWith` gains an `outlineVariant` parameter to build them. Every line drawn from the role then reaches `outline`'s ratio, about 4.3 : 1, through the palette and through `ColorScheme`. That covers the secondary button, the step dots, the avatar ring, the dividers and Material's own uses, with no change at their sites.

**A banner's edge is its own text colour in high contrast.** `AppPalette` gains `bannerBorder({required Color accent, required Color onContainer})`:
- outside high contrast, `accent` at 30 %, as today;
- in high contrast, `onContainer`, solid.

The two banners pass their accent and their text colour:

| Banner | `accent` | `onContainer` | High-contrast ratio, light |
| --- | --- | --- | --- |
| Tips disclaimer | `warning` | `onWarningContainer` | 6.63 : 1 |
| Confidence, moderate | `warning` | `onWarningContainer` | 6.63 : 1 |
| Confidence, low | `error` | `onErrorContainer` | 13.26 : 1 |

**Edges are 2 dp in high contrast.** `AppPalette` gains `edgeWidth`, 1 outside high contrast and 2 in it. The five card edges and the two banner edges pass it as their border's width.

**Body type is one step heavier in high contrast.** `AppTypography.textThemeFor` raises each weight by one step the app bundles:
- `bodyLarge`, `bodyMedium` and `bodySmall`, from Inter 400 to 500;
- `labelSmall`, from Inter 500 to 600.

The other styles are already Inter 600 or Manrope 700 and 800, the heaviest weights the app bundles, and stay as they are.

## Alternatives Considered

- **Change each site that draws `outlineVariant`.** Rejected: four sites and every Material default would each need the high-contrast check. The role is what high contrast changes.
- **Make the banner edges `warning` and `error`, solid.** Rejected: `warning` on `warningContainer` is 2.50 : 1, below 3 : 1. The banner's text colour already passes on its own container.
- **Darken the page in high contrast,** so a card's fill stands apart from it. Rejected for this slice: the solid edge already gives the card its boundary, and a new page colour changes every screen's look.
- **Bold every style.** Rejected: the headings are already ExtraBold, and Inter 700 is not bundled. The fallback would be a synthetic bold.

## Scope

- Includes:
  - `lib/core/theme/app_palette.dart`: `outlineVariant` in the high-contrast palettes, `copyWith`'s new parameter, `bannerBorder` and `edgeWidth`.
  - `lib/core/theme/app_typography.dart`: the heavier weights in high contrast.
  - The five card edges and the two banner edges: `management_tips_section.dart`, `info_section.dart`, `last_analysis_section.dart`, `stats_grid.dart`, `settings_screen.dart` and `classification_header.dart`.
  - Tests for each criterion.
- Does NOT include:
  - Any colour or weight outside high contrast.
  - Fills: the page, cards, the history selection tint, and the onboarding and permission icon backgrounds. They are not edges.
  - The native launch screen, as in SPEC 0130.

## Acceptance Criteria

- `hc_lines_reach_3_to_1`: in both high-contrast palettes and their themes' `ColorScheme`, `outlineVariant` is `outline`, and reaches at least 3 : 1 against `surface` and `background`. In `light` and `dark` it is unchanged.
- `hc_banner_edges_read`: in both high-contrast palettes, each banner's `bannerBorder` is its `onContainer`, at least 3 : 1 against its container. Outside high contrast it is `accent` at 30 %. Under the light high-contrast theme, the tips disclaimer draws that colour.
- `hc_edges_are_thicker`: `edgeWidth` is 2 in high contrast and 1 otherwise. Under the light high-contrast theme, an info section card's edge and the tips disclaimer's edge are 2 dp wide.
- `hc_body_type_is_heavier`: in both high-contrast themes, the body styles are `FontWeight.w500` and `labelSmall` is `w600`. In `light` and `dark` they are unchanged.
- `edges_take_the_width`: every `Border.all` under `lib/` that reads `cardBorder` or `bannerBorder` passes `edgeWidth`.
- The existing tests pass. One changes, because this spec changes what it pins: SPEC 0130's `high-contrast palettes differ from their base only there` compared the whole `ColorScheme` with the base's. It now compares it with `outlineVariant` set back to the base's.

## Reproducibility

`flutter test test/core/theme/ test/features/`

Flutter 3.44.1, Dart 3.12.1.

## Risks and Assumptions

- Dividers become as strong as card edges in high contrast. They separate content, so a visible line suits the mode.
- A 2 dp edge moves each card's content 1 dp inward, because a `Container` pads its child by its border. The tightest card, a stat card, still keeps 8 dp of padding inside its edge.
- Inter 500 sets slightly wider than 400. SPEC 0121's layouts already reflow at 200 % text, so a wider weight at the default size fits.
