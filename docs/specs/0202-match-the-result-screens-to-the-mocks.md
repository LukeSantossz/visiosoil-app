# SPEC: feat(details): match the result screens to the redesign mocks

## Problem

The Developer asked on 2026-10-26 that every screen follow the redesign v11 mocks strictly. The result family differs from PNGs 14, 15, 19, 26, 32 and 33:

- **Header.** It has no triangle lattice behind it. The class name carries a colour dot. The overline omits "(triângulo USDA)". The confidence is a badge with an icon and the percent, beside a continuous bar, where the mock has a label-only badge, a five-segment bar and the percent on the right.
- **Tabs.** They are a pill segmented control. The mock draws underlined tabs over a full-width rule.
- **Visão geral.** Its sections are cards. In the mock they are open sections, and the triangle sits beside its text.
- **Footer.** "Corrigir" wraps onto two lines at 390 dp.
- **App bar.** It offers "Nova captura" where the mock offers share, and the saved bookmark is green where the mock draws it dark.
- **Error (15).** The error keeps the photograph and the record's cards under the error block. The mock shows only the block.
- **Capture result (32).** It ends in three stacked capture buttons. The mock ends in the same "Corrigir · Dicas de manejo" footer as a saved result, and saves from the bookmark.
- **Photo screen (19).** It lists rows the mock does not have, and its accuracy row repeats its label.

## Design Decision

Measurements are read from the 2× PNGs (390 × 844 dp) and matched against Inter's metrics.

- **Lattice.** A `ResultLattice` painter draws an equilateral triangle grid behind the app bar:
  - apex at (260, −40) dp from the screen's top-left, side 35 dp, rows 30 dp;
  - 1 dp lines in `primaryText` at 16.5 % opacity down to 110 dp, fading to nothing 250 dp down.

  Modo Sol draws none (§1.5, PNG 26). The date chip sits 169 dp below the app bar, as in the mock.
- **Header.**
  - **Date chip:** `onSurface` at 75 %, radius 8, 12.5 sp Inter 500 tabular figures in `background`, padding 8 × 4.
  - **Overline:** "Classe textural (triângulo USDA)", 12 sp, `textTertiary`, 28 dp under the chip.
  - **Class name:** `headlineMedium`, with no colour dot.
  - **Confidence row:** the badge, then 12 dp, then the bar, then 12 dp, then the percent, 13 sp tabular in `onSurfaceVariant`.
    - The badge reads only the level label ("Confiança alta") at 12 sp Inter 600, 10 dp side padding, 24 dp tall, radius 6. Its fill is `selected` for high, `warningContainer` for moderate and `errorContainer` for low, and its text is the level's foreground. There is no icon.
    - The bar has five segments 6 dp tall, 2 dp apart, rounded. ⌊score × 5⌋ segments are filled in the level's accent (`primary`, `warningText` or `error`). The rest are `surfaceContainerHigh`.
  - **Banner:** the moderate and low advisory banner (§3.14) stays under the row.
- **Tabs.** `ResultTabBar` lays the three labels side by side from the start:
  - 14 sp Inter 500, 12 dp padding each side;
  - the selected label in `primaryText` with a 3 dp rounded indicator as wide as the label;
  - the others in `onSurfaceVariant`;
  - a 1 dp `surfaceContainerHigh` rule spans the full width under them.

  It plays `AppHaptics.selection()` and announces the selected tab.
- **Visão geral.** Open sections on the background, 16 dp side margins:
  - the intro at 14/20 in `onSurfaceVariant`;
  - each section title at 14 sp Inter 600 in `onSurfaceVariant`, its caption at 12 sp in `textTertiary`, 24 dp between sections;
  - "No triângulo textural": a 150 dp wide static triangle, then 16 dp, then "A região **{classe}** está destacada." at 14/20 and the diagram's note at 12 sp in `textTertiary`;
  - "Sobre a classe" with its caption, and "Amostra" in the same open style;
  - the lab notice last.
- **Footer.**
  - A 1 dp `surfaceContainerHigh` top rule, then 12 dp padding.
  - The 52 dp outlined "Corrigir", with Lucide `pencil` and flex 5, then 8 dp, then the 52 dp primary "Dicas de manejo", flex 8.
  - Labels are 15 sp Inter 600 on one line.
  - From a 1.3× text scale the buttons stack (§8).
- **App bar.** Back (Lucide `arrowLeft`, "Voltar"), then the bookmark, then share (Lucide `share2`, `shareRecordWithConsent`).
  - The bookmark is Lucide `bookmark` outlined while unsaved and a filled bookmark once saved, both in `onSurface`.
  - "Nova captura" leaves the app bar. Home and history start a capture.
