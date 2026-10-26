# SPEC: feat(main): adapt the layout to tablets and small phones

## Problem

Redesign v11 §10 asks the app to adapt its layout to the screen:

- **Tablets (600 dp and wider):** a `NavigationRail` on the left; content at most 560 dp wide and centred; the history as master-detail from 840 dp, with a 360 dp list beside the record; the result in two columns, the triangle beside the information.
- **Small phones (360 × 640 and smaller):** no screen overflows, including at 200 % text.

Today the app draws the phone layout at every width:

- The `NavigationBar` stretches across a tablet.
- Home and the Dicas tab grow to the full width.
- Opening a record from the history always pushes a full-screen route.
- The result's overview is one column.

## Design Decision

- **Navigation.** `MainScreen` reads the width.
  - Below 600 dp it keeps the `NavigationBar`.
  - From 600 dp it shows a `NavigationRail`, labels always shown, beside the tabs and divided from them.
  - Both use the same four destinations, the same selection haptic and the same `mainTabIndexProvider`.
- **Content width.** Home and the Dicas tab are centred at a maximum of 560 dp, as Perfil and the history already are.
- **History master-detail.**
  - From 840 dp the history shows its 360 dp list beside the selected record's `DetailsScreen`, divided from it.
  - Tapping a record selects it there instead of pushing `/details`, and the selected row is marked as selected. Selection mode keeps its toggling.
  - Until a record is chosen, and after the chosen one leaves the list (deleted or filtered out), the pane reads "Selecione uma análise para ver os detalhes.".
  - Below 840 dp, tapping a record still pushes `/details`.
- **Result in two columns.** From 600 dp of available width, `ResultOverview` places the triangle card beside a column holding the other cards. Below that it stays one column.
- **Small phones.** No layout change is needed beyond the rules SPEC 0121 and SPEC 0197 already apply. The main tabs gain an overflow test at 320 × 568 and at 200 % text.

## Alternatives Considered

- **A `NavigationRail` only from 840 dp.** Rejected: §10 names 600 dp.
- **Push `/details` on tablets too.** Rejected: §10 asks for master-detail from 840 dp, and pushing loses the list.
- **Lift the history selection into a provider.** Rejected: only the history reads it, so state local to the screen is enough.

## Scope

- Includes:
  - The rail in `MainScreen`.
  - The 560 dp cap on Home and Dicas.
  - The history master-detail and its placeholder.
  - `ResultOverview`'s two columns.
  - The small-phone and 200 % tests for the main tabs.
- Does NOT include:
  - Orientation locks beyond the guided camera's (SPEC 0165).
  - Tablet layouts for capture, compare or settings.
  - The stats grid's small-screen value size.

## Acceptance Criteria

- `rail_from_600dp`: at 599 dp `MainScreen` shows a `NavigationBar` and no rail. At 600 dp it shows a `NavigationRail` with the four labels, and selecting "Histórico" there shows the history.
- `home_content_is_capped_at_560`: at 1024 dp, the home content is at most 560 dp wide and centred.
- `history_is_master_detail_from_840`: at 1024 dp the pane first reads "Selecione uma análise para ver os detalhes.". Tapping a record shows its class in the detail pane without pushing a route, and the list stays visible.
- `history_pushes_below_840`: at 600 dp, tapping a record pushes `/details`.
- `history_clears_a_vanished_selection`: when the selected record leaves the list, the pane reads the placeholder again.
- `result_overview_has_two_columns_from_600`: at 600 dp of width the triangle card and the "Sobre a classe" card sit side by side. At 400 dp they are stacked.
- `main_tabs_fit_a_small_phone`: each main tab lays out without overflow at 320 × 568 and at 200 % text.
- Existing main, history and details tests pass. Tests that pinned the bottom bar on the test surface's default 800 dp width now use a phone surface, or accept either navigation.

## Reproducibility

Flutter 3.44.1, Dart 3.12.1. Run `flutter test`, `flutter analyze` and `mf check`.

## Risks and Assumptions

- The Developer asked for every pending v11 visual item on 2026-10-26.
- An embedded `DetailsScreen` keeps its own actions. Deleting from the pane still goes home (`context.go('/')`), which is the main screen the history lives in, so the history stays open. The vanished-selection rule then shows the placeholder.
