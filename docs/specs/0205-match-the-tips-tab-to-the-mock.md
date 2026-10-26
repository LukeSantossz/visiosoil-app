# SPEC: feat(tips): match the Dicas tab to the redesign mock

## Problem

The Developer asked on 2026-10-26 that every screen follow the redesign v11 mocks "fielmente e estritamente" ("faithfully and strictly"). The Dicas tab differs from PNG 20:

- **Chrome.** The tab has no app bar, and its content runs to the screen's edges with no margin. The mock has an app bar titled "Dicas de manejo" and 16 dp margins.
- **Record header.** The tab shows "Dicas de manejo" as a 16 sp title, then "Argilosa · 3 dicas" as a line of text. The mock heads the page with the record: a 56 dp photograph, the class, the record's labels, and a "4 dicas" chip, over a rule.
- **Disclaimer.** The disclaimer sits at the end, bordered. The mock puts a borderless warning banner first, under the header.
- **Timeline.** It has 16 sp group titles in the old weight, a 2 dp rule and 12 dp dots in `primary`. The mock draws 16 sp titles at weight 600, a 1 dp rule in `divider`, and a filled first dot with outlined `outline` dots after it.
- **Tip cards.** The cards are bordered in `cardBorder` with Material icons. The mock draws a `divider` border, radius 16, a 40 dp `surfaceContainer` icon tile with a Lucide icon, 14/20 text, and the source at 12 sp under a 16 dp bookmark.

## Design Decision

Measured on the 2× PNG 20, 2 px to the dp. The text sizes were checked by rendering PNG 20's own strings and comparing each line's ink extent with the mock's, which they match within 1 dp.

- **Tab chrome** (`MainScreen`'s Dicas tab).
  - A `VisioAppBar` titled "Dicas de manejo".
  - Its back arrow ("Voltar") selects Início, as the system back already does from this tab (SPEC 0200).
  - The mock's filter action is left out: no filter exists to open.
  - The list keeps 16 dp margins, the header 4 dp under the app bar.
- **Record header** (`ManagementTipsSection` with `asPage`).
  - The record's 56 dp photograph with radius 12, or a `surfaceContainerHigh` tile when it cannot be read.
  - 12 dp after it, the class at 17 sp weight 500, over the record's field and sample labels joined by " · " at 15 sp in `onSurfaceVariant`. A record without labels shows its date instead.
  - At the end, a "N dicas" chip: 24 dp tall, radius 6, `surfaceContainer`, 13 sp weight 600 in `onSurfaceVariant`. It appears once tips exist.
  - A full-width `divider` rule 8 dp below the header.
  - The result's Manejo tab keeps its own heading, since the result's header already names the record.
- **Disclaimer.** It moves to the top, 12 dp under the rule (or under the heading on the result):
  - a borderless `warningContainer` banner, radius 12, padding 12;
  - a 20 dp Lucide `info` in `onWarningContainer`, 12 dp before the text;
  - the text at 14/20 in `onWarningContainer`.
- **Timeline.**
  - A 24 dp gutter holds a 12 dp dot centred 12 dp in: the first group's dot is filled with `primary`, the others are `surface` with a 2 dp `outline` ring. A 1 dp `divider` rule joins the dots.
  - Group titles are 16 sp weight 600, 12 dp after the gutter, with 8 dp to their first card and 16 dp between groups.
  - The mock's "Agora" and "Próximo" chips, its titled cards and its filter follow in SPEC 0209, which gives a tip an optional title and crop phase. On category groups the chips stay out, since a category is not a crop phase (SPEC 0198) and §11 forbids inventing one.
- **Tip card.**
  - On `surface`, radius 16, with a 1 dp `divider` border (2 dp `cardBorder` in Modo Sol) and 12 dp padding. Cards are 8 dp apart.
  - A 40 dp `surfaceContainer` tile with radius 10 holds a 20 dp Lucide icon in `onSurfaceVariant`: `tractor` (preparo), `sprout` (culturas), `droplets` (água) or `lightbulb` (outras).
  - 12 dp after it, the tip's text at 14/20 in `onSurface`. Tips carry no title, so the mock's bold titles are not invented.
  - The source line, 6 dp lower, has a 16 dp Lucide `bookmark` in `textTertiary`, then the source at 12/16 in `textTertiary`.
- Sources, the update time and "Atualizar dicas" keep their place after the timeline.

## Alternatives Considered

- **Draw the mock's phase chips from the categories.** Rejected: "Agora" and "Próximo" state a crop phase the corpus does not record.
- **Use the first sentence of a tip as its title.** Rejected: it would split reviewed corpus text in two and read as two claims.

## Scope

- Includes:
  - the Dicas tab in `MainScreen`;
  - `ManagementTipsSection`'s disclaimer, timeline, tip card and new `asPage` header.
- Does NOT include:
  - The result's Manejo tab layout beyond the shared timeline, card and disclaimer.
  - What the tips say or how they are composed.

## Acceptance Criteria

- `tips_tab_has_an_app_bar`:
  - the Dicas tab shows a "Dicas de manejo" app bar whose "Voltar" selects Início;
  - its content starts 16 dp from the edge.
- `tips_page_heads_with_the_record`:
  - with a classified record labelled "Talhão 3" and "Amostra 2", the header shows its class and "Talhão 3 · Amostra 2";
  - a "2 dicas" chip shows once two tips are cached;
  - the header's photograph is 56 dp.
- `disclaimer_comes_first`: the disclaimer banner sits above the first group title and has no border.
- `timeline_matches_the_mock`:
  - group titles are 16 sp;
  - the first dot is filled with `primary` and the second is outlined.
- `tip_card_matches_the_mock`:
  - the card's border is `divider` with radius 16;
  - the icon tile is 40 dp with a Lucide icon;
  - the tip's text is 14 sp.
- Existing tests pass. They are updated only where they pinned the old heading, icons or the disclaimer's position.

## Reproducibility

Flutter 3.44.1, Dart 3.12.1. Run `flutter test`, `flutter analyze` and `mf check`.

## Risks and Assumptions

- The mock's back arrow on a root tab is read as "back to Início", the system back's behaviour.
- Sizes come from the 2× PNG and can be a sub-pixel off.
