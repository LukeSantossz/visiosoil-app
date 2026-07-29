# SPEC: refactor(theme): snap off-scale spacing and radius to the token scale

## Problem

A design-system re-audit found the home dashboard widgets and a few details/preview cards were hand-tuned to a 20-based rhythm (20/18/14/10/7/6 px paddings and 20/14/32 px radii) that sits off the `AppSpacing` (4/8/12/16/24/32/48) and `AppRadius` (8/12/16/24/999) scales the rest of the app follows. Every other screen (capture, details cards, preview, settings) already uses `AppSpacing.lg` (16) as its canonical padding.

## Design Decision

Snap each off-scale value to its nearest scale step, anchored to the app's established convention (`AppSpacing.lg`/`AppRadius.lg` = 16 is the canonical card/screen padding), and reference the named `AppSpacing`/`AppRadius` constants instead of literals. Where a value is equidistant between two steps — notably `20 px`, halfway between 16 and 24 — the snap table below is authoritative and the target is chosen per component role, not by a single global tie-breaking rule: card paddings and CTA card radii snap down to 16, while the bottom-sheet and splash-logo radii snap up to 24. Sub-token hairline spacers (`2 px`) are left as-is — they are below the scale by intent, not off it. This is a purely visual-hygiene refactor: no behavior, copy, or layout structure changes, only spacing/radius magnitudes move to the nearest token.

Snap table:

| From | To | Applies to |
| --- | --- | --- |
| padding 20 | `AppSpacing.lg` (16) | home hero/primary-action/stats/last-analysis horizontal padding, details content padding |
| padding 18 | `AppSpacing.lg` (16) | hero bottom, primary-action horizontal |
| gap 14 | `AppSpacing.md` (12) | hero/primary-action/last-analysis inter-element gaps |
| padding/gap 10 | `AppSpacing.sm` (8) | stats/last-analysis/classification-header/tips chip padding |
| padding 7, gap 6 | `AppSpacing.sm` (8) | last-analysis chip padding, inline gap |
| radius 20 (cards) | `AppRadius.lg` (16) | primary-action CTA card, capture info chip |
| radius 20 (sheet) | `AppRadius.xl` (24) | preview bottom-sheet top corners |
| radius 14 | `AppRadius.md` (12) | primary-action icon tile |
| radius 32 | `AppRadius.xl` (24) | splash logo container |
| literal 12 / 16 / 4 (on-scale) | `AppRadius.md`/`lg`, `AppSpacing.xs` | history grid/filter, capture preview, misc — reference the constant, no visual change |
| shadow `primary.withValues(0.3)` | `AppColors.shadowBrand` | splash logo (same value, tokenized) |

## Alternatives Considered

- **Snap 20 up to `AppSpacing.xl` (24):** rejected — the whole app already uses `AppSpacing.lg` (16) as screen/card padding, so snapping down to 16 makes the home consistent with every other screen; snapping up to 24 would make the home the outlier in the other direction.
- **Leave the home dashboard as-is:** rejected — it is the one screen built pixel-pushed rather than on tokens; the re-audit flagged it as the highest-value cleanup.
- **Snap the 2 px hairline spacers to `xs` (4):** rejected — doubling them is a visible change for spacers that are intentionally sub-token; left untouched.

## Scope

- Includes:
  - The spacing snaps in `home/widgets/` (hero_section, primary_action, stats_grid, last_analysis_section), `home_screen.dart`, `details/` (details_screen, classification_header, management_tips_section), and `preview/image_preview_screen.dart` per the snap table.
  - The radius snaps in splash, preview, capture preview, and home primary-action per the table, plus replacing on-scale radius/spacing literals with `AppRadius`/`AppSpacing` constants in history grid/filter and capture preview.
  - The splash logo shadow → `AppColors.shadowBrand`.
- Does NOT include:
  - The 2 px hairline micro-spacers (left as intentional sub-token spacers).
  - Any color/typography/motion/component change (spec 0026), or the `share_content_builder` canvas literals.
  - Icon sizes, stroke widths, illustration box dimensions, or gradient-overlay heights — these are element sizes, not layout spacing on the scale.
  - Any change to layout structure, widget tree, or copy.

## Acceptance Criteria

- offscale_absent: the listed files contain no off-scale spacing/radius literals from the snap table (20/18/14/10/7/6 spacing, 20/14/32 radius); they reference `AppSpacing`/`AppRadius` constants.
- no_layout_regression: every existing widget test stays green (the refactor changes magnitudes, not structure).
- visual_inspection: the home, details, preview, splash, and capture screens are inspected on the Android emulator and render coherently with the tightened, on-scale spacing (per the accepted inspection precedent).
- analyze_clean: `flutter analyze` reports no new issues.

## Reproducibility

- Toolchain: Flutter 3.44.1 / Dart 3.12.1 (pinned per `ci.yml`).
- Scale sources: `lib/core/theme/app_spacing.dart`, `app_radius.dart` (mirrored in design system `tokens/spacing.css`).
- Run: `flutter analyze && flutter test`, then inspect the affected screens on an emulator.

## Risks and Assumptions

- Assumption: snapping to the nearest scale step is visually neutral-to-improving (subtle tightening on the home). Spacing changes are at most 4 px, while the largest radius change is 8 px (the splash logo container, 32 → 24); validated screen-by-screen on the emulator before merge, and reversible per site if any reads worse.
- Assumption: no test asserts an exact off-scale pixel value; if one does, it is updated to the snapped value as part of the same change (no behavior change, only the magnitude the test pins).
