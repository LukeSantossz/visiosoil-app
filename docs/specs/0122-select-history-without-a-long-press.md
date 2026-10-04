# SPEC: fix(a11y): let history selection start without a long press

## Problem

The only way into history's selection mode is a long press on a thumbnail, a gesture with no visible hint and no discrete alternative.

The audit asks that no interaction require a gesture without a discrete alternative, and names this one (`docs/design/ux-2026/12-accessibility.md` §3, criterion `long_press_has_alternative`; roadmap criterion `selection_has_non_gesture_entry`). It is the last open criterion of roadmap item 3, after SPEC 0118, SPEC 0120 and SPEC 0121.

On `main`, `HistoryScreen` derives selection mode from its set of selected ids (`_isSelectionMode => _selectedIds.isNotEmpty`). So the mode cannot exist with nothing selected, and the first selection has to come from the long press.

## Design Decision

**The app bar offers a "Selecionar registros" button.** It is an `IconButton` with `Icons.checklist` and the tooltip "Selecionar registros", which is also its label. It shows only outside selection mode, and only while the grid has at least one record to select.

**Selection mode becomes an explicit flag.** `_selecting` replaces the derived getter:

| Event | Effect |
| --- | --- |
| "Selecionar registros" | enters selection mode with nothing selected |
| long press on a thumbnail | enters selection mode with that record selected, as today |
| tap on a thumbnail while selecting | toggles it, as today |
| deselecting the last selected record | ends selection mode, as today |
| "Cancelar seleção" | ends selection mode |
| a confirmed deletion | ends selection mode |

Ending the mode when the last record is deselected keeps today's behaviour. Entering with nothing selected is the one new state.

**With nothing selected, the title reads "Nenhum selecionado"**, and the delete button stays disabled, as its existing `_selectedIds.isNotEmpty` guard already does. Today the title would read "0 selecionado".

## Alternatives Considered

- **A checkbox on every thumbnail, always visible.** Rejected: it adds a target to every cell and clutters the grid for the common case, which is opening a record.
- **A "Selecionar" text button instead of an icon.** Rejected: at 200 % text it would compete with the title for the app bar's width. The tooltip gives the icon its words, for a screen reader and on a long press.
- **Keep the derived mode, and enter it by selecting the first visible record.** Rejected: it selects something the user did not choose.

## Scope

- Includes:
  - `lib/core/features/history/history_screen.dart`: the button, the `_selecting` flag and the empty-selection title.
  - `test/features/history/history_screen_test.dart`: the tests below.
- Does NOT include:
  - The history card's content (class and confidence), which is roadmap item 9.
  - Where a tap on a card goes (`tap_opens_details`), which is roadmap item 10.
  - System back while selecting.
  - Select all.

## Acceptance Criteria

- `selection_has_non_gesture_entry`: with a record shown, tapping "Selecionar registros" enters selection mode with nothing selected. The title reads "Nenhum selecionado", and "Excluir selecionados" is disabled. A tap on the thumbnail then selects it, and does not open the preview.
- `selection_entry_needs_a_record`: with no record shown, "Selecionar registros" is absent.
- `selection_entry_is_labelled`: history outside selection mode meets `labeledTapTargetGuideline` and `androidTapTargetGuideline`.
- `deselecting_the_last_record_ends_selection`: after entering by the button, selecting a record and deselecting it ends selection mode.
- The existing tests pass unchanged.

## Reproducibility

`flutter test test/features/history/`

Flutter 3.44.1, Dart 3.12.1.

## Risks and Assumptions

- The button reads the same stream the grid shows, `filteredRecordsProvider`. With a filter that matches nothing, there is no record to select, and the button hides.
- `Icons.checklist` is a Material icon that ships with Flutter 3.44.1, so no asset is added.
