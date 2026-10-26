# SPEC: fix(details): match the result in Modo Sol to PNG 26, and space the bar's actions

## Problem

The Developer asked on 2026-10-26 for "100% de fidelidade ao mock" ("100% fidelity to the mock"). Rendering the result in Modo Sol and comparing every line of ink with PNG 26 leaves these gaps. One of them, the actions' spacing, holds in every theme.

- **App bar.**
  - The bookmark and share actions touch. PNG 13, 14, 26 and 32 draw them 4 dp apart, the bookmark centred 4 dp further left.
  - In Modo Sol the back arrow is centred at 28 dp and the title starts at 60 dp. PNG 26 and 38 centre the arrow at 32 dp and start the title at 68 dp, because the 56 dp target sits in a 64 dp slot.
- **Date chip.**
  - The app draws it in Modo Sol's heavier weight on `onSurface` at 75 %.
  - PNG 26 keeps light mode's 12.5 sp at weight 500, on `onSurface` at 67 %.
- **Badge.** The app writes "Confiança alta" in `primaryText`. PNG 26 writes it in ink, `onSurface`.
- **Bar.**
  - The app draws 6 dp segments 2.5 dp apart, the empty one in `divider`, which Modo Sol paints black.
  - PNG 26 draws 10 dp segments 2 dp apart, each inside a 1 dp ink rule, the empty one white.
- **Percent.** The app uses 14 sp; PNG 26 uses 15 sp.
- **Mini triangle**, in every theme. The overview's triangle and its labels sit 3.5 dp lower than PNG 14 and 26 draw them.
- **Tabs.**
  - The app sets the labels at 14 sp, the selected one in `primaryText`, and the 56 dp target pushes them 8 dp below where light mode has them.
  - PNG 26 sets them at 15.5 sp in ink, the selected one at weight 600. Its labels sit where light mode's sit, and its 2 dp rule is drawn 2 dp lower, under the taller line.

## Design Decision

Each value below is read from the 2× PNG 26, 2 px to the dp.

- **`resultAppBar`** puts 4 dp between the bookmark and share, in every theme.
- **`VisioAppBar`'s leading slot** is the density's target plus 8 dp: 56 dp as before, and 64 dp in Modo Sol.
- **`_DateChip`** in Modo Sol:
  - 12.5 sp at weight 500, set through `AppTypography.weighted`, so Modo Sol's heavier axis does not override it;
  - on `onSurface` at 67 %.
- **`_LevelBadge`** in Modo Sol writes its label in `onSurface`, whatever the level, as Modo Sol draws ink on white.
- **`SegmentedConfidenceBar`** in Modo Sol:
  - 10 dp segments 2 dp apart, each with a 1 dp `onSurface` rule;
  - filled ones in the level's colour and empty ones in `surface`.
- **The percent** is 15 sp in Modo Sol.
- **The overview's triangle** moves 3.5 dp up, in every theme.
- **`ResultTabBar`** in Modo Sol:
  - labels at 15.5/22 in `onSurface`, the selected one at weight 600 and the others at 500;
  - the extra target height is taken from the gap above the bar, so the labels keep light mode's place.
  - The details screen's gap above the tabs becomes 17 dp less the target's excess over 48 dp.

## Alternatives Considered

- **Drop Modo Sol's tab target to 48 dp.** Rejected: §2's 56 dp target is an accessibility rule. Taking the extra height from the gap above keeps both the target and PNG 26's labels.

## Scope

- Includes:
  - `resultAppBar`, `VisioAppBar`'s leading width, the classification header's date chip, badge and percent;
  - `SegmentedConfidenceBar`, `ResultTabBar`, the details screen's gap above the tabs, and the overview triangle's offset;
  - their tests.
- Does NOT include:
  - values such as the date, the class and the percent, which are data.

## Acceptance Criteria

- `bar_actions_are_4_dp_apart`: the bookmark and share centres are 52 dp apart, two 48 dp targets with 4 dp between them.
- `sun_leading_slot_is_64_dp`: in Modo Sol the back arrow is centred 32 dp from the edge and the title starts at 68 dp.
- `sun_header_matches_the_mock`:
  - the date's text is 12.5 sp at weight 500;
  - the badge's text is `onSurface`;
  - segments are 10 dp tall, 2 dp apart, with a 1 dp `onSurface` rule, the empty one in `surface`;
  - the percent is 15 sp.
- `overview_triangle_sits_3_5_dp_higher`: the overview's triangle starts 8.5 dp under its heading, the section's 12 dp less 3.5.
- `sun_tabs_keep_their_place`:
  - the tab bar's rule lies 74.5 dp under the bar's segments, as PNG 26 measures;
  - it is 15.5 sp in `onSurface`;
  - the indicator still sits on the rule.
- Existing tests pass.

## Reproducibility

Flutter 3.44.1, Dart 3.12.1. Run `flutter test`, `flutter analyze` and `mf check`.

## Risks and Assumptions

- PNG 26 shows only the high level. The moderate and low badges in Modo Sol take the same ink, which Modo Sol's black-on-white rule implies.
