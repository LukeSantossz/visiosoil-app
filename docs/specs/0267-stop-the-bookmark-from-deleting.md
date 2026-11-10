# SPEC: fix(details): stop the result's bookmark from deleting the analysis

## Problem

The result screen's app bar shows a filled bookmark, which reads as "saved", and tapping it deletes the analysis.

## Design Decision

**The bookmark leaves the result app bar.** The app bar keeps back and "Compartilhar", 4 dp apart as SPEC 0212 draws them.

How the bookmark came to delete:

- SPEC 0196 put a "Salvar" bookmark on the capture draft, because a result was saved only on that tap, and a filled "Salvo" bookmark on details.
- SPEC 0197 made the filled bookmark a button labelled "Remover dos salvos". It runs the same confirmed delete as "Excluir análise", and it pops once after a capture save.
- SPEC 0219 saved every capture when the photograph arrives and removed the draft's bookmark. Since then every record is saved, so the filled bookmark says nothing about this record, and its only action is the delete.

A bookmark is the platform's sign for "keep this". The UX audit of 2026-11-10 (finding UX-01) found that it opens "Excluir análise" here. The Developer approved removing it on 2026-11-10.

What the bookmark did, and where it now lives:

- **Deleting a record** stays on the Detalhes tab's "Excluir análise", with its confirmation. SPEC 0219 named the bookmark as the one-tap way to remove a poor retake. That removal now takes one more tap, the Detalhes tab.
- **Telling the user the capture was saved** stays with the "Salvo no histórico" snackbar (SPEC 0196, SPEC 0218). It already shows on every capture save.

What goes with it, because nothing else reads it:

- `_SavedBookmark` and its 1 → 1.28 → 1 pop (SPEC 0197);
- `justSavedRecordProvider`, which capture marks only so that details can pop the bookmark;
- `AppStrings.resultRemoveSaved`;
- the `bookmark` parameter of `resultAppBar`.

The v11 design documents record the departure:

- `docs/design/v11/redesign.md` §0.2 gets a row for this spec.
- `docs/design/v11/haptics.md`'s "Save (bookmark)" row says that no bookmark is drawn.

## Alternatives Considered

- **Keep a filled bookmark that does nothing when tapped.** Rejected. Every record is saved, so the icon carries no information, and a filled bookmark still reads as a toggle that the user expects to undo.
- **Keep the control, but draw it as a trash icon labelled "Excluir análise".** Rejected. The result would have two delete controls, which UX-05 asks to reduce to one per intent. The one on the Detalhes tab sits beside the record's data.
- **Keep the bookmark and only relabel it.** Rejected. A label does not change what the icon says to someone who does not long-press it.

## Scope

- Includes:
  - removing the bookmark, its pop, `justSavedRecordProvider` and `AppStrings.resultRemoveSaved`;
  - `resultAppBar` without its `bookmark` parameter;
  - updating the tests that pin the bookmark;
  - the two v11 design documents above.
- Does NOT include:
  - the delete on the Detalhes tab, its confirmation, or an undo for it (UX-11 is its own change);
  - the second share control and the other duplicated result actions (UX-05);
  - the snackbar, its copy or its timing;
  - the bookmark icon inside the management tips section, which marks a tip's source and is not an action;
  - stored data, sync or routes.

## Acceptance Criteria

- `result_app_bar_has_no_bookmark`: details for a saved record shows "Voltar" and "Compartilhar" in the app bar, and finds no `LucideIcons.bookmark` in the app bar and no "Remover dos salvos" tooltip or semantics label.
- The existing details test "confirming delete removes the record, shows a snackbar, and returns home" passes unchanged: on the Detalhes tab, "Excluir análise" opens the confirmation, and confirming deletes the record.
- The existing capture test `capture_writes_the_classification_and_opens_details` passes unchanged: a capture shows "Salvo no histórico" and opens details for the new record.
- `flutter analyze` reports nothing new, `flutter test` has no failures beyond those this machine has on `main`, and `mf check` passes.

## Reproducibility

Flutter 3.44.1 / Dart 3.12.1 in CI. Run `flutter test test/features/details/result_screen_test.dart`, then `flutter analyze`, `flutter test` and `mf check`.

## Risks and Assumptions

- **Removing a poor retake takes one more tap.** Accepted. The Detalhes tab is one tap away. UX-12 adds "Descartar esta foto" to a failed result, which covers the photographs that most need removing.
- **The save loses its pop.** Accepted. The snackbar names the save in words, and the pop was a confirmation of a state that every record now has.
- **Assumption:** nothing outside `details_screen.dart` and `capture_screen.dart` reads `justSavedRecordProvider`. A search of `lib/` and `test/` on 2026-11-10 found no other reader.
