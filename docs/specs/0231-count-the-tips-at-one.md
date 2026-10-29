# SPEC: fix(tips): count the tips in the singular at one

## Problem

The management tips write the plural whatever the number is, so a cell with one tip reads "1 dicas".

- **Where.** Two counters in `management_tips_section.dart` build the string by hand:
  - the section's header under the disclaimer, "`<class>` · N dicas";
  - the record header on the Dicas page, "N dicas".
- **Every record with tips will show it.** The corpus that SPEC 0227 and SPEC 0230 release grounds four cells, and each holds exactly one tip. Every record that gets tips will read "Média · 1 dicas" or "Argilosa · 1 dicas". The emulator check of 2026-10-28 shows both.
  - The category filter reaches one as well: hiding all but one tip reads "1 dicas".
- **A test pins the error.** `filter_hides_a_category` expects the text "1 dicas".
- **Why SPEC 0223 missed it.** SPEC 0223 added `Formatters.count` and named the four plural strings it applied it to. The two tip counters were not among them.

## Design Decision

**Both tip counters write their count with `Formatters.count(n, 'dica', 'dicas')`.**

- One is singular, and every other count, zero included, is plural, as SPEC 0223 decided for pt-BR.
- Nothing else in the two strings changes: the class label and the " · " separator stay as they are.

## Alternatives Considered

- **Hide the count when it is one.** Rejected. The header would then mean different things at different counts, and the mock draws the count at every size.
- **Inline `n == 1 ? 'dica' : 'dicas'` at each site.** Rejected. SPEC 0223 made `Formatters.count` the one place that decides a pt-BR plural, and a second rule would drift from it.

## Scope

- Includes:
  - the two tip counters in `management_tips_section.dart`;
  - their tests in `management_tips_section_test.dart`, including correcting `filter_hides_a_category`.
- Does NOT include:
  - the other counters in the app, which SPEC 0223 already covers or which already read correctly;
  - the corpus, its cells or its copy;
  - the "Fontes" list an abstained result shows.

## Acceptance Criteria

- `tips_header_counts_one_tip_in_the_singular`: a grounded result with one tip reads "Média · 1 dica" in the section's header.
- `tips_header_counts_the_tips`: a grounded result with two tips still reads "Média · 2 dicas".
- `filter_hides_a_category`: hiding the water category from the three-tip result leaves one tip, and the page's record header reads "1 dica".
- `tips_page_heads_with_the_record`: with two tips, the record header still reads "2 dicas".

## Reproducibility

Flutter 3.44.1, Dart 3.12.1. Run `flutter test test/features/details/management_tips_section_test.dart`, then `flutter test`, `flutter analyze` and `mf check`.

## Risks and Assumptions

- **A screen reader reads the same text.** Neither counter has its own semantics label, so fixing the text fixes what is announced.
- **Plurals cover only "1".** No tip count holds a fraction, as SPEC 0223 assumed for its counters.
