# SPEC: fix(ui): close the measured gaps on Início, Histórico and the result

## Problem

The Developer asked on 2026-10-26 for "100% de fidelidade ao mock" ("100% fidelity to the mock"). Rendering each screen and comparing every line of ink with its PNG left these gaps after SPEC 0201 to 0203:

- **Buttons.**
  - Every filled and outlined button is 52 dp tall, per the design spec's §1.4.
  - PNG 05, 14 and 15 draw them at 48 dp, and the app's elevated button casts a shadow the mocks do not.
- **Stat cells** (PNG 08, 21). The icon is 20 dp. The mock's is 18 dp, its top 2 dp lower, with the value where it is.
- **Home rows** (PNG 08). A row is 64 dp plus its 1 dp rule; the mock repeats every 64 dp, the rule included.
- **Page titles** (PNG 08, 21). "Início" and "Perfil" are `headlineMedium` at 28 sp. The mock's are 3 % wider and 5 % taller.
- **Result header** (PNG 14).
  - The confidence row sits 2 dp low.
  - The level badge stretches to 60 % of the row; the mock's is as wide as its label.
  - The bar's segments are pills on `surfaceContainerHigh` 2 dp apart. The mock's are square-ended (1.5 dp radius) on `divider`, 2.5 dp apart.
  - The percent is 13 sp; the mock's is 14 sp.
- **Result tabs** (PNG 14). The indicator ends 2 dp above the rule. The mock's indicator sits on the rule, its bottom on the rule's.
- **Result error** (PNG 15). The title sits 2 dp low and the cause 2 dp further.
- **Empty Início** (PNG 09).
  - The card is 57 dp taller than the mock's, set in 16/24 and 14/20.
  - Its drawing does not match the mock's magnifier: a 21 dp lens over two soil lines in `textTertiary`, the lower at half strength.
- **Empty Histórico** (PNG 17).
  - The app centres a Material archive icon in the remaining height.
  - The mock draws, 74.5 dp under the list's top, two record cards behind a dashed one holding a sample. Under it come an 18 sp title, the 14/20 sentence and the action.

## Design Decision

Each value below is read from the 2× PNG, 2 px to the dp, and checked by rendering the screen and comparing its lines of ink with the mock's.

- **`AppTheme`**:
  - elevated and outlined buttons are at least 48 dp tall, with 12 dp vertical padding;
  - the elevated button has no elevation;
  - `AppDensity.standard.buttonHeight` is 48.
  - §1.4's 52 dp gives way to the mocks, as the Developer asked.
- **`StatCell`**: an 18 dp icon after 2 dp, then the existing 12 dp gap.
- **Home rows**: 11.5 dp above and below the 40 dp thumbnail, so a row and its rule repeat every 64 dp.
- **`AppTypography.pageTitle`**: `headlineMedium` resized to 29/36, tracked −0.725, for Início and Perfil.
- **Result header**:
  - 12 dp between the class and the confidence row;
  - the badge hugs its label inside its 24 dp minimum height;
  - the bar's segments have a 1.5 dp radius and are 2.5 dp apart, their track `divider`;
  - the percent is 14 sp;
  - 17 dp between the header and the tabs, and 8 dp from the rule to the overview's first line.
- **`ResultTabBar`**:
  - the rule is drawn under the tabs and the indicator over it, its bottom on the rule's;
  - a tab's extra height goes above its label.
- **`ResultErrorBlock`**: 14 dp under the disc and 6 dp under the title.
- **Empty Início**:
  - a painter at PNG 09's coordinates: the lens and its handle in `primaryText` at 1.5 dp, filled with `primaryContainer` at 55 %, four grains, and two Catmull-Rom soil lines through the mock's sampled points;
  - the card's content 43 dp from its top and 17 dp from its bottom, plus the card's 4 dp;
  - the line at 15/20 in `onSurface` and the sentence at 13/18 in `onSurfaceVariant`.
- **Empty Histórico**:
  - a painter at PNG 17's coordinates:
    - the dashed front card (1.5 dp, 6 dp dashes every 9.5 dp) filled with `primaryContainer` at 55 %;
    - two back cards in `textTertiary` at 45 % and 75 %;
    - the sample square with three grains;
    - two 1.25 dp lines;
  - 74.5 dp from the list's top;
  - the title at 18/24 weight 600, 6 dp above the 14/20 sentence;
  - the action 21 dp lower, with a Lucide `camera`.
  - A history filtered to nothing keeps the existing "Nenhum resultado" state.

## Alternatives Considered

- **Keep 52 dp buttons per §1.4.** Rejected: the Developer asked for the mocks, and every PNG measures 48 dp.

## Scope

- Includes the widgets named above and their tests.
- Does NOT include the camera and processing screens (PNG 10 to 13, 28 to 31, 38), which follow in their own change.

## Acceptance Criteria

- `buttons_are_48_dp`: a themed elevated button is 48 dp tall and has no elevation.
- `home_stats_match_the_mock`: the stat icons are 18 dp.
- `home_recent_rows_show_a_status_dot`: a home row is 63 dp, so with its rule the rows repeat every 64 dp.
- `page_titles_are_29_sp`: "Início" and "Perfil" are 29 sp.
- `confidence_row_matches_the_mock`:
  - the badge is narrower than half the row;
  - the empty segment is `divider`;
  - the percent is 14 sp.
- `tab_indicator_sits_on_the_rule`: the indicator's bottom equals the rule's.
- `empty_history_matches_the_mock`: the empty history shows its drawing, "Nenhuma análise ainda" at 18 sp, and "Fazer primeira análise" with `LucideIcons.camera`.
- Existing tests pass, updated where they pinned the measures above.

## Reproducibility

Flutter 3.44.1, Dart 3.12.1. Run `flutter test`, `flutter analyze` and `mf check`.

## Risks and Assumptions

- The drawings follow the mock's measured points, not its source paths, so a curve can differ by a fraction of a dp between samples.
