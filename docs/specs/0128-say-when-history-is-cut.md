# SPEC: fix(history): say when history shows only the most recent records

## Problem

History shows at most 150 records and drops the older ones silently, so a user with more records cannot tell that some are missing (`docs/design/ux-2026/13-roadmap.md` §4, criterion `cap_is_disclosed`).

## Scope

- Includes:
  - `lib/core/features/history/widgets/history_grid.dart`: when the records outnumber `maxRecords`, a line above the grid reads "Mostrando os 150 registros mais recentes. Use a busca ou os filtros para encontrar os mais antigos." The number is `maxRecords`, and "mais recentes" holds because the records stream is ordered newest first (`id` descending).
  - `test/features/history/history_widgets_test.dart`: the tests below.
- Does NOT include:
  - Raising or removing the 150 cap, or paging.
  - Any change to the search or the filters.

## Acceptance Criteria

- `cap_is_disclosed`: with 151 records, the grid shows 150 thumbnails and the line naming 150.
- `no_notice_under_the_cap`: with 150 records or fewer, the line is absent.
- The existing tests pass unchanged.
