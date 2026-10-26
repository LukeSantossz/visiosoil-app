# SPEC: fix(ui): match the settings row icons, the unavailable backup row and Início's empty stats to the mocks

## Problem

The Developer asked on 2026-10-26 for "100% de fidelidade ao mock" ("100% fidelity to the mock"). A second render pass at 390 × 844 dp with Inter found three gaps that SPEC 0215 leaves open.

- **Row icons.**
  - Every settings row draws its icon at 22 dp.
  - PNG 23, 35 and 36 draw its ink 2 dp smaller on each row (sun, phone, ruler, languages, scan, user), which is a 20 dp icon.
  - The text still starts 66.5 dp in, in both.
- **Backup na conta.**
  - Without a linked account the row is drawn at full strength.
  - PNG 23 greys its title and its line to 55 % and keeps the icon green, as the redesign's §3.12 says: "Requer conta vinculada" (desabilitado).
- **Início's stat cards.**
  - SPEC 0203 holds the row at 120 dp at least, so PNG 09's empty Início draws cards 16 dp taller than its 104 dp. "Recentes" and the empty card sit 16 dp low.
  - PNG 08's cards are 120 dp only because "última confiança" wraps to two lines.

## Design Decision

Measured on the 2× PNGs, 2 px to the dp.

- **Icons.**
  - A settings row's icon is 20 dp in every theme.
  - It sits at the start of a 22 dp slot, so the text keeps its place.
  - This covers `SettingsTile`, `SettingsSwitchTile`, and the Tema and Tamanho do texto rows.
- **An unavailable row.** `SettingsTile` takes `enabled`.
  - When it is false, the title and the line are drawn at 55 % of their colour.
  - The icon keeps its colour, and the row offers no chevron and no tap.
  - Backup na conta is unavailable while no account is linked.
- **Início's stats.**
  - `StatsGrid` stops forcing 120 dp.
  - The cards take the tallest card's content height: 104 dp in PNG 09, and 120 dp in PNG 08, where a label wraps.
  - `StatsRow` keeps its `minHeight`, for callers that need one.

## Alternatives Considered

- **Grey the icon too.** Rejected: PNG 23 keeps the backup row's icon in `primaryText`.

## Scope

- Includes `SettingsRowFrame`'s icon slot, the settings and profile row icons, `SettingsTile.enabled`, Backup na conta, `StatsGrid`, and their tests.
- Does NOT include the linked backup row's "Último: hoje, 10:45" and "Fazer agora", which wait on a sync backend.

## Acceptance Criteria

- `settings_row_icons_are_20_dp`: a row's icon is 20 dp, and its text starts where a 22 dp icon's did.
- `unavailable_row_is_greyed`: a `SettingsTile` with `enabled: false`:
  - draws its title and its line at 55 % of their colour;
  - keeps its icon colour;
  - has no chevron.
- `backup_is_unavailable_without_an_account`: Configurações with no account draws Backup na conta unavailable.
- `stats_cards_take_their_content_height`: Início's stat row is 104 dp when no label wraps.
- Existing tests pass, with SPEC 0203's 120 dp minimum replaced by the content height.

## Reproducibility

Flutter 3.44.1, Dart 3.12.1. Run `flutter test`, `flutter analyze` and `mf check`.

## Risks and Assumptions

- SPEC 0203's acceptance criterion "each at least 120 dp tall" no longer holds for Início. This spec supersedes it, because PNG 09 draws 104 dp.
