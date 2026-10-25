# SPEC: feat(details): lay out the saved record as the v11 result screen

## Problem

The record screen opened after a save still shows the pre-v11 photo header and one long column, not the result layout of redesign v11 §3.6 (PNGs 14, 15, 26): a confidence header, Visão geral, Manejo and Detalhes tabs, a reference card for the class, and a footer with Corrigir and Dicas de manejo.

## Design Decision

Restructure `DetailsScreen` around a plain `VisioAppBar` titled "Resultado", keeping its "Nova captura" action (SPEC 0146), and build the body from components that already exist.

- **Header.** It shows, top to bottom:
  - the date chip ("dd/MM/yyyy · HH:mm", from `formattedTimestampCompact`);
  - the overline "Classe textural";
  - the class name in `headlineMedium`;
  - a row with the full-label `ConfidenceBadge`, which carries the floored percent (SPEC 0187), beside an animated `ConfidenceBar`;
  - the existing advisory banner for a média or baixa confidence.
- **Tabs.** A `SegmentedControl` with Visão geral, Manejo and Detalhes. The selected tab is local widget state and starts on Visão geral.
- **Visão geral** holds four parts:
  - the intro sentence from §3.6;
  - a "Sobre a classe" card labelled "Referência geral";
  - an "Amostra" card;
  - the laboratory notice.

  The card text is static copy for each class, written from the SiBCS (Embrapa) textural groups that the model's four classes name, never from model output. It lives in `SoilTextureReference`, the second file the texture-class literal guard permits, on the same grounds as `SoilTextureColors` (SPEC 0035): it is not model output, and it returns nothing for a class it does not know. The card carries the note "Faixa típica da classe, não medição desta amostra." The "Amostra" card joins the address, the coordinates and the record's labels. It never lists a layer or moisture state, because the capture protocol does not fix one.
- **Manejo** is the existing `ManagementTipsSection`.
- **Detalhes** holds today's content:
  - the photograph (or the soil sample cut from it, SPEC 0172), as the labelled button that opens the viewer (SPEC 0125);
  - `InfoSection`, with its label editor;
  - Compartilhar and Excluir registro, 24 dp apart (SPEC 0118).
- **Footer.** A fixed footer holds [Corrigir] (outlined, opens the existing labels dialog) and [Dicas de manejo] (primary, selects the Manejo tab). The two stack vertically from a 1.3× text scale (§8) and on a screen 360 dp wide or less (§10), and the confidence badge and bar stack under the same rule.
- **Unclassified record.** A record without a classification replaces the header, tabs and footer with the §3.6 error block:
  - the title "Não deu para classificar";
  - a message that is the record's saved `ClassificationFailureCause` copy (SPEC 0173), or a generic sentence for a record without one;
  - [Fotografar de novo], which opens `/capture`;
  - [Ver dicas de captura], which opens `/capture-guide`.

  The Detalhes content follows the error block, so the record can still be shared and deleted.
- **Entrance.** When the screen opens, its blocks (the header, the tab control and the opening tab, or the error block and the details) rise 8 px and fade in, staggered 30 ms per block over `AppMotion.base`. A later tab change does not replay the entrance, and `AppMotion.durationOf` shortens it under reduced motion.
- **Class colour and missing score.** The header keeps the class's `SoilTextureColors` dot, which history and compare also show. A classified record without a score shows neither the confidence row nor the banner.

## Alternatives Considered

- **Keep the photo `SliverAppBar` as the header.** Rejected: the v11 result has no photograph on top, and the photograph belongs to Detalhes (§3.8).
- **Use a Material `TabBar` with a `TabBarView`.** Rejected: §3.6 names the segmented control, `SegmentedControl` already exists with its haptic and motion, and a swipe-driven view adds page-height constraints the scrolling body does not need.
- **Use the mock's "Classe textural (triângulo USDA)" overline and USDA ranges.** Rejected: the model emits SiBCS textural groups (Arenosa, Media, Argilosa, Muito Argilosa), not USDA classes. A USDA range would describe a class the app never returns.
- **Use the mock's image-quality failure copy ("A foto ficou escura e com reflexo…").** Rejected: that copy reads `ImageQualityAnalyzer`, which has no production caller. The saved failure cause is the reason the app actually knows.

## Scope

