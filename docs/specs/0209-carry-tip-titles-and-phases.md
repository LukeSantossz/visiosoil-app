# SPEC: feat(tips): carry tip titles and crop phases, and filter the Dicas tab

## Problem

The Developer asked on 2026-10-26 for "100% de fidelidade ao mock" ("100% fidelity to the mock"). PNG 20 and the design spec's §3.9 draw three things the Dicas tab cannot show, because a tip carries neither a title nor a crop phase:

- **A timeline by crop phase.** The groups are "Antes do plantio · Agora", "Semeadura · Próximo" and "Ciclo da cultura". SPEC 0205 groups by category instead: Preparo do solo, Culturas, Água, Outras práticas.
- **A titled tip card.** Each card has a 15 sp title in `onSurface` over its text in `onSurfaceVariant`. SPEC 0205's card has the text alone, in `onSurface`.
- **A filter action.** The app bar ends in a Lucide `slidersHorizontal`. SPEC 0205 draws no action there.

## Design Decision

- **The tip contract gains two optional fields**, read defensively like `category`. An unknown value reads as absent, so a corpus that adds a value does not break an older client.
  - `title`: a short imperative heading for the tip.
  - `phase`: one of `before_planting`, `sowing`, `crop_cycle`. These are labelled "Antes do plantio", "Semeadura" and "Ciclo da cultura".
  - `ManagementTip` parses and writes both. The composer passes both through from a corpus cell, as it does `category`. The cache holds them inside the result's JSON, so no schema change follows.
  - On the corpus side, `build_cell_payload` keeps both when present. `validate_cell` refuses an empty `title` and a `phase` outside the three values. The chain that writes cells is not asked for them yet (see Scope).
- **The timeline.**
  - When every tip carries a phase, the groups are the phases, in crop order.
  - Otherwise the groups stay the categories (SPEC 0205), and no chip is drawn.
  - With phases, the first group present is marked "Agora" and the second "Próximo".
    - Rule: a soil sample is taken to plan the season ahead, so the earliest phase the tips speak to is the one to act on now, and the next follows.
    - "Agora": 12 sp weight 600 in `primaryText` on `selected`.
    - "Próximo": the same size in `onSurfaceVariant` on `surfaceContainer`.
    - Both are 24 dp tall, 8 dp in from each side, radius 6, and sit 8 dp after the phase title.
- **The tip card.**
  - With a title, the title is 15/22 weight 600 in `onSurface`, directly over the text at 14/20 in `onSurfaceVariant`.
  - Without one, the text keeps SPEC 0205's form.
- **The filter.**
  - The Dicas tab's app bar ends in a `VisioIconButton` labelled "Filtrar", with Lucide `slidersHorizontal`.
  - It opens a sheet titled "Filtrar dicas", with one `SettingsSwitchTile` per category the tips carry, all on at first.
  - Turning one off hides that category's tips. The "N dicas" chip counts the tips shown.
  - When no tip carries a category, the sheet says "Estas dicas não têm categorias para filtrar."
  - The choice lasts while the tab is open.

## Alternatives Considered

- **Derive the title from the text's first clause.** Rejected: a tip's text is one sentence written as such, and cutting it at a colon or comma would produce headings nobody reviewed.
- **Mark "Agora" from the calendar.** Rejected: it needs the crop and the region's sowing window, which the app does not know. The sampling rule needs neither, and the agronomist's review the corpus already owes covers it.
- **Draw the chips without phases**, on the categories. Rejected: "Agora" on "Água" would say something false about timing.

## Scope

- Includes:
  - `ManagementTip`'s `title` and `phase`, the new `TipPhase`, and the composer passing them through;
  - `corpus/src/cell.py`'s payload and validation, with tests in `corpus/tests`;
  - the timeline's phase groups and chips, and the titled card;
  - the Dicas tab's filter.
- Does NOT include:
  - Asking the corpus chain (B1 to B3) to write titles and phases. That is the corpus build's own change, and until it lands no released cell carries them. The tab keeps SPEC 0205's category timeline for such cells, which is the honest form of the same layout.

## Acceptance Criteria

- `tips_carry_title_and_phase`: `ManagementTip.fromJson` reads `title` and `phase`, writes them back, and reads an unknown phase as absent.
- `composer_passes_title_and_phase`: a corpus cell's tip with both keeps them in the composed result.
- `phases_group_the_timeline`: tips with phases are grouped "Antes do plantio", "Semeadura", "Ciclo da cultura", with "Agora" on the first group and "Próximo" on the second.
- `categories_group_without_phases`: tips without a phase keep the category groups and draw no chip.
- `titled_card_matches_the_mock`: a titled tip shows its title at 15 sp weight 600 and, directly under it, its text at 14 sp in `onSurfaceVariant`.
- `filter_hides_a_category`: turning off "Água" in the filter sheet removes the water tip and the count reads one fewer.
- `corpus/tests`:
  - `build_cell_payload` keeps `title` and `phase`;
  - `validate_cell` refuses an empty title and an unknown phase.
- Existing tests pass.

## Reproducibility

Flutter 3.44.1, Dart 3.12.1, Python 3.12. Run `flutter test`, `flutter analyze`, `python -m pytest corpus/tests -q` and `mf check`.

## Risks and Assumptions

- The "Agora" rule assumes a sample is taken before the season it informs. A sample taken mid-cycle would read "Agora" on pre-planting tips. The rule is stated here so the agronomist's review can overturn it.
- Until the chain writes titles and phases, production cells render the category form. PNG 20's phase form is reached only by cells that carry them.
