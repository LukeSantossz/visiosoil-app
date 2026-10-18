# SPEC: feat(capture): read the sheet live on the camera preview

## Problem

The guided camera (SPEC 0165) shows where the sheet and the soil belong but cannot tell whether they are there, so a user still learns that the sheet was cropped, the soil too small or the photograph too coarse only after the shot, from a refusal.

Those are the refusals that stopped all 31 photographs of 2026-10-05 ([the check](../ml/sheet-reader-real-photographs.md)). Each one is decided by arithmetic the app already runs on the still: `findSheet` names a sheet not found or cropped, `locateSoilDisc` measures the soil disc, `patchGeometry` counts the patches the disc holds against the contract's `min_patches`, and `resampleToCanonical` refuses a scale coarser than the contract's canonical one. `findSheet` looks for the sheet on a copy reduced by the whole factor `ceil(longSide / 1024)`, so a 4080 px still is searched at 1020 px.

## Design Decision

**The preview is read by the same reader that judges the still.** No new detector and no new threshold are introduced for the sheet or the soil: the live messages come from `findSheet`, `locateSoilDisc`, `patchGeometry` and `resampleToCanonical`'s rule, with the released contract's `min_patches`, patch side, stride fraction and canonical scale. A live verdict is guidance only. The still is judged again in full by `InferenceService`, as today.

**Frames.** `CaptureCamera` gains the preview stream (`startImageStream` / `stopImageStream`). Only **one frame is in flight** at a time: a frame that arrives while one is being read is dropped, never queued, which caps the rate at what the device can read. The target is about three readings a second. A frame becomes a grey `RgbFrame`, the grey replicated into the three channels, in three steps on the UI isolate, each a plain copy:

1. **Grey.** Android, `ImageFormatGroup.yuv420`: the Y plane, which is the luma, copied row by row so the plane's `bytesPerRow` padding is dropped. iOS, `ImageFormatGroup.bgra8888`: each pixel through the reader's own `greyOf`, also honouring `bytesPerRow`. `findSheet` and `locateSoilDisc` reduce every pixel through `greyOf` before any decision, so a grey frame replicated into three channels feeds them what a colour frame of the same luma would.
2. **Portrait.** The frame is rotated clockwise by the `sensorOrientation` the camera reports, so the sheet's long side is vertical as it is on the still, whose capture orientation SPEC 0165 locks to portrait-up. Amended in implementation: that holds on Android, whose stream is in the sensor's orientation; on iOS, `camera_avfoundation` applies the locked capture orientation to the stream's connection as well, so its frames arrive portrait and turn by 0:

   | `sensorOrientation` | Output pixel (x, y) is source pixel | Output size |
   |---|---|---|
   | 0 | (x, y) | w × h |
   | 90 | (y, h − 1 − x) | h × w |
   | 180 | (w − 1 − x, h − 1 − y) | w × h |
   | 270 | (w − 1 − y, x) | h × w |

3. **Size.** A frame whose long side exceeds 1024 px is resized to a long side of exactly 1024 px and a short side of `max(1, roundHalfEven(short × 1024 / long))`, so `findSheet` searches it at factor 1, within 2.5 % of the resolution it searches a 4000 to 4080 px still at. The resize is the Pillow-compatible bilinear that `patch_grid.dart` already holds for `resampleToCanonical` (ADR 0025), whose downscale widens its support to the scale and so averages every source pixel it covers, fractional edges included. It is made callable from the guided camera, unchanged. A smaller frame is read as it is and never enlarged.

**`LiveSheetReader`** runs in **one long-lived isolate**, because spawning an isolate per frame costs more than the reading. The contract's numbers are sent to it once, when it is spawned. Each request carries a generation number, and each reply carries it back. It returns a `LiveReading`, never pixels:

- `sheetNotFound` or `sheetCropped`, from `findSheet`;
- or `sheetFound`, with the sheet's long side in the read frame's pixels, and the soil disc's diameter in millimetres, or `soilNotMeasured` when `locateSoilDisc` returns null. That null covers a sheet with no soil, too little contrast between soil and paper, and a patch thinner than the reader's margin, which the still also refuses alike, as `soilRegionTooSmall`.