- Includes:
  - `DetailsScreen` layout: the app bar, header, segmented tabs, Visão geral cards, the footer, the unclassified error block and the entrance motion.
  - Static per-class reference copy for the four model classes in `lib/core/constants/soil_texture_reference.dart`, with that file added to `test/standards/texture_class_literals_test.dart`'s permitted paths. The guard now matches on full paths rather than file names. The screen's other copy goes in `AppStrings`.
  - `SegmentedControl` gains wrapping labels and a minimum rather than fixed height, so "Visão geral" fits a third of a phone's width at large text. The file is copied byte for byte from open PR #425, which makes the same fix, so the two branches merge cleanly.
  - Updates to the details tests that assumed the photo header or the single column, and new tests for the acceptance criteria below.
- Does NOT include:
  - The "Salvar" bookmark, the "Salvo no histórico" snackbar and the per-level entrance haptic. All three need the capture flow to land on an unsaved result, which changes `capture_screen.dart`, the file open PR #423 rewrites. They follow once #423 merges.
  - The "No triângulo textural" card. `TextureTriangle` exists only in open PR #423.
  - The share icon in the app bar, which the bookmark follow-up places together with the bookmark.
  - The §3.8 detail list restyle, the thumbnail-to-photo Hero and the §3.9 tips timeline (v11 item 11).
  - Offline copy in Manejo, image-quality failure copy, two-column tablet layout (§10), and any change to the classifier, the repository or the database schema.
  - Fractions, top-3 classes or field registration (§11).

## Acceptance Criteria

- `result_header_shows_class_and_confidence`: a classified record shows "Resultado", the date chip, "Classe textural", the class name, the full confidence label with its percent, and a `ConfidenceBar`.
- `result_tabs_switch_content`: the screen starts on Visão geral, showing the intro, "Sobre a classe" and "Amostra". Selecting Manejo shows the tips section. Selecting Detalhes shows the photo button, `InfoSection` and the share and delete actions.
- `about_class_copy_per_model_class`: each of Arenosa, Media, Argilosa and Muito Argilosa renders its own reference sentence and the "Faixa típica da classe" note. An unknown class renders no "Sobre a classe" card.
- `no_texture_class_literal_in_lib` still passes, and its anti-vacuity test proves that both permitted files name the classes.
- `sample_card_joins_location_and_labels`: the Amostra card shows the address, coordinates and labels the record has, and "Sem localização registrada" when it has none.
- `tips_footer_selects_manejo`: tapping "Dicas de manejo" selects the Manejo tab. Tapping "Corrigir" opens the labels dialog.
- `unclassified_record_shows_error_block`: a record with no class shows "Não deu para classificar", its failure cause's copy (or the generic copy without a cause), and [Fotografar de novo] and [Ver dicas de captura], which push `/capture` and `/capture-guide`. It shows no tabs and no footer, and keeps share and delete.
- `result_fits_a_320dp_phone`: on a 320 × 568 dp screen, at 1.0× and 1.29× text in light and Sun, every tab lays out without overflow.
- `entrance_respects_reduced_motion`: under `disableAnimations` the header and blocks settle within 150 ms.
- Existing behaviours stay covered: sharing with and without location, delete confirm and cancel, load error retry, not found, viewer from the photo, Nova captura, label editing, the last action clearing the navigation bar, 200 % text without overflow, and the tap-target and contrast guidelines in light, dark and Sun.

## Reproducibility

Flutter 3.44.1, Dart 3.12.1.

```sh
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter test test/features/details
flutter analyze
flutter test
mf check
```

## Risks and Assumptions

- The Developer approved this partial scope and the SiBCS-based reference copy on 2026-10-25. An agronomist has not yet reviewed the copy, and it should be reviewed before the Play release.
- Moving the photograph into Detalhes retires SPEC 0107's over-photo header controls, because no control sits over a photograph any more. The back button takes the theme's colours.
- `DetailsScreen` serves both a just-saved record and one opened from history, so the result layout applies to both until v11 item 11 splits the detail view, if it does.
- Open PR #425 also edits `app_strings.dart`. This spec only appends constants, so a merge conflict there stays textual.

## Reference

Redesign v11 `docs/design/spec/SPEC.md` §3.6, §3.14, §6.4, §6.5, §8, §11 and §12 item 9, and PNGs 14, 15 and 26.
