# SPEC: fix(tips): name the sources of an abstained result as consulted

## Problem

An abstained result tells the agronomist that no source supports a tip, and then lists sources under a heading that reads as support.

- **Where.** `_TipsData` in `management_tips_section.dart` shows the abstained message, "Não encontramos dicas de manejo com fontes confiáveis para este registro.", and below it `_SourcesList`, headed "Fontes", whenever the result carries sources.
- **Every abstained cell carries sources.** The corpus SPEC 0230 releases, `2026.10.28.1`, abstains in eight of its twelve substance cells, and each of the eight lists two or three sources: the documents the build read and found no supported tip in.
- **The two lines contradict each other.** "No reliable sources" followed by a list headed "Fontes" reads as if those sources were the reliable ones and the tips were withheld anyway. The emulator check of 2026-10-28 (SPEC 0227's F step) showed it.

## Design Decision

**When the abstained message shows, the sources list is headed "Fontes consultadas"; otherwise it stays "Fontes".**

- The label follows the same condition as the message — an abstained status or no tips at all — so the two can never disagree.
- The list itself does not change: the same sources, in the same order, with the same tiles. What the build read stays visible, which is what the result can honestly say about an abstention.
- A grounded result whose tips the category filter hides is not abstained: its sources still support tips, and it keeps "Fontes".

## Alternatives Considered

- **Hide the sources of an abstained result.** Rejected by the Developer on 2026-10-29. It removes the only record of what was searched, and an agronomist who wants to read the documents themselves loses the links.
- **Reword the abstained message instead.** Rejected. The message is accurate; it is the heading that claims more than the result does.

## Scope

- Includes:
  - the heading of `_SourcesList` in `management_tips_section.dart`;
  - a widget test in `management_tips_section_test.dart`.
- Does NOT include:
  - the corpus, its cells or which sources a cell records;
  - the abstained message, the disclaimer or the source tiles;
  - the build's retry, which stays an open decision.

## Acceptance Criteria

- `abstained_result_names_the_consulted_sources`: an abstained result with sources shows the heading "Fontes consultadas" and no heading "Fontes", and still lists each source's title.
- `data state renders cards, chips, sources and disclaimer`: a grounded result still shows the heading "Fontes".

## Reproducibility

Flutter 3.44.1, Dart 3.12.1. Run `flutter test test/features/details/management_tips_section_test.dart`, then `flutter test`, `flutter analyze` and `mf check`.

## Risks and Assumptions

- **A screen reader reads the same text.** The heading has no semantics label of its own, so the new text is what is announced.
- **An insufficient-evidence result reads the same way.** It has no tips, so it shows the abstained message; any sources it carries are headed "Fontes consultadas", which is as true of it as of an abstention.
