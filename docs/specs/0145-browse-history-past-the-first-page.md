# SPEC: feat(history): browse every Soil Record past the first 150

## Problem

History shows the 150 most recent matching records and offers no way past them, so an older Soil Record that shares its address and texture class with 150 newer ones cannot be reached at all (#359).

The grid slices the filtered stream to `maxRecords` and, since SPEC 0128, says so with a line pointing to the search and the filters. That advice fails exactly when it is needed: a field visited every week fills 150 records with one address and one class, and narrowing by either leaves the oldest of them out of reach. The stream already holds every matching record, newest first, filtered in the database (`filteredRecordsProvider`), so the limit is the grid's alone.

## Design Decision

**A "Mostrar mais registros" button at the end of the grid adds the next 150.** `HistoryGrid` becomes a stateful widget that owns how many records it shows. It starts at `pageSize` (150, the screen's constant renamed from `_maxRecords`) and each tap on the button adds another `pageSize`. The grid shows the first `min(shown, total)` records of the stream, in the stream's order, so the next records are the next older ones and none is repeated or moved.

- **Where the button sits.** The grid becomes a `CustomScrollView` holding the same grid as a `SliverGrid` and, after it, the button as an outlined `VisioButton`. The user meets it by scrolling to the last record shown, which is where they ran out. It is absent when every matching record is shown.
- **The notice counts.** The line above the grid reads "Mostrando os {shown} registros mais recentes de {total}." while records are left out, and is absent otherwise. The sentence sending the user to the search and the filters goes, because the button now reaches what they could not.
- **The count is the grid's, not the filter's.** Changing the class filter or the search term keeps the count, so a user who opened 300 records and then narrows the filter is not sent back to 150. The filters keep working on the full set in the database as they do today. The count also survives selection mode, which removes the filter bar above the grid but keeps the grid's state, and switching tabs, since the main screen keeps History in an `IndexedStack`.

Nothing changes in the database, the repository or the providers: the stream is the same, and the grid builds thumbnails lazily, so showing more records costs only what is scrolled into view.

## Alternatives Considered

- **Load the next page automatically as the user nears the end.** Rejected. The issue asks for an explicit control, and a list that grows on its own gives no point where the user knows how much they are looking at.
- **Page in the database with `LIMIT` and `OFFSET`.** Rejected for this change. The stream already loads every matching record, so a database page would change the repository contract and `watchFiltered` without changing what the device holds. It belongs with a measured cost of the full stream, which nothing reports today.
- **Remove the 150 limit.** Rejected. The issue keeps the initial limit, and the notice keeps telling the user how much of the total they see.
- **Put the button in the notice line above the grid.** Rejected. It keeps the `GridView`, but a user who reaches the 150th record has to scroll back to the top to continue.
- **Reset the count to 150 when a filter changes.** Rejected. It would hide again records the user just opened, for no saving, since thumbnails are built only when scrolled into view.

## Scope

- Includes:
  - `lib/core/features/history/widgets/history_grid.dart`: the stateful count, the `CustomScrollView` with the button, and the notice's new copy; `maxRecords` renamed to `pageSize`.
  - `lib/core/features/history/history_screen.dart`: `_maxRecords` renamed to `_pageSize` and passed as `pageSize`.
  - `test/features/history/history_widgets_test.dart`: the tests below; `cap_is_disclosed` and `no_notice_under_the_cap` updated to the new copy, and the thumbnail-count helper read from the `SliverGrid`.
  - `test/features/history/history_screen_test.dart`: the selection criterion.
- Does NOT include:
  - Any change to the database, the repository, `filteredRecordsProvider` or the order of the stream.
  - Any change to the search, the class filter or selection mode's actions.
  - Automatic loading, a "show all" action, or a way back to fewer records.
  - Other screens, including the home screen's recent records.

## Acceptance Criteria

- `show_more_reveals_the_next_records`: with 400 records, the grid shows the 150 newest and the button; one tap shows 300, a second tap shows all 400 and removes the button; the records shown are the stream's first ones, in its order, with no repeat.
- `show_more_keeps_the_filters`: with 200 records of one class under an active class filter, the button shows all 200, and the filter stays selected.
- `count_survives_a_filter_change`: after one tap, a stream that changes to 250 records shows all 250 with no button.
- `no_button_when_all_are_shown`: with 150 records or fewer, neither the button nor the notice is shown.
- `cap_is_disclosed`: with 151 records, the grid shows 150 thumbnails and the line "Mostrando os 150 registros mais recentes de 151."; after a tap, the line is gone.
- `selection_keeps_the_shown_records`: on the history screen with 200 records, after a tap on the button, entering and leaving selection mode still shows 200.
- The button and the screen pass the existing accessibility guideline and 200 % text tests, and every other existing test passes unchanged.

## Reproducibility

```sh
flutter test test/features/history
flutter analyze && flutter test && mf check
```

Flutter 3.44.1, Dart 3.12.1, `mf` v0.8.0.

## Risks and Assumptions

- **Assumption: the full stream stays cheap enough to load at once.** It does today, and this change does not make it heavier. If a device with thousands of records shows the history slowly, the remedy is database paging, an alternative recorded above.
- **Risk: a long grid is slow to scroll back through.** Accepted. Search and filters remain the way to narrow, and the count is visible in the notice.
- **What would invalidate this spec:** a decision to page in the database, or a history ordered other than newest first.