**Its lifecycle is explicit.** The reader is spawned when the stream starts. Stopping it, on the shutter, on any lifecycle event that releases the camera, on close and on dispose, is one sequence: stop accepting frames, increase the generation, call `stopImageStream`, and kill the isolate. A reply whose generation is not the current one is discarded, so nothing read before a stop reaches the banner after it. Starting the stream again spawns a new isolate. The shutter does not wait for a reading in flight: the reader holds its own copy of the frame and touches neither the camera nor the still.

**The still's scale is estimated from the preview.** The still's millimetres per pixel are 297 mm over the sheet's long side in read-frame pixels times the ratio between the still and the read frame. The ratio is `min(stillWidth / frameWidth, stillHeight / frameHeight)`, every size in portrait and the frame's after step 3. When the read frame is a crop of the still's field of view, which is how a preview of another aspect is framed, the axis it does not crop gives the exact ratio and the cropped one a larger ratio, so the minimum is exact there and errs toward "too coarse" everywhere else. The estimate fails the scale check when it is coarser than the contract's canonical millimetres per pixel, the rule `resampleToCanonical` applies.

**The still's size is learned, not assumed.** The plugin reports the preview's size but not the size `takePicture` will produce at `ResolutionPreset.max`. So every still the guided camera takes has its width and height read from its JPEG frame header, swapped when its EXIF orientation is 5 to 8 so they are in portrait, and stored by a `StillSizeStore` in `shared_preferences` under `guided_camera_still_size`. The scale check uses the stored size. Until a still has been taken on the device, or if the store cannot be read, row 4 never holds and the still's own reader decides, as it does today; the first photograph through the guided camera teaches the size. A store that cannot be written loses only that.

**`CaptureGuidance` combines the reading with the tilt** of SPEC 0165. The first condition that holds sets the banner:

| # | Condition | Colour | Sentence |
|---|---|---|---|
| 1 | Tilt over 12° | red | "Segure o celular paralelo ao chão, de cima." |
| 2 | Sheet not found | red | "Enquadre a folha A4 inteira no contorno." |
| 3 | Sheet cropped | red | "A folha está cortada. Afaste o celular." |
| 4 | Still's scale too coarse | amber | "Aproxime o celular da folha." |
| 5 | Soil not measured | amber | "Coloque o solo no meio da folha, num círculo de 8 a 10 cm." |
| 6 | Disc holds fewer than `min_patches` patches | amber | "Pouco solo (X cm). Espalhe num círculo de 8 a 10 cm." |
| 7 | Tilt over 5° and up to 12° | amber | "Quase. Deixe o celular paralelo ao chão." |
| 8 | Otherwise | green | "Pronto. Segure firme." |

The colours are SPEC 0165's, through `guidanceColors`: each role's container with its own ink (`primaryContainer`/`onPrimaryContainer` for green, `warningContainer`/`onWarningContainer` for amber, `errorContainer`/`onErrorContainer` for red), each with its own icon. In `tiltUnavailable` (SPEC 0165), rows 1 and 7 never hold, and row 8 reads "Folha e solo certos." on `primaryContainer`, because nothing says the phone is level. Before the first reading arrives, the banner is SPEC 0165's tilt banner.

**Every refusal the still can meet on the A4 path has a row or cannot happen there.** `sheetNotFound` and `sheetCropped` are rows 2 and 3, `photographTooCoarse` row 4, and `soilRegionTooSmall`, whether from a null disc or too few patches, rows 5 and 6. `soilRegionOutsideFrame` needs no row: `a4SheetMeasurer` rectifies a square reaching 1 mm (`_squarePadMm`) beyond the soil disc on every side, and `patchGeometry` places every patch inside the disc, so the grid lies in the square by construction; the check that names it is a guard against rounding. The classification's own failures, a timeout or an isolate failure, are not about the photograph and have no live counterpart.

In row 6, X is the soil patch's diameter in centimetres to one decimal, with a comma: the disc's diameter plus twice the reader's `soilMarginMm`, which is the size the user spread and the size the protocol names.

