# SPEC: feat(home): match the navigation bar, home and history to the redesign mocks

## Problem

The Developer asked on 2026-10-26 that every screen follow the redesign v11 mocks (`docs/design/spec/telas/`) strictly. SPEC 0201 matched the chrome every screen shares, and SPEC 0202 the result screens. The navigation bar, Home (PNG 08, 09, 25, 27) and the history (PNG 16, 17, 18, 34) still differ from their mocks:

- **Navigation bar.**
  - It is drawn on `surface` with a green selected label.
  - The mocks draw it on `surfaceContainer` with a one-line rule on top. Labels are 12 sp, and the selected one is dark ink.
- **Home.**
  - The header carries the logo and a settings button. The mock has only the title, and Perfil hosts Settings.
  - The page is drawn on `background`. The mock draws it on `surfaceContainer`, so the white cards stand out.
  - The capture pill's text is 22 sp. The mock's is 17 sp, with a scan icon and an image icon.
  - The stat cards are 81 dp tall, bordered and shadowed, with 14 dp icons and 20 sp values. The mock draws them 120 dp tall, flat, with 20 dp icons and 24 sp values.
  - The collection reads "3" here, "3/12" on Perfil and "0/12" in the history, for the same records. The mock reads "7/12" on both Home and Perfil.
  - Recent rows carry a coloured status pill. The mock draws a dot and a coloured word.
  - The rows use a 48 dp bordered placeholder. The mock uses a 40 dp photograph.
  - Blocks sit 20 dp from the edge. The mock puts blocks at 16 dp and titles at 20 dp.
- **History.**
  - The app bar offers "Nova captura" and "Selecionar registros", with an always-open search field and chips below it. The mock's app bar offers a search and a filter action, and nothing sits between the bar and the segmented control.
  - The segmented control is 48 dp tall with 12 sp labels. The mock's is 40 dp, with 14 sp labels and 20 dp icons.
  - The summary is three separate shadowed cards. The mock draws one bordered strip split in three, with 20 sp values.
  - The date headers are 16 sp. The mock's are 14 sp in `onSurfaceVariant`, each followed by a rule.
  - The rows' 16 sp titles stack the pending pill under the text. The mock's rows have 14 sp titles, a 12 sp `textTertiary` line, and a chevron or the pill at the end.

## Design Decision

Every value below was measured on the 2× PNGs (780 × 1688, so 390 × 844 dp with a 44 dp status bar). Text sizes were fitted against InterVariable at the same optical size and features.

- **Navigation bar** (`AppTheme`, `MainScreen`).
  - It is drawn on `surfaceContainer`, with a top rule in `divider` at `edgeWidth`.
  - Labels are 12 sp, weight 500, `onSurfaceVariant`, with no tracking. The selected label is weight 600 in `onSurface`.
  - The selected icon is `onPrimaryContainer` on the `primaryContainer` indicator.
  - Modo Sol keeps its 88 dp bar, black indicator and white icon (SPEC 0182).
