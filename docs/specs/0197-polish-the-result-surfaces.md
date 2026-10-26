# SPEC: feat(details): polish the result surfaces left over from SPEC 0194 and SPEC 0196

## Problem

Five gaps remain in the v11 result surfaces after SPEC 0194 and SPEC 0196:

- The draft result's fixed footer of three stacked buttons crowds out the result on a small phone or at large text.
- A one-word tab label such as "Detalhes" is clipped at 320 dp and 200 % text.
- The saved bookmark does not pop when a save lands on details (redesign §7).
- The filled bookmark does nothing when tapped, although §7 lists "Remover dos salvos".
- A failed classification inside capture still shows the pre-v11 preview, not the error layout of PNG 15.

## Design Decision

- **Inline footer.** `ResultContent` moves its footer from `bottomNavigationBar` to the end of the scrolling body when the screen is shorter than 600 dp or the text scale is 1.3× or more. A fixed footer would cover most of the result there. The rule applies to both hosts.
- **Tab labels.** `SegmentedControl` scales a label down with `FittedBox(fit: BoxFit.scaleDown)` when it is wider than its segment, keeping one line. A word that cannot wrap is never clipped.
- **Bookmark pop.** A successful capture save sets `justSavedRecordProvider` to the new record's id before it replaces the route. Details reads the id once and clears it. The filled bookmark then plays one scale pop, 1 → 1.28 → 1 over 340 ms on `AppMotion.emphasizedDecelerate`. Reduced motion skips the pop.
- **Remover dos salvos.** The filled bookmark becomes a button labelled "Remover dos salvos". It plays `AppHaptics.selection()` and runs the same confirmed delete as "Excluir registro". Removing a saved analysis deletes the record, and the confirmation stays because the action cannot be undone from details.
- **Error layout in capture.** When a classification fails, capture shows the v11 error layout instead of the preview. `ResultErrorBlock` takes optional `onRetake` and `onCaptureTips` callbacks, and capture passes its retake and the capture guide. A retryable cause adds a "Tentar de novo" button keyed `retryClassification`. The photograph and `CaptureActions` stay below the block, so a failed capture can still be saved (SPEC 0173) or discarded.

## Alternatives Considered

- **A row of two secondary buttons in the footer.** Rejected: at 320 dp and 200 % text the row overflows, and that is exactly where the footer is too tall.
- **Removing from saved without a confirmation, with undo.** Rejected: details has no undo window, and the delete is permanent there (SPEC 0093).
- **Keeping the bookmark pop in capture before navigating.** Rejected: it would delay the route replacement that SPEC 0132's tests pin.

## Scope

- Includes:
  - `ResultContent`'s inline footer rule.
  - `SegmentedControl`'s label scaling.
  - `justSavedRecordProvider` and the pop.
  - The removable saved bookmark.
  - The v11 error layout in capture.
  - The `ResultErrorBlock` callbacks.
- Does NOT include:
  - An undo for "Remover dos salvos".
  - Changes to the delete repository, the history swipe, or inference.
  - Label editing on the draft.

## Acceptance Criteria

- `footer_moves_inline_on_a_short_or_large_text_screen`: at 1.3× text, or a 568 dp tall screen, the result footer is inside the scroll view; at 1.0× on an 800 dp screen it is the scaffold's bottom bar.
- `one_word_tab_labels_are_not_clipped`: at 320 dp and 2.0× text, every tab label's rendered width fits its segment.
- `saved_bookmark_pops_after_a_capture_save`: details for the id in `justSavedRecordProvider` animates the bookmark's scale through 1.28 and clears the id. Another record does not animate.
- `filled_bookmark_removes_from_saved`: tapping "Remover dos salvos" opens the delete confirmation, and confirming deletes the record.
- `capture_failure_shows_the_error_layout`: a failed classification shows "Não deu para classificar", the cause's copy, "Fotografar de novo" and "Ver dicas de captura", and keeps "Salvar registro" and "Descartar".
- `retryable_failure_offers_retry`: a timeout adds the retry button, and tapping it reruns the classification.
- Existing capture, details and segmented control tests pass, updated only where the failure body changed.

## Reproducibility

Flutter 3.44.1, Dart 3.12.1. Run `flutter test`, `flutter analyze` and `mf check`.

## Risks and Assumptions

- The Developer asked for every pending v11 visual item on 2026-10-26.
- Scaling a label down trades a smaller glyph for an unclipped word. It only happens at large text on narrow screens.
