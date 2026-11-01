# SPEC: fix(tips): drop the Dicas tab's back arrow

## Problem

The Dicas tab is the only root tab with a back arrow.

- **What it draws.** `_TipsTab` in `main_screen.dart` puts a "Voltar" arrow in its app bar, which selects Início (SPEC 0205, after PNG 20).
- **Why it is wrong.** A tab is a top-level destination, reached from the navigation bar. Histórico and Perfil have no arrow, so the Dicas arrow suggests a depth the tab does not have.
- **The system back already does it.** From any tab other than Início, the system back selects Início (SPEC 0200). The arrow repeats it.
- **The visual review names it.** The unslop review of 2026-10-31 asked whether to keep the arrow, as item 6.
- **Decision.** On 2026-10-31 the Developer chose to remove it.

## Design Decision

**The Dicas tab's app bar has no leading button. Its title starts 16 dp from the edge, as Histórico's does, and the filter stays.**

- Removing `leading` is the whole change. `VisioAppBar` already sets the title 16 dp in when there is no leading button (SPEC 0201).
- The system back from Dicas still selects Início, untouched.

## Alternatives Considered

- **Keep the arrow.** Rejected by the Developer: it makes Dicas differ from the other tabs.

## Scope

- Includes:
  - `lib/core/features/main/main_screen.dart`, `_TipsTab` only;
  - `test/features/main/main_tabs_mock_test.dart`.
- Does NOT include:
  - the system back's behaviour;
  - the filter;
  - the mock, PNG 20, which still draws the arrow.

## Acceptance Criteria

- `test/features/main/main_tabs_mock_test.dart`:
  - `tips_tab_has_an_app_bar`, amended: the app bar titled "Dicas de manejo" has no "Voltar" button, and its title starts 16 dp from the left edge;
  - `tips_tab_system_back_selects_home`: on the Dicas tab, a system back selects Início.

## Reproducibility

Flutter 3.44.1, Dart 3.12.1. Run `flutter test test/features/main/main_tabs_mock_test.dart`, then `flutter test`, `flutter analyze` and `mf check`.

## Risks and Assumptions

- **Departs from the mock.** PNG 20 draws the arrow. The Developer chose the review over the mock here, and the mock is not changed.
- **SPEC 0205 recorded the arrow.** This spec supersedes that one point, and SPEC 0205's other decisions stand.
