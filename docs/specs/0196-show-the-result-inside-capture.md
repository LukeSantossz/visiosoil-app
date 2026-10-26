# SPEC: feat(capture): show the v11 result inside capture and save it from the bookmark

## Problem

After the processing triangle settles, capture goes back to its pre-v11 preview. The v11 result layout (redesign §3.6, PNGs 14, 32 and 33) only appears once the record is saved, so the user never sees the result before deciding to keep it. The result also lacks the triangle card, the bookmark save and the per-level entry haptic that SPEC 0194 deferred until PR #423 merged.

## Design Decision

Extract the classified layout of `DetailsScreen` into a public `ResultContent` widget. It owns the scaffold, the header, the segmented tabs, the entrance motion and the tab state. Each host supplies four things:

- the app bar;
- the Manejo tab;
- the Detalhes tab;
- a footer builder that receives a callback selecting a tab.

`DetailsScreen` keeps its behaviour, footer and unclassified error block. It now hosts `ResultContent`, and its app bar adds a filled bookmark marked "Salvo".

When a classification succeeds and the triangle settles, `CaptureScreen` hosts `ResultContent` for a draft `SoilRecord` built from its state:

- The draft carries the photograph, the location read so far, the class and score, and the time the result arrived.
- The app bar reads "Resultado". Its outlined bookmark, labelled "Salvar", runs the existing `_saveRecord`.
- The footer is the existing `CaptureActions`, so Salvar registro, Tirar outra foto, Descartar and every guard on them (SPEC 0117, SPEC 0132, SPEC 0146, SPEC 0147) are unchanged.
- The Manejo tab says the tips appear once the analysis is saved, because tips are cached against a saved record's uuid.
- The Detalhes tab shows the photograph and the location and time read so far.
- A successful save shows "Salvo no histórico" (redesign §3.13) and replaces capture with details, as today. Details then shows the filled bookmark.

Three smaller changes complete the result:

- **Entry haptic per level (§3.14).** A classification that arrives plays `AppHaptics.result()` for high and moderate confidence, and `AppHaptics.confirm()` for low.
- **Triangle card.** `ResultOverview` gains the "No triângulo textural" card: the static `TextureTriangle` with the class highlighted, "A região {classe} está destacada.", and the diagram's legend. This applies to both hosts.
- **Unchanged failure path.** A failed classification keeps today's preview, cause chip and retry.

## Alternatives Considered

- **Push a separate result route for the draft.** Rejected: the photograph's lifecycle, the late location, the retry and the discard-on-leave guards live in `CaptureScreen`. Moving them would rewrite the SPEC 0117, 0132, 0146 and 0147 contracts this change keeps.
- **Save automatically when classification ends.** Rejected by the Developer: every classified photograph would become a record.
- **Replace `CaptureActions` with the bookmark alone.** Rejected: retake and discard need a visible control, and the guarded save button is what the capture tests pin.

## Scope

- Includes:
  - The `ResultContent` extraction and `DetailsScreen` hosting it, with the filled bookmark.
  - The capture draft result: app bar, bookmark save, Manejo and Detalhes draft tabs, and `CaptureActions` as the footer.
  - The "Salvo no histórico" snackbar.
  - The entry haptic per confidence level.
  - The triangle card in `ResultOverview`.
- Does NOT include:
  - "Remover dos salvos" (tapping a filled bookmark).
  - The bookmark's 1.28 pop animation: the save replaces the route right away.
  - The v11 error layout for a failed classification inside capture.
  - Label editing on the draft.
  - Any change to inference, persistence, routes or the processing view.

## Acceptance Criteria

- `capture_shows_the_result_after_processing`: a successful classification shows "Resultado", the class, the full confidence label and the tabs, and keeps "Salvar registro", "Tirar outra foto" and "Descartar".
- `bookmark_saves_the_draft`: tapping the bookmark labelled "Salvar" writes one record, shows "Salvo no histórico" and opens details for it.
- `draft_manejo_asks_to_save`: the draft's Manejo tab shows the save prompt and no tips section.
- `failure_keeps_the_preview`: a failed classification shows the cause chip and no result tabs.
- `entry_haptic_follows_the_level`: a result at 0.82 or 0.60 plays a medium impact, and one at 0.40 plays a light impact.
- `details_shows_a_filled_saved_bookmark`: a saved record's app bar shows a bookmark announced as "Salvo".
- `overview_shows_the_triangle_card`: the overview shows "No triângulo textural", a `TextureTriangle` highlighting the record's class, and "A região {classe} está destacada.".
- Existing capture and details tests keep passing, updated only where the snackbar copy or the post-processing body changed.

## Reproducibility

Flutter 3.44.1, Dart 3.12.1.

```sh
flutter test test/features/capture test/features/details
flutter analyze
flutter test
mf check
```

## Risks and Assumptions

- The Developer chose the in-capture result on 2026-10-26.
- The draft's time is when the result arrived, while the saved record's time is when it was saved, as today. The two can differ by the seconds the user spends on the result.
- Open PRs #424–#426 touch neither capture nor details, and #429 changes only `displayTextureClass` and the capture chip, so the expected merge conflicts are small.