**The banner does not flicker.** A reading changes the reader's rows only once two consecutive readings agree on the row. The tilt rows follow the smoothed tilt at sensor rate, as in SPEC 0165.

**Entering green gives a selection tick**, `AppHaptics.selection()`, once per entry. The photograph's return keeps the `AppHaptics.confirm()` `CaptureScreen` already gives.

**A reader that fails never blocks.** If the isolate reports an error, exits, or holds a reading for more than 2 s, the reader is stopped by the sequence above, the stream is not restarted for the rest of the visit, the banner falls back to SPEC 0165's, and the error is recorded in `ErrorReportStore` with the source `live_sheet_reader`. The shutter works throughout. SPEC 0167 reads this state as disarmed.

## Alternatives Considered

- **A lighter detector for the live view, such as an edge or rectangle detector.** Rejected. It would tell the user one thing and the reader another, and every threshold in it would be new and uncalibrated. Reusing the reader makes the live verdict and the still's verdict share every number.
- **Live blur, exposure and glare through `ImageQualityAnalyzer`.** Deferred. Its thresholds are engineering starting points with no real photograph behind them (#244), and an uncalibrated live warning teaches the user to ignore the banner.
- **Drawing the detected sheet's outline on the preview.** Deferred. It needs a mapping from frame coordinates to the cover-fitted screen, and the banner already says what is wrong.
- **An isolate per reading with `Isolate.run`.** Rejected for its spawn cost at three readings a second.
- **Feeding the frame at the stream's own size.** Rejected. `findSheet`'s whole-factor reduction would search a 1280 px frame at 640 px, coarser than it searches any still.

## Scope

- Includes:
  - `CaptureCamera`: the preview stream, the image format per platform, the sensor orientation and the still's size.
  - `lib/core/features/capture/guided_camera/`: the frame conversion, `LiveSheetReader` and its isolate, `LiveReading`, the scale estimate, `StillSizeStore`, the extended `CaptureGuidance`, and the debounce.
  - `lib/core/services/descriptors/patch_grid.dart`: the existing bilinear resize made callable from outside the file, with no change to its arithmetic.
  - `GuidedCameraScreen`: the stream's start and stop, the banner from the combined guidance, the haptic, and the fallback.
  - Tests for each criterion.
- Does NOT include:
  - Automatic capture (SPEC 0167).
  - Live blur, exposure or glare checks.
  - Drawing the detected sheet or disc on the preview.
  - Any change to `findSheet`, `locateSoilDisc`, `patchGeometry`, the resize's arithmetic, the contract, the reader's thresholds, or what the still's classification refuses.
  - Adapting the reading to a slow phone; the time per reading is measured here, and a remedy, if one is needed, is its own spec.

## Acceptance Criteria

- `yuv_luma_drops_row_padding`: a synthetic Y plane with `bytesPerRow` larger than its width converts to an `RgbFrame` whose pixels equal the unpadded luma in all three channels.
- `bgra_converts_to_the_readers_grey`: a synthetic BGRA plane with row padding converts to the grey `greyOf` gives for the same colours, replicated into the three channels.
- `the_frame_is_turned_portrait`: a 3 × 2 frame with distinct pixels converts, for each `sensorOrientation` of 0, 90, 180 and 270, to the frame the table gives.
- `a_large_frame_is_read_at_1024`: a 1920 × 1080 frame is reduced to 1024 × 576, a 4000 × 3000 one to 1024 × 768, a 1280 × 721 one to 1024 × 577, and a 800 × 600 one is left as it is; each reduced frame equals the existing bilinear resize's output for that size byte for byte.
- `the_still_size_is_learned`: a captured JPEG of 4000 × 3000 with EXIF orientation 6 stores 3000 × 4000; one of 3000 × 4000 with orientation 1 stores 3000 × 4000; with no stored size, a reading that would be too coarse gives row 5, 6 or 8, never row 4; with a stored size, it gives row 4.
- `the_live_reading_matches_the_colour_reading`: for each of the six real photographs in `test/fixtures/sheet_photos/`, already at a long side of 1024 px or less, the frame converted to grey and read by `LiveSheetReader` gives the verdict `findSheet` and `locateSoilDisc` give on the colour frame: found, cropped or not found, and, when found, the same answer on `min_patches`, with the disc's diameter within 1 mm.
- `the_scale_estimate_uses_the_uncropped_axis`: for a still of 3000 × 4000 and a read frame of 576 × 1024, the ratio is 4000 / 1024; a sheet whose long side spans 900 frame pixels estimates 297 / (900 × 4000 / 1024) mm/px, which passes the canonical scale, and one spanning 500 frame pixels fails it.
- `guidance_follows_the_priority`: each row of the table is returned when its condition is the first that holds, including a cropped sheet at a 20° tilt giving row 1 and a small disc at 8° giving row 6; under `tiltUnavailable`, a cropped sheet gives row 3 and a sound reading gives "Folha e solo certos.".
- `the_small_soil_sentence_names_the_size`: a disc of 47.1 mm with the reader's 2 mm margin gives "Pouco solo (5,1 cm). Espalhe num círculo de 8 a 10 cm."
- `one_reading_does_not_change_the_banner`: a single reading of a new row leaves the banner unchanged, and a second consecutive one changes it.
- `one_frame_in_flight`: with a reader that does not answer, further frames from the fake camera are dropped and none is queued.
- `a_stale_reading_is_discarded`: a reply carrying an earlier generation than the current one, arriving after a stop and a restart, does not change the banner.
- `entering_green_ticks_once`: entering green twice, with a non-green reading between, gives two `selection` haptics; staying green gives one.
- `a_failed_reader_falls_back`: a reader that reports an error, exits, or does not answer within 2 s by the fake clock is stopped, the stream is not restarted, the banner shows SPEC 0165's, the shutter captures, and `ErrorReportStore` holds one entry with the source `live_sheet_reader`.
- `the_shot_stops_the_reader_first`: on a tap, the fake camera sees `stopImageStream` before `takePicture`, the reader's isolate is killed, and no wait on the reading in flight delays `takePicture`.
- `the_lifecycle_stops_the_reader`: `inactive` stops the stream and kills the reader; `resumed` starts a new stream and a new reader; dispose leaves neither running.
- On a device (Developer), observational: on the Developer's phone, in a release build (`flutter run --release`), with its model, OS and the stream's frame size recorded in the PR, the first 10 readings over a sheet are discarded as warm-up and the next 30 consecutive ones are timed by a `Stopwatch` on the UI isolate, from the frame being accepted to its reply arriving. The median and maximum of those 30 and the readings per second over them are recorded, not gated; a median above 300 ms opens a follow-up spec.

## Reproducibility

```sh
flutter test test/features/capture test/services/a4_sheet_photos_test.dart
flutter analyze && flutter test && mf check
```

Flutter 3.44.1, Dart 3.12.1, `mf` v0.8.0.

## Risks and Assumptions

- **Risk: the reader is slow on a low-end phone.** The one-in-flight rule lowers the rate instead of queueing, and the shutter never waits on a reading.
- **Risk: the preview's grey is not the still's grey.** The camera's luma and `greyOf`'s weights differ slightly, and the preview is processed by the camera pipeline differently from the still. The live verdict is guidance: the still is judged by the reader on the full photograph, so a disagreement costs a retake, never a wrong classification.
- **Assumption: the still's field of view contains the preview's.** It holds when the preview is a crop of the sensor's field, which is how the platforms' camera pipelines frame a preview of a different aspect. `the_scale_estimate_uses_the_uncropped_axis` covers the arithmetic, and SPEC 0167's field session covers the assumption.
- **Assumption: the conversion on the UI isolate fits a frame's budget.** It is three plain copies of at most one frame at a time. If the device measurement shows dropped UI frames, moving the conversion into the reader's isolate is a follow-up.
- **Risk: battery.** The stream runs only while the guided screen is open.
- **What would invalidate this spec:** a change to the reader's inputs, such as a colour-dependent step in `findSheet` or `locateSoilDisc`, which a grey frame would no longer feed faithfully.
