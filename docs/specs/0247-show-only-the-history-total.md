# SPEC: fix(history): show only the history total

## Problem

The same three numbers appear on three screens.

| Screen | What it shows |
|---|---|
| Início | three stat cells: analyses this week, total, the collection (`stats_grid.dart`) |
| Histórico | a bordered strip split in three: total, this week, the collection (`history_list.dart`, `_Summary`, PNG 16, SPEC 0203) |
| Perfil | a sentence with the total and the collection (`profile_screen.dart`) |

- **Why it matters.** Histórico is the list of analyses, and the strip puts a dashboard on top of it. Three bordered numbers repeat Início's grid one tap away, so the screens look templated rather than designed for their job.
- **The visual review names it.** The unslop review of 2026-10-31 found it, as item 3.
- **Decision.** On 2026-10-31 the Developer chose to keep only the total on Histórico, and approved this spec.

## Design Decision

**Histórico shows one quiet line above the list, "N análises", in place of the three-cell strip. The week and the collection stay on Início, and Perfil keeps its sentence.**

- The line counts every saved record, as the strip's first cell did, and takes the singular at one: `Formatters.count(n, 'análise', 'análises')`.
- It is `bodySmall` in `textSecondary`, with no border, and keeps the key `history-summary`.
- `_Summary` no longer reads the contract's classes, and `_SummaryCell` is removed.
- The collection grid on Histórico's other segment is unchanged.

## Alternatives Considered

- **Keep the strip.** Rejected by the Developer: it repeats Início.
- **Remove the line too.** Rejected: the total is the one number that belongs to the list, and nothing else on Histórico says it.

## Scope

- Includes:
  - `lib/core/features/history/widgets/history_list.dart`, `_Summary` and `_SummaryCell`;
  - `test/features/main/main_tabs_mock_test.dart`;
  - `test/features/collection_contract_classes_test.dart`.
- Does NOT include:
  - Início's stat cells and Perfil's sentence;
  - the collection grid;
  - the "Mostrando os N registros mais recentes" line;
  - the mock, PNG 16, which still draws the strip.

## Acceptance Criteria

- `test/features/main/main_tabs_mock_test.dart`:
  - `history_summary_is_the_total_alone`, replacing `history_summary_is_one_strip`: with two records, `history-summary` reads "2 análises", and shows neither "nesta semana", "classes" nor a fraction like "1/4".
- `test/features/collection_contract_classes_test.dart`:
  - the "history summary" cases of `collection_counts_contract_classes` and `collection_without_contract_reads_a_dash` are removed, since Histórico no longer shows the collection;
  - `counts_take_the_singular_at_one` gains a "history summary" case: one record reads "1 análise".

## Reproducibility

Flutter 3.44.1, Dart 3.12.1. Run the two test files above, then `flutter test`, `flutter analyze` and `mf check`.

## Risks and Assumptions

- **Departs from the mock.** PNG 16 draws the strip. The Developer chose the review over the mock here, and the mock is not changed.
- **SPEC 0203 recorded the strip.** This spec supersedes that one point, and SPEC 0203's other decisions stand.
- **The total ignores the filter.** With a texture filter or a search on, the line still counts every record, as the strip did. A count of the filtered list is a separate decision.
