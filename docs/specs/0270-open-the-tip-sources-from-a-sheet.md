# SPEC: feat(tips): open the sources from a sheet instead of stacking them

## Problem

The tips page stacks every source of the composed cell under the tips, each as plain text with its URL. A cell can hold 14 sources while its tips cite four, so the list runs longer than the tips, and the URLs cannot be opened.

## Design Decision

**The tip cards carry the numbers of the sources they cite, and the sources open in a bottom sheet from one button.** This is variation C of the mock the Developer chose on 2026-11-10.

### Numbering

- A new top-level function, `citationNumbers(tips, sourceCount)`, maps each cited source's index to a number. The numbers start at 1 and follow the order in which `tips` first cite each source.
- An index outside `0 <= i < sourceCount` is ignored, as `_TipCard` ignores it today.
- The numbers come from every tip of the result, not only the tips the category filter shows. Hiding a category therefore never renumbers a chip, and the button's count does not change.
- A result that abstains, or has no tips, has no numbers. Its sources were consulted, and they support no tip (SPEC 0233).

### Tip card

- The card's source line goes away: the bookmark, the first cited title and "+N". In its place, one chip per distinct cited source shows that source's number, in the order the tip cites them.
- A chip is 28 dp tall and at least 28 dp wide, on `selected` with its number in `primaryText` at 12 sp weight 600. These are the colours of the "Agora" phase chip.
- Each chip reads "Fonte N" to a screen reader.
- **The chips are not buttons.** The mock lets a chip open the sheet, but a 28 dp chip is under the 48 dp tap floor the app keeps, and the button below opens the same sheet.

### Button

- Where the list was, the page shows a secondary `VisioButton` with the `bookOpen` icon.
- When some source is cited, it reads "Ver fontes (N citadas)", or "(1 citada)" for one.
- When no source is cited, it reads "Ver fontes consultadas (M)", where M counts every source. This keeps SPEC 0233's wording for sources that support no tip.
- A result with no sources shows no button, as it shows no list today.

### Sheet

- `showModalBottomSheet`, scroll-controlled, with a drag handle like the filter sheet, at most 85 % of the screen's height. Its list scrolls inside it.
- The head is the title and a close `IconButton` (`x`, tooltip "Fechar"). The title is "Fontes", or "Fontes consultadas" when no source is cited.
- When some sources are cited and others are not, a `SegmentedControl` offers "Citadas (N)" and "Todas (M)", and the sheet opens on "Citadas". When every source is cited, or none is, the control is not shown and the sheet lists every source: a choice between two equal lists is not a choice.
- "Citadas" lists the cited sources by number. "Todas" lists them the same way, then the sources no tip cites, in the result's order.
- Each row is at least 48 dp tall and shows:
  - a 28 dp badge with the number, or "·" for a source no tip cites;
  - the title, at most two lines;
  - the publisher, on one line, when there is one;
  - a trailing `externalLink` icon.
- A row is a link to a screen reader.
- **Tapping a row opens the source's URL outside the app**, with `launchUrl` in `LaunchMode.externalApplication`, as Settings opens the privacy policy (SPEC 0157).
- **A launch that fails is said inside the sheet.** That covers a URL that does not parse, a launch that returns false, a `PlatformException` and a `MissingPluginException`. The sheet then shows "Não foi possível abrir a fonte." above the list, as a live region. A `SnackBar` would draw under the sheet, where nobody sees it.
- `_SourcesList` and `_SourceTile` are removed.

The UX audit of 2026-11-10 (finding UX-14) found that sources "cannot be opened". This change makes them open. The Developer approved the layout on 2026-11-10.

## Alternatives Considered

- **Keep the list and make each row open its URL (variation A).** Rejected by the Developer: the page still stacks 14 rows under three tips.
- **List only the cited sources on the page.** Rejected. The sources that no tip cites disappear from the app, while the corpus lists them as the cell's support, and an abstaining cell would show nothing to check.
- **Group the sources by publisher.** Rejected. It shortens nothing when every source has its own publisher, which is the common case.
- **Number the sources by their place in the result, as the list does today.** Rejected. A tip citing sources 9 and 12 shows chips that point into a list the user cannot see. Numbering by first citation makes the first tip read "1, 2".
- **Make the chips open the sheet, as the mock draws them.** Rejected for the tap floor, as above.

## Scope

- Includes:
  - `citationNumbers`;
  - the chips on `_TipCard`;
  - the "Ver fontes" button;
  - the sources sheet and its launch;
  - tests for all of them, and the existing tests that read the old list.
- Does NOT include:
  - the rest of UX-14 (the Dicas tab's record picker and its empty state);
  - the corpus, its sources, or how the composer cites them;
  - the "Atualizar dicas" button and the "Atualizado em" line, which keep their place under the new button;
  - schema, sync or routes.

## Acceptance Criteria

- `citation_numbers_follow_first_citation`:
  - given tips citing `[2, 0]`, `[0]` and `[5]` over 6 sources, `citationNumbers` maps 2 to 1, 0 to 2 and 5 to 3;
  - an index of 6 or -1 is ignored.
- `tip_card_shows_citation_chips`: a tip citing two sources shows the chips "1" and "2", and no bookmark and no source title on the page.
- `sources_are_not_stacked_on_the_page`: with a grounded result, no source title is on the page until the sheet is opened.
- `button_counts_the_cited_sources`:
  - with 1 of 3 sources cited, the button reads "Ver fontes (1 citada)";
  - with 2 cited, it reads "Ver fontes (2 citadas)".
- `sheet_opens_on_the_cited_sources`:
  - with 2 of 3 sources cited, the sheet shows "Citadas (2)" and "Todas (3)", lists the two cited titles, and does not list the third;
  - tapping "Todas (3)" lists the third after them, with the badge "·".
- `sheet_without_a_choice_hides_the_control`: with every source cited, the sheet lists them all and shows no "Citadas" segment.
- `tipless_result_offers_the_consulted_sources`:
  - an abstaining result with 2 sources shows "Ver fontes consultadas (2)";
  - its sheet is titled "Fontes consultadas" and lists both.
- `filter_does_not_renumber_the_chips`: hiding the category of the first tip leaves the second tip's chips and the button's count as they were.
- `tapping_a_source_opens_it`: tapping a row launches its URL in `externalApplication` mode.
- `a_failed_launch_is_said_in_the_sheet`: when the launcher returns false, "Não foi possível abrir a fonte." shows in the sheet.
- `flutter analyze` reports nothing new, `flutter test` has no failures beyond those this machine has on `main`, and `mf check` passes.

## Reproducibility

Flutter 3.44.1 / Dart 3.12.1 in CI. Run `flutter test test/features/details/management_tips_section_test.dart`, then `flutter analyze`, `flutter test` and `mf check`.

## Risks and Assumptions

- **A source's name is one tap further away.** Accepted. The Developer chose this layout, and the card kept only the first cited title anyway.
- **A source whose URL no app can open shows the failure line and nothing else.** Accepted. The row keeps its title and publisher, so the source can still be looked up.
- **Assumption:** every source URL is an `https` link, so the launch targets a browser and not another app. All 58 source URLs in the bundled corpus `2026.10.31.3` are.