- **Home.**
  - The page is drawn on `surfaceContainer`, or `background` in Modo Sol, as PNG 25 shows. The contour lines stay outside Modo Sol.
  - The header is only "Início": `headlineMedium`, 20 dp from the edge, its line 20 dp below the safe area.
    - The logo and the settings button leave.
    - The boot's logo therefore no longer lands on Home. The boot ends as its reduced-motion path already does (SPEC 0193).
  - The capture pill is 56 dp tall in every theme (PNG 25 draws Modo Sol's at 56 too), at 16 dp margins, on `surface`.
    - It holds a 20 dp Lucide `scan` icon 20 dp from its left edge, then "Analisar solo" at 17 sp weight 400 in `onSurfaceVariant`, 16 dp after the icon.
    - A 20 dp Lucide `image` icon sits 69 dp from its right edge, where the mock draws it. It is decorative, since capture is camera-only.
  - Section titles ("Esta semana", "Recentes") are 17 sp weight 600, 20 dp from the edge. They sit 28 dp below the block above, with 12 dp to the block below.
  - **Stat cards** (`StatCell`, shared with Perfil).
    - Each card is flat, on `surface` with radius 16, with no border or shadow outside Modo Sol. Cards are 8 dp apart.
    - Each card holds a 20 dp `onSurface` icon, then the value at 24 sp weight 650 with tabular figures and −0.025 em tracking, then the label at 12 sp in `onSurfaceVariant`.
    - The padding is 12 dp. The row is at least 120 dp tall, with each card's content centred vertically.
    - Home's icons are Lucide `scan`, `layers` and `sprout`.
    - The collection value reads `N/12`, counting the twelve USDA reference classes the records hold, as the history and its collection grid count them. Perfil adopts the same count in its own change.
  - **Recent rows** (`AnalysisTile` with `showSyncStatus`).
    - The list sits on a `surface` card with radius 16 and 4 dp of vertical padding.
    - Each row is 64 dp tall: a 40 dp photograph with radius 8, then the 16 sp weight 600 title over a 13 sp `onSurfaceVariant` line, 12 dp after the photograph.
    - At the end, a 7 dp dot and the status word at 13 sp weight 600 take the status colour.
    - The status colours are `statusSent`, `statusPending` and `statusError`, new `AppPalette` roles taken from the mocks:

      | Theme | Sent | Pending | Error |
      |---|---|---|---|
      | Light | #2E6B3A | #8A5A00 | #B3261E |
      | Dark | #9BD3A3 | #E9C16C | #F2B8B5 |
      | Sol | black | black | black |

    - Rules between rows run from the text's start to 16 dp from the card's end.
- **History.**
  - **App bar.**
    - Its actions are Lucide `search`, labelled "Buscar", and `slidersHorizontal`, labelled "Filtros".
    - Each toggles its part of `HistoryFilterBar`: the search field, or the class chips. A part stays open while it holds a term or a chosen class.
    - "Nova captura" leaves: Home and the empty history start a capture.
    - "Selecionar registros" leaves the bar. A selection starts with a long press, or with a row's "Selecionar" custom semantics action. A switch or screen-reader user keeps a way in that is not a gesture, as SPEC 0122 required, and as the row's "Excluir" action already gives (SPEC 0187).
  - **Segmented control** (`SegmentedControl`, shared with Settings).
    - The pill is 40 dp tall, top-aligned in a 48 dp hit area so the target stays 48 dp. The extra 8 dp sit in the gap below, which the mock leaves.
    - Labels are 14 sp weight 500, and icons are 20 dp Lucide `history` and `layers`.
    - It sits directly under the app bar, at 16 dp margins.
  - **Summary.**
    - One strip with a 1 dp `divider` border and radius 12 is split into three cells by 1 dp rules.
    - Each cell has 12 dp of padding, the value at 20 sp weight 600 with tabular figures, and the label at 12 sp in `textTertiary`.
  - **Date headers.** 14 sp weight 600 in `onSurfaceVariant`, with 24 dp above and 8 dp below, then a full-width rule.
  - **Rows** (`AnalysisTile` with `history`).
    - Each row has 8 dp of vertical padding, a 56 dp photograph with radius 8, and 12 dp before the text.
    - The title is 14 sp weight 600. The line under it is 12 sp in `textTertiary`.
    - At the end, a 24 dp Lucide `chevronRight` in `onSurface`, or the pending pill with Lucide `refreshCw`.
    - A full-width rule follows each row. The list keeps 16 dp margins.

## Alternatives Considered

- **Keep "Selecionar registros" in the app bar.** Rejected: the mock's bar has search and filters only. The custom semantics action keeps the way in that SPEC 0122 asked for, without a gesture.
- **Keep the boot's logo on Home and hide it.** Rejected: a Hero flying into an invisible logo would shrink the boot's logo into nothing at the title's corner, which reads as a glitch.
- **Draw the segmented control 48 dp tall.** Rejected: the mock draws 40 dp. The hit area keeps 48 dp without changing what is drawn.

## Scope

- Includes:
  - the navigation bar theme;
  - `HomeScreen`, `HeroCaptureCard` and `StatsGrid`;
  - `StatCell`;
  - `AnalysisTile`'s home and history presentations;
  - `StatusPill`'s icon;
  - `SegmentedControl`;
  - `HistoryScreen`, `HistoryFilterBar` and `HistoryList`;
  - the three status roles in `AppPalette`.
- Does NOT include:
  - Perfil, Settings and the Dicas tab, which follow in their own change. They pick up `StatCell` and `SegmentedControl` from this one.
  - The collection grid's own layout.
  - The history's swipe, undo and offline banner behaviour, which this change only re-skins.

## Acceptance Criteria

- `navigation_bar_matches_the_mock`:
  - the bar's colour is `surfaceContainer`, with a rule on top;
  - the selected label is `onSurface` at weight 600, and the others are `onSurfaceVariant` at 12 sp.
- `home_header_is_the_title_alone`: Home shows "Início" with no settings button and no logo, and the title starts 20 dp from the edge.
- `home_page_is_surface_container`: Home's background is `surfaceContainer` in light and dark themes, and `background` in Modo Sol.
- `home_stats_match_the_mock`:
  - three cards, each at least 120 dp tall;
  - 20 dp icons;
  - the collection value reads `N/12`;
  - the cards draw no shadow.
- `home_recent_rows_show_a_status_dot`:
  - a sent record's row shows "Enviada" in `statusSent` beside a dot, and no `StatusPill`;
  - the row is 64 dp tall with a 40 dp photograph.
- `history_app_bar_offers_search_and_filters`:
  - the bar holds "Buscar" and "Filtros", and no "Nova captura" or "Selecionar registros";
  - the search field appears only after "Buscar";
  - the chips appear only after "Filtros".
- `history_selection_has_a_semantics_action`: a row's "Selecionar" custom semantics action enters selection with that row selected.
- `segmented_control_is_40_dp_with_a_48_dp_target`: the drawn pill is 40 dp tall, and each segment's hit area is at least 48 dp tall.
- `history_summary_is_one_strip`: the summary is one bordered strip of three cells, with no `StatCell` shadow.
- `history_rows_match_the_mock`:
  - a sent row is 72 dp tall, with a 56 dp photograph and a chevron;
  - a pending row shows the pill at the row's end, on the same line as the title.
- Existing tests pass. They are updated only where they pinned the old header, actions, sizes, pill or summary.

## Reproducibility

Flutter 3.44.1, Dart 3.12.1. Run `flutter test`, `flutter analyze` and `mf check`.

## Risks and Assumptions

- The Developer asked on 2026-10-26 for the screens to follow the mocks "fielmente e estritamente".
- The sizes are read from 2× PNGs, so they can be a sub-pixel off.
- The image icon's 69 dp right inset is what the mock draws. It may be an artefact of the prototype, and it is followed as drawn.
- With the four-class model, no record holds one of the twelve USDA reference labels yet. The collection therefore reads "0/12" on Home, as the history and its collection grid already show it.
- Moving "Selecionar registros" off the bar makes selection less discoverable for a sighted user who does not try a long press. The semantics action covers assistive technology only.