- **Error (PNG 15).** Centred, 44 dp under the app bar, with 48 dp side margins:
  - a 56 dp `errorContainer` disc with Lucide `circleAlert` in `onErrorContainer`;
  - 16 dp lower, the title "Não deu para classificar" at 18 sp Inter 600;
  - 8 dp lower, the cause's copy at 14/20 in `onSurfaceVariant`. A cause the capture chip offers a rerun for (timeout, isolate failure, computation error) reads "Análise não terminou · tire outra foto", since the block offers no rerun;
  - 20 dp lower, a primary "Fotografar de novo" with Lucide `camera`, as wide as its label;
  - 8 dp lower, a text "Ver dicas de captura".

  Nothing else is listed.
  - A saved unclassified record still shares from the app bar and is removed through its filled bookmark (SPEC 0197).
  - "Fotografar de novo" opens capture.
  - "Ver dicas de captura" opens the capture guide.
- **Capture result (PNG 32).**
  - The draft uses the same app bar and footer. The outlined bookmark saves (SPEC 0196), and back discards it, as leaving capture already does (SPEC 0146).
  - "Corrigir" asks for the field and sample labels and keeps them for the save.
  - "Dicas de manejo" opens the Manejo tab.
  - A failed capture shows the PNG 15 error, with the outlined bookmark saving it (SPEC 0173). The rerun button and the photograph leave it.
  - The capture guide stays reachable from "Ver dicas de captura".
- **Photo screen (PNG 19).**
  - The app bar is black, with back, the title and share.
  - The photograph sits in a square as wide as the screen, shown whole so the viewer's zoom and pan reach its edges; a non-square one sits on the black page.
  - The rows are at least 56 dp, with 14 sp labels in #C8C8C8 and 15 sp white values on the right, over #333333 rules: Classe estimada · Confiança · Data e hora · Coordenadas ("−17,79 · −50,92": two decimals, comma, true minus) · Modelo.
  - "Precisão" and "Endereço" leave the screen, since PNG 19 does not list them, and "Excluir registro" ends the page.
  - "Captura" stays out, because the app does not measure lux, distance or sharpness (§11).

## Alternatives Considered

- **Keep "Salvar registro", "Tirar outra foto" and "Descartar" under the draft.** Rejected: PNG 32 shows the saved result's footer, and the bookmark already saves.
- **Keep the photograph under the error.** Rejected: PNG 15 shows only the block.
- **Show the mock's "Captura" row with invented values.** Rejected: §11 forbids fictional data.

## Scope

- Includes:
  - `ClassificationHeader`, `ConfidenceBadge`'s result variant, a segmented `ConfidenceBar`, `ResultTabBar`, `ResultLattice`, `ResultOverview`, the result footer, app bar and error block;
  - capture's draft and failed results;
  - the photo screen;
  - the Lucide icons of these screens;
  - updates to tests that pinned the replaced controls.
- Does NOT include:
  - The Manejo and Detalhes tab contents beyond their header.
  - Capture's pre-result screen.
  - The processing view.
  - The camera.

## Acceptance Criteria

- `header_matches_the_mock`:
  - the overline reads "Classe textural (triângulo USDA)";
  - no colour dot is drawn;
  - the badge reads "Confiança alta" with no icon;
  - the bar has five segments, four filled at 0.82;
  - "82%" sits right of the bar.
- `tabs_are_underlined`: the three labels sit in one row with an indicator under the selected one only, and tapping "Manejo" moves it.
- `footer_fits_one_line`: at 390 dp and 1.0× text, "Corrigir" and "Dicas de manejo" each render on one line, side by side.
- `app_bar_shares`: the result's app bar offers "Compartilhar" and no "Nova captura".
- `lattice_only_outside_sun`: the lattice paints in the light theme and not in Modo Sol.
- `error_shows_only_the_block`: an unclassified record shows the title, the cause, "Fotografar de novo" and "Ver dicas de captura", and no photograph.
- `draft_footer_and_bookmark`:
  - a classified capture shows "Corrigir" and "Dicas de manejo", and none of "Salvar registro", "Tirar outra foto" or "Descartar";
  - the bookmark saves;
  - "Corrigir" labels end up on the saved record.
- `photo_rows_match_the_mock`: the photo screen lists exactly Classe estimada, Confiança, Data e hora, Coordenadas and Modelo, with coordinates as "−17,79 · −50,92".
- Existing tests pass, updated only where they pinned a control this change replaces.

## Reproducibility

Flutter 3.44.1, Dart 3.12.1. Run `flutter test`, `flutter analyze` and `mf check`. The mock comparison renders at 390 × 844 dp with a 44 dp status bar.

## Risks and Assumptions

- The Developer asked on 2026-10-26 for the screens to follow the mocks "fielmente e estritamente" ("faithfully and strictly").
- Removing the draft's retake and the failure's rerun moves recovery to back plus a new capture, and to "Fotografar de novo".
- The mock shows no Manejo or Detalhes tab, so those keep their content under the new header.
