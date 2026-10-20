# SPEC: fix(capture): show the whole camera frame so a sheet filling the guide reaches the model's scale

## Problem

On a 20:9 phone the guided camera crops the 4:3 preview to the screen and draws the sheet outline at 85 % of the screen's width, so a sheet that fills the outline spans about half of the still's width and is read at 0.133 to 0.137 mm/px, coarser than the contract's 0.1292, which refused all five photographs the Developer took in the app on 2026-10-19 as `photographTooCoarse` while the outline said they were framed.

## Design Decision

The preview is drawn whole, with `BoxFit.contain`, so the screen shows the still's whole field of view, and the overlay (outline, target, brackets, arrows, glow) is laid out inside the rectangle the preview occupies rather than the screen. The outline keeps `guideFill` of that rectangle's width, bounded by the space between the banner and the footer as today. On the Developer's phone this puts a sheet filling the outline at about 0.08 mm/px, and leaves a window from about 53 % to the whole preview's width in which the still reaches the scale, where today the window is 88 % to 100 % of the screen. Corners are mapped to the overlay through the same `contain` fit, so a corner leaves the screen only when it leaves the frame. The live too-coarse check (SPEC 0166) stays as the safety net for a phone whose still is too small for the outline, and the `photographTooCoarse` chip names the remedy, "Aproxime o celular da folha".

## Alternatives Considered

- **Keep the cover fit and size the outline from the scale.** Rejected: on this phone the outline would have to fill 93 % of the screen's width, and the window before the sheet leaves the screen would stay a few percent wide, which is the contradiction the Developer met.
- **Accept photographs slightly coarser than the canonical by upsampling.** Rejected: training refuses them too (`ml/src/dataset.py`, SPEC 0053's eleven coarse archive photographs), so the model has never seen an upsampled patch, and `patch_grid.dart` refuses it for that reason. Changing it is an ML decision with no evidence behind it.
- **Ask the camera for a larger still (50 MP).** Rejected: `ResolutionPreset.max` already selects the highest resolution CameraX offers this app on this phone, 3072 × 4096; the 50 MP mode is the vendor camera's.

## Scope

- Includes:
  - `GuidedCameraScreen`: the preview drawn with `BoxFit.contain` on a black background, and the overlay laid out inside the preview's rectangle.
  - `CaptureGuideLayout.compute`: the outline sized from the preview's rectangle instead of the screen.
  - `mapCornersToOverlay` (`guide_alignment.dart`): the `contain` fit in place of the `cover` fit; "past the screen" becomes "past the frame".
  - `classification_failure_chip.dart`: the `photographTooCoarse` label.
  - The capture protocol's chip table (`docs/capture-protocol.md` and its pt-BR copy) for the new label.
  - Tests for each criterion.
- Does NOT include:
  - Any change to the reader, the contract, the patch grid or the too-coarse rule.
  - The live too-coarse estimate (`still_scale.dart`) and its thresholds.
  - Cropping the photograph shown after the capture, other failure visuals, or the pale-table `sheetCropped` refusal, each its own spec.
  - The `image_picker` fallback.

## Acceptance Criteria

- `the_preview_is_shown_whole`: for a 3:4 preview on a 20:9 screen, the preview's displayed rectangle lies inside the screen and spans its full width.
- `the_outline_lies_in_the_preview`: the outline is inside the preview's displayed rectangle and its width is `guideFill` of the rectangle's width, unless the space between the banner and the footer is the bound.
- `a_sheet_filling_the_outline_reaches_the_scale`: on a 1220 × 2712 px screen at its density, a preview of 3072 × 4096 and the shipped contract, a sheet whose corners sit on the outline's corners maps to a still scale finer than `canonicalMmPerPx` by at least 10 %.
- `corners_map_through_the_contain_fit`: a read-frame corner lands where `BoxFit.contain` puts it, within 0.5 logical pixel; a frame of another aspect maps no corner, as today.
- `a_corner_inside_the_frame_is_on_screen`: a corner 5 px inside the read frame's left edge is not reported as off-screen.
- `the_too_coarse_chip_names_the_remedy`: the `photographTooCoarse` chip reads "Aproxime o celular da folha · tire outra foto".
- The existing guided-camera tests pass, amended only where they encode the cover fit.
- Device check (Developer): five photographs in the app, sheet filling the outline, each read finer than 0.1292 mm/px by the SPEC 0170 runner.

## Reproducibility

```sh
flutter test test/features/capture
flutter analyze && flutter test && mf check
VISIOSOIL_PHOTOS=<folder> flutter test test/field_session/field_session_test.dart
```

Flutter 3.44.1, Dart 3.12.1, `mf` v0.8.0.

## Risks and Assumptions

- Assumption: on this phone the preview has the still's 4:3 field of view. It is inferred from the five app photographs, whose scale matches a cover-cropped 4:3 preview to within 1 %, and the device check confirms it.
- Risk: the letterbox leaves black bands above and below the preview. The banner and the footer sit in them, so less of the preview is covered than today.
- Risk: a phone whose preview is 16:9 while its still is 4:3 still shows less than the still. The outline then errs toward a finer scale, and the live check still warns.
- What would invalidate this spec: a device check whose photographs, filling the outline, still read coarser than 0.1292 mm/px.
