# SPEC: feat(capture): start the next capture from a record or the history

## Problem

Field collection records several samples in a row, but after a save the app lands on the new record's details, where the only actions are share and delete (#364). The home screen and the empty history start a capture. Details and a populated history do not, so each new sample means going back to the home first.

There is also a defect in the way a new capture starts. On `main`, the photograph lives in the global `imageProvider`, which is not disposed with the capture screen. A save and "Descartar" clear it, but leaving the screen with back does not. The next capture, from any entry point, then opens on that old photograph with "Salvar registro" showing, and with no classification, because the screen's own state starts fresh. Saving it writes a record with no class. The picker's file, which still carries the original EXIF and GPS (ADR 0005), is never deleted. SPEC 0094 recorded this case and left it out of its scope. A probe test on `main` reproduced it: after back and a second open, "Salvar registro" was shown and the deleter had received nothing.

## Design Decision

**A "Nova captura" icon button in the app bar of details and of a populated history.** Each one is a `VisioIconButton` with the label "Nova captura" and the icon `Icons.add_a_photo_outlined`, and each calls `context.push('/capture')`, as the home and the empty history do. The label is the capture screen's own title and the empty history's button, so one action keeps one name.

- **Details.** The button sits in the pinned `SliverAppBar`'s `actions`, drawn over the photograph (`overPhoto: true`) with the same padding as "Voltar". It is always in view, including on the page a save opens. Only the loaded record shows it, not the load-error or not-found views.
- **History.** The button sits in the app bar before "Selecionar registros", under the same condition: outside selection mode, when the grid shows records. The empty history keeps its own "Nova captura" button and gets no second one.
- **Back restores what launched it.** A push leaves details or history on the stack with its state, so back from a cancelled capture returns to the same record, or to history with its filter, its search term, its scroll position and its shown count. A save replaces capture with the new record's details (SPEC 0132), so back from those also returns to the screen that launched the capture.

**Leaving capture discards its photograph, as "Descartar" does.** The capture screen's `Scaffold` is wrapped in a `PopScope` whose `onPopInvokedWithResult` runs when a pop completes. If a photograph is selected, the screen reads the picked file, the image notifier and the deleter while it is still mounted. Then, once the route's exit transition ends (`ModalRoute.completed`), it clears the image with `clearIfPath` and deletes the picker's file. That way the photograph stays on screen while the page leaves instead of blanking under the transition. While a save is in flight it does not delete the file, and leaves it to the save, which deletes it once it succeeds (SPEC 0094). A save's replacement is not a pop, so this does not run after a save. A save also clears the photograph before it navigates.

Nothing changes in the router, the database or the repository.

## Alternatives Considered

- **A "Nova captura" button at the end of details' action column.** Rejected. After a save the user lands at the top of details, and the actions sit below the classification, the information and the management tips. The app bar is in view at once.
- **A floating action button.** Rejected. On history it would cover the last thumbnails and the "Mostrar mais registros" button at the end of the grid, and no other screen uses one.
- **`pushReplacement('/capture')` from details.** Rejected. It would keep the stack from growing during a session, but back from a cancelled capture would no longer return to the record, which the issue requires.
- **Clear the photograph in the capture screen's `dispose` or `initState`.** Rejected. Riverpod refuses a provider change during a widget lifecycle method, and clearing it after the first frame of the next capture would still show the old photograph for that frame.
- **Clear the photograph at the moment of the pop.** Rejected. The screen watches the provider, so the photograph would vanish while the page is still sliding out.
- **Make the photograph the capture screen's own state instead of the global `imageProvider`.** Rejected for this change. It would fix the leak at its root, but it rewrites the save, retry and discard paths that read the provider, which is a refactor beyond this issue.
- **Keep the photograph across back as a draft, and classify it again on return.** Rejected. The issue asks for a capture that starts without the prior photograph, and a hidden draft would come back on every entry point, including the home.
- **Ask for confirmation before leaving with an unsaved photograph.** Not taken here. Back already gives up the classification, and the photograph that would be lost is retaken from the sample in hand. It can be its own change if field use asks for it.

## Scope

- Includes:
  - `lib/core/features/details/details_screen.dart`: the "Nova captura" action in the `SliverAppBar`.
  - `lib/core/features/history/history_screen.dart`: the "Nova captura" action in the app bar.
  - `lib/core/features/capture/capture_screen.dart`: the `PopScope` and the discard on leaving.
  - `test/features/details/details_screen_test.dart`, `test/features/history/history_screen_test.dart` and `test/features/capture/capture_screen_test.dart`: the tests below.
- Does NOT include:
  - A confirmation before leaving capture.
  - A capture action on the details error and not-found views, on the photo viewer, or anywhere else not named above. The home's "Nova análise" is unchanged.
  - What a save does or the route it opens (SPEC 0132).
  - Replacing the global `imageProvider` with screen state.
  - The capture guide's flow (SPEC 0142) and the lost-capture recovery (SPEC 0096). A recovered photograph is discarded on leaving, like any other.
  - The information architecture's planned direct entry into the camera (`docs/design/ux-2026/04-information-architecture.md` §3). The new actions push `/capture` exactly as the home does, so that change will apply to them unchanged.

## Acceptance Criteria

- `new_capture_from_details`: on a pushed details page, the app bar's "Nova captura" opens `/capture`, and back returns to the same record's details.
- `new_capture_from_history`: on a populated history with a texture class selected, "Nova captura" opens `/capture`, and back returns to history with the class still selected and its records shown.
- `new_capture_follows_the_grid`: history shows "Nova captura" only when the grid shows records and selection mode is off. The empty history shows its own button and no app bar action.
- `leaving_capture_discards_its_photograph`: back from a capture that holds an unsaved photograph keeps the photograph on screen on the first frame of the exit. Once the exit ends, the deleter has received the picked file's path once. The next capture opens with no photograph: "Câmera" is shown and "Salvar registro" is not.
- `leaving_during_a_save_leaves_the_file_to_the_save`: back while a save is in flight does not call the deleter. When the save completes, the record is created and the deleter receives the path once.
- `a_saved_capture_starts_the_next_one_clean`: after a confirmed save, opening capture again shows no photograph and no classification.
- `new_capture_is_labelled`: both actions read "Nova captura" and meet the labelled and Android tap-target guidelines. The existing 200 % text, contrast and capture tests pass, and the existing deleter tests still see one deletion per capture.

## Reproducibility

```sh
flutter test test/features/capture test/features/details test/features/history
flutter analyze && flutter test && mf check
```

Flutter 3.44.1, Dart 3.12.1, `mf` v0.8.0.

## Risks and Assumptions

- **Risk: back now discards a photograph the user meant to keep.** Accepted. On `main` such a photograph came back without its classification, and saving it wrote a record with no class, so nothing usable is lost. The confirmation is recorded above as its own change.
- **Risk: a session started from details builds a stack of details pages.** Each sample started from details adds one, and back walks the session's records newest first. Each page holds one hero image decoded at 280 dp, so the cost is small at field scale. A cancelled capture adds nothing.
- **Assumption: a pop always runs `onPopInvokedWithResult`.** It does for the app bar's back, the system back and `context.pop()`, which are capture's only exits other than a save. The router's `pushReplacement` removes the route without popping it.
- **What would invalidate this spec:** a capture screen that owns its photograph, or a save that no longer replaces capture with details.
