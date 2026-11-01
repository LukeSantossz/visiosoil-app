# SPEC: fix(ui): show one date format

## Problem

A record's date and time are written three ways across the screens.

| Format | Where |
|---|---|
| `01/04/2026 às 14:30` | details' information section, the comparison |
| `01/04/2026 14:30` | the history grid's tiles, the analysis tile's default line, the Dicas head |
| `01/04/2026 · 14:30` | the result screen's date chip, the photo screen |

- **Why it matters.** The same instant reads differently from one screen to the next, so the app looks assembled rather than designed.
- **The visual review names it.** The unslop review of 2026-10-31 found it, as item 4.
- **Decision.** On 2026-10-31 the Developer chose the middle dot for every screen, the format of redesign v11 §3.6.

## Design Decision

**Every screen writes a record's date and time as `dd/MM/yyyy · HH:mm`, through a new `SoilRecord.formattedTimestampDotted`.**

- `formattedTimestampDotted` returns `Formatters.timestampDotted(timestamp)`.
- These places switch to it:
  - details' information section (`info_section.dart`);
  - the comparison (`compare_screen.dart`);
  - the history grid's tile label (`history_grid.dart`, `_TimestampLabel`);
  - the analysis tile's default metadata line (`analysis_tile.dart`);
  - the Dicas head (`management_tips_section.dart`).
- These keep their form, because they are not a date shown on its own:
  - **Shared text** (`Data: … às …`) and **"Atualizado em … às …"**. They are sentences, and "às" reads as one.
  - **Spoken labels** (`Semantics`). They keep `formattedTimestampCompact`, because a screen reader may read the dot aloud.
  - **Home's relative line** (`hoje 14:30 · 87%`). It is a different element, which says when relative to today.

## Alternatives Considered

- **"às" everywhere.** Rejected by the Developer: it is longer and crowds the list lines.
- **A space everywhere.** Rejected by the Developer: the date and the time run together.

## Scope

- Includes:
  - `lib/models/soil_record.dart`;
  - the five screens above;
  - `test/soil_record_test.dart` and the screen tests named below.
- Does NOT include:
  - `Formatters`, which keeps its three functions;
  - shared text, "Atualizado em", spoken labels, and Home's relative line.

## Acceptance Criteria

- `test/soil_record_test.dart`:
  - `dotted_timestamp_joins_date_and_time_with_a_dot`: a record at `2026-04-01T14:30:00` gives `01/04/2026 · 14:30`.
- `test/features/details/info_section_test.dart`:
  - `info_section_shows_the_dotted_date`: the section shows `formattedTimestampDotted`, and not `formattedTimestamp`.
- `test/features/compare/compare_screen_test.dart`:
  - the existing date check is amended to `formattedTimestampDotted`.
- `test/features/history/history_widgets_test.dart`:
  - `grid_tile_shows_the_dotted_date`: the tile's visible label is `formattedTimestampDotted`, and its spoken label keeps `formattedTimestampCompact`.
- `test/core/widgets/analysis_tile_test.dart`:
  - the existing default-line checks are amended to `formattedTimestampDotted`.
- `test/features/details/management_tips_section_test.dart`:
  - `tips_head_shows_the_dotted_date`: a record with no labels shows `formattedTimestampDotted` under its class.

## Reproducibility

Flutter 3.44.1, Dart 3.12.1. Run the tests above, then `flutter test`, `flutter analyze` and `mf check`.

## Risks and Assumptions

- **A wider line.** `·` adds two characters to the space form. The analysis tile already measures its date line for the pill's place (SPEC 0215), and its large-text tests run with the new text.
- **#468 and #469 edit `management_tips_section.dart`.** This change touches only the head's date line, outside their hunks.
