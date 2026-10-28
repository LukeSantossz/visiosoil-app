# SPEC: fix(capture): name the cause that blocks the shutter

## Problem

The blocked shutter calls every non-ready guidance row a distance problem, and camera switching can select a front camera for a soil photograph.

## Design Decision

A pure helper in `capture_guidance.dart` maps the blocking row and sheet alignment to an optional cause, correction and distance flag. The screen uses that mapping for both the warning and the distance chip, preserving the existing null-reading behaviour and light/focus checks while ordering warning causes as light, focus, then distance or framing, and corrections as light, distance or framing, then focus.

| Blocking row | Cause | Correction | Distance failure |
| --- | --- | --- | --- |
| sheetCropped; sheetMisaligned farther | perto demais | afaste até a folha caber na moldura | Yes |
| tooCoarse; sheetMisaligned closer | longe demais | aproxime até a amostra preencher a moldura | Yes |
| tilted; almostLevel | celular inclinado | deixe o celular paralelo ao chão | No |
| sheetNotFound | folha fora do contorno | enquadre a folha A4 inteira no contorno | No |
| sheetMisaligned shift | folha fora do centro | leve o celular para the banner's existing direction | No |
| sheetMisaligned turn | folha torta | gire o celular até a folha ficar reta no contorno | No |
| soilNotMeasured | solo não medido | coloque o solo no meio da folha, num círculo de 8 a 10 cm | No |
| smallSoil | pouco solo | espalhe num círculo de 8 a 10 cm | No |

Ready returns no failure. A misaligned row without an alignment fix returns no failure rather than inventing a cause. The distance chip fails only for distance failures, shows `Ajustando…` for other blocked rows and `Enquadrada` when ready; without a reading it keeps adjusting. Only distance failures highlight that chip.

`PluginCaptureCamera` retains only back-facing cameras from the plugin's available list. Switching is available with more than one back camera and cycles through that list, retaining flash-off and portrait orientation configuration. The existing platform fake supports tests of this behaviour.

## Alternatives Considered

- Duplicate the mapping in the widget's warning and chips. Rejected because the two could disagree again and the mapping would require widget tests alone.
- Hide camera switching entirely. Rejected because devices with multiple back cameras can still offer a useful choice without selecting a front camera.

## Scope

- Includes: the blocking-cause helper, warning and distance-chip wiring, back-camera filtering and focused unit/widget tests.
- Does NOT include: guidance thresholds, capture eligibility, automatic capture, light/focus detection, camera fallback or other capture UI changes.

## Acceptance Criteria

- `blocking_rows_name_their_real_cause`: each row and alignment fix returns the table's cause, correction and distance flag; ready and missing misalignment fix return null. Shift corrections reuse all four banner directions.
- `non_distance_block_keeps_distance_adjusting`: tilt and missing-sheet warnings name their cause without highlighting or failing the distance chip.
- `blocked_feedback_preserves_causes_and_corrections_order`: the existing cropped-sheet widget test names causes in chip order (light, focus, distance), lists corrections as light, distance, focus and retains its highlights and expiry.
- `switch_cycles_back_cameras_with_flash_off`: switching skips front cameras, wraps between two back cameras and keeps flash off and portrait capture locked.
- `one_back_camera_cannot_switch`: a front camera plus one back camera cannot switch; initialization still selects the back camera. No back camera remains unavailable.
- Existing capture tests pass, including ready and null-reading states.

## Reproducibility

Flutter 3.44.1 / Dart 3.12.1. Run `flutter analyze`, then `flutter test test/features/capture`. Run `dart format` on changed Dart files. Run focused tests before implementation to observe failure.

## Risks and Assumptions

- Alignment and its shift arrow come from the same debounced reading as the row, as the banner already requires.
- Camera availability is sampled at initialization, as before; dynamically discovering lenses is out of scope.
- User-facing copy remains pt-BR, matching the product.
