# SPEC: feat(capture): retake a photograph without discarding it first

## Problem

Once a photograph is taken, the capture screen offers "Salvar registro" and "Descartar", and "Câmera" is shown only while no photograph exists (#362). To replace a photograph, the user has to discard it first and then open the camera again. If the new photograph never arrives, because the camera was cancelled or failed to open, the first one is already gone, together with its classification and its location.

A retake is the normal answer to most failures the capture preview names. The causes that ask for a new photograph, such as a sheet that was not found or a soil patch that is too small, offer no retry on the chip (SPEC 0105), so on `main` the only way forward is to discard.

## Design Decision

**A "Tirar outra foto" button between "Salvar registro" and "Descartar".** Once a photograph exists, `CaptureActions` shows three buttons in a column:

1. "Salvar registro", the primary action, unchanged.
2. "Tirar outra foto", a new `VisioButton` with the secondary variant and the icon `Icons.camera_alt`, the same icon as "Câmera". It sits 12 dp (`AppSpacing.md`) below Save.
3. "Descartar", unchanged, now 24 dp below "Tirar outra foto". That keeps the 24 dp SPEC 0118 put between Discard and the button above it.

`CaptureActions` gains a required `onRetake` callback. "Tirar outra foto" is disabled while the screen is busy, which means while classification runs or a save is in flight, the same condition that disables Save.

**A save and a retake never run together.** A button's callback comes from the last frame, so both can be tapped before either disables the other. The screen checks its state when each one runs: a save tapped while the camera is open for a retake does nothing, because the photograph is about to change, and a retake tapped while a save is in flight does nothing. Otherwise a save could finish with the previous photograph while the new one stayed in `imageProvider` after the save left capture, and the next capture would open on it without its classification.

**The retake runs the same path as "Câmera", and changes nothing until a new photograph returns.** "Tirar outra foto" calls the screen's existing `_pickImage`. That method checks permission, passes the capture guide (already seen in practice) and opens the camera. The current photograph and its state stay as they are until the camera returns a file:

- **Cancelled.** The picker returns `null`. The photograph, its classification result or failure, and its location stay unchanged, and nothing is classified or deleted.
- **Camera failed to open.** The picker throws. The existing SnackBar "Não foi possível abrir a câmera." is shown, and the photograph and its state stay unchanged.
- **Camera access refused while a photograph is held.** The full-screen `CameraPermissionDeniedView` is not shown, because it would hide the photograph and it has no `PopScope` (SPEC 0146). A SnackBar says "Sem acesso à câmera. A foto atual foi mantida.", and the photograph and its state stay unchanged. Without a photograph, a refusal shows the denied view as it does today. Discarding and then tapping "Câmera" still leads to that view and its "Abrir configurações".
- **New photograph returned.** `_useCapturedImage` replaces the photograph in `imageProvider`, advances the generation and starts location and classification on the new file. That is exactly what a first capture does. The previous photograph's classification and location are dropped, and the generation discards any late result for the previous photograph. The previous picker file is then deleted, best effort, as "Descartar" deletes it (SPEC 0094), because it still carries the original EXIF and GPS (ADR 0005).

**Location is read again for the new photograph.** The record's coordinates are where its photograph was taken. A save does not wait for location (SPEC 0117), so a save made before the new reading resolves has no coordinates, as on a first capture.

**No record is written before Save.** A retake creates nothing, and a save after a retake writes one record, with the new photograph and its classification.

Nothing changes in the router, the database, the repository or `imageProvider`.

## Alternatives Considered

- **Keep the previous location for the new photograph.** Rejected. It would save a GPS wait when the user retakes on the spot, but the record would carry a reading that was not taken with its photograph. It would also need a special case in `startingCapture`, which today resets both axes together. If field use shows that the second reading is slow, this can be its own change.
- **Keep retake enabled while classification runs, as "Descartar" is.** Rejected. `classify` spawns one isolate per call, so a retake during classification would decode two 12 MP photographs at once on the device. Classification takes about 3 s on a sheet photograph (SPEC 0092), so waiting for it costs little.
- **An icon button over the photograph, like "Nova captura" in details.** Rejected. The preview already carries the location and classification chips, and an icon alone is harder to find than a labelled button in the action column, which is where the issue asks for it.
- **Show the denied view on a refusal and wrap it in `PopScope`.** Rejected. The photograph would vanish behind the view, and back from it would discard the photograph, which is what the issue asks to avoid.
- **Ask for confirmation before replacing the photograph.** Rejected. Nothing is replaced until a new photograph exists, and a cancelled camera keeps everything.

## Scope

- Includes:
  - `lib/core/features/capture/widgets/capture_actions.dart`: the "Tirar outra foto" button and the `onRetake` callback.
  - `lib/core/features/capture/capture_screen.dart`: passing `_pickImage` as `onRetake`, the SnackBar in place of the denied view while a photograph is held, and deleting the previous picker file after a replacement.
  - `test/features/capture/capture_screen_test.dart` and `test/features/capture/capture_widgets_test.dart`: the tests below, and `onRetake` added to the existing `CaptureActions` calls.
- Does NOT include:
  - The capture guide (SPEC 0142), what a save does (SPEC 0132), or leaving capture (SPEC 0146).
  - The classification failure chip's copy or its retry rule (SPEC 0105).
  - Keeping a previous location, or any change to how location is read.
  - A picker file left by a retake whose app process Android killed while the camera was open. The lost-capture recovery (SPEC 0096) returns the new photograph, and the previous file stays in the picker's cache, as any picker file does when the process dies.

## Acceptance Criteria

- `retake_replaces_the_photograph`: with a classified photograph held, "Tirar outra foto" opens the camera. When the camera returns a new file, the preview shows the new file, classification and location run again on it, and the deleter receives the previous file's path once. No record is created.
- `cancelling_a_retake_keeps_the_photograph`: when the camera returns nothing, the same photograph, classification result and location are shown. Classification does not run again, and the deleter receives nothing.
- `a_failed_retake_keeps_the_photograph`: when the camera throws, "Não foi possível abrir a câmera." is shown, and the photograph, its result and its location are kept.
- `a_refused_retake_keeps_the_photograph`: when camera access is refused, either denied or permanently denied, while a photograph is held, "Sem acesso à câmera. A foto atual foi mantida." is shown. The denied view is not shown, and the photograph, its result and its location are kept. Without a photograph, a refusal still shows the denied view.
- `retake_waits_for_the_classification_and_the_save`: "Tirar outra foto" is disabled while classification runs and while a save is in flight, and enabled once classification ends, whether it succeeded or failed. A save tapped while the camera is open for a retake creates no record, and a retake tapped in the same frame as a save opens no camera.
- `saving_after_a_retake_saves_the_new_photograph`: a save after a retake creates one record, with the new file's path and the new classification.
- `retake_is_labelled`: "Tirar outra foto" meets the labelled and Android tap-target guidelines, "Descartar" keeps 24 dp from the button above it, and the capture actions lay out at 200 % text with no exception.

## Reproducibility

```sh
flutter test test/features/capture
flutter analyze && flutter test && mf check
```

Flutter 3.44.1, Dart 3.12.1, `mf` v0.8.0.

## Risks and Assumptions

- **Risk: the action column grows by one button,** so the preview gets about 60 dp less height. The preview is `Expanded`, and the 200 % text criterion covers the column itself.
- **Risk: a save right after a retake has no coordinates** while the new reading is still running. Accepted, as on a first capture (SPEC 0117), and recorded above as a possible later change.
- **Assumption: the camera permission is refused while a photograph is held only in rare cases.** Android and iOS end the app's process when a permission is revoked, so this needs a photograph recovered after a restart (SPEC 0096) together with a revoked permission. The SnackBar covers it without a new screen.
- **This change builds on SPEC 0146,** which wraps capture in a `PopScope` and discards the photograph on leaving. It branches from that change and merges after it.
- **What would invalidate this spec:** a capture screen that owns its photograph, or a camera flow that leaves the capture screen.
