# SPEC: feat(details): redesign the sample photo and the management tips as v11 surfaces

## Problem

Two v11 surfaces are still in their pre-v11 form:

- §3.8 (PNG 19) asks for a "Foto da amostra" screen with the photograph on top, a list of label/value pairs, share and delete, reached by a Hero from the photograph. The `/preview` viewer shows only the photograph (SPEC 0125).
- §3.9 (PNG 20) asks for the tips as a timeline of cards with an icon and a source line under a context header. They are a flat list of cards with numbered citation chips.

## Design Decision

- **"Foto da amostra" screen.** `/preview` keeps its route and its black canvas.
  - App bar: "Foto da amostra", with "Fechar" and a share action.
  - Photograph: in the existing `InteractiveViewer`, at most 60 % of the screen height, wrapped in a `Hero` tagged `recordPhotoHeroTag(record.id)`.
  - Label/value list, one row per known fact:
    - "Classe estimada": the display label;
    - "Confiança": the level and the floored percent, as "Alta · 82%";
    - "Data e hora": `timestampDotted`;
    - "Coordenadas";
    - "Precisão";
    - "Endereço";
    - "Modelo": "no aparelho · v{modelVersion}".
  - "Excluir registro" closes the list.
  - Facts the app does not measure are left out. That includes the mock's lux, distance and sharpness.
  - Sharing and deleting reuse `shareRecordWithConsent` and `confirmAndDeleteRecord`, now shared with details.
  - The photograph in the result's Detalhes tab carries the same Hero tag, so opening the viewer flies the photograph.
- **Tips timeline.** `ManagementTipsSection` groups the tips by their `TipCategory`, in a fixed order with fixed headings:
  1. Preparo do solo
  2. Culturas
  3. Água
  4. Outras práticas

  Each group has a dot on a vertical rule. Each card shows the category's icon, the text, and a source line with the first cited source's title and publisher, plus "+N" when more sources are cited. The header adds "{classe} · {n} dicas". The loading copy becomes "Carregando dicas" (§3.9). The numbered sources list, the disclaimer, the update time and "Atualizar dicas" stay.
- **No crop phases.** The mock's phase names ("Antes do plantio", "Semeadura") are not used, because tips carry a category and no phase, and §11 forbids the mock's fictional data.

## Alternatives Considered

- **Put the label/value list in the result's Detalhes tab.** Rejected: PNG 19 is its own "Foto da amostra" screen, and the Detalhes tab already holds the identification editor.
- **Group the tips by an inferred crop phase.** Rejected: no field supports it, and guessing a phase would misstate the source.
- **Keep numbered citation chips on each card.** Rejected: PNG 20 shows a source line. The numbered list below still gives every source in full.

## Scope

- Includes:
  - The `/preview` redesign and its Hero.
  - The shared share and delete helpers.
  - The tips timeline, card, header context and loading copy.
  - Updates to the preview and tips tests that pinned the old layout (SPEC 0125's photo-only viewer).
- Does NOT include:
  - The Dicas tab's record picker or the mock's crop and season context.
  - New tip data fields, or corpus and composer changes.
  - Changes to how tips are generated or cached.

## Acceptance Criteria

- `photo_screen_lists_the_known_facts`: a classified, located record with a model version shows "Foto da amostra", the class, "Alta · 82%", the date, the coordinates and "no aparelho · v{version}". A record without coordinates shows no "Coordenadas" row.
- `photo_screen_shares_and_deletes`: the share action reaches the share service, and "Excluir registro" deletes the record after confirmation.
- `photo_flies_from_the_details_tab`: the Detalhes tab photograph and the viewer photograph carry the same Hero tag.
- `tips_render_as_a_timeline_by_category`: tips of two categories render under their two headings in the fixed order, each card with its category icon and its source line.
- `tips_header_counts_the_tips`: the header reads "{classe} · {n} dicas".
- `tips_loading_reads_carregando`: while generating, the section reads "Carregando dicas".
- Existing details, preview and tips tests pass, updated only where they pinned the replaced layout.

## Reproducibility

Flutter 3.44.1, Dart 3.12.1. Run `flutter test`, `flutter analyze` and `mf check`.

## Risks and Assumptions

- The Developer asked for every pending v11 visual item on 2026-10-26.
- SPEC 0125 deliberately made the viewer photo-only. Redesign v11 §3.8, which the Developer approved, supersedes it for this screen.
