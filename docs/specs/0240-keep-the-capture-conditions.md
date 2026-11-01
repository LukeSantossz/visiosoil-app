# SPEC: feat(capture): keep the light, distance and focus of the shot with its record

## Problem

The guided camera shows the light in lux, the sheet's distance in centimetres (SPEC 0238) and a focus verdict (SPEC 0166), and all three are lost when the shutter fires.

- **What the mock shows.** The photo screen of the v11 mock lists "Captura · 1.480 lx · 21 cm · nítido" between the coordinates and the model (`docs/design/spec/SPEC.md` §3.8, PNG 19).
- **Why it is absent.** SPEC 0202 left the row out because the app measured none of it (§11 forbids invented values). SPEC 0238 now measures the lux and the distance, and left keeping them with the record to this spec, at schema v12. The focus chip has read "Nítido" or "Desfocado" since SPEC 0166.
- **Why it matters.** The sheet reader and the classifier depend on the light and the distance of the shot (ADR 0017). A record that keeps them lets the agronomist, and a later study of field photographs, tell a shot taken in poor conditions from one that was not.

## Design Decision

**The guided camera hands the lux, the distance and the focus verdict its chips show when the shutter fires to the capture screen, which saves them with the record in three nullable columns. The photo screen shows them as a "Captura" row.**

### What is kept

- **The values shown.** `GuidedCaptureResult.captured(file, conditions:)` carries a `CaptureConditions` with `lux`, `distanceMm` and `sharp`, each nullable. They are the values the light, distance and focus chips show at the moment `_shoot` starts, read before the live reader stops: the shown lux (SPEC 0238's refreshed value), the distance estimate of the shown sheet reading, and the shown focus verdict (`focusOk`). A chip that shows no number, or a focus chip still adjusting, gives null. The automatic capture shoots through the same path, so it keeps them the same way.
- **The raw numbers.** The lux is kept as the sensor read it and the distance in millimetres as estimated; the rounding is the formatters', at display. The focus is kept as the verdict, true for "Nítido" and false for "Desfocado".
- **When nothing is known.** A photograph from the system camera fallback, one recovered after a restart (SPEC 0096) or one from an injected picker keeps null in all three. A retake keeps the new shot's values, and a retried save the values of the photograph it saves.

### Where it is kept

- **Schema v12.** `soil_records` gains `capture_lux` REAL, `capture_distance_mm` REAL and `capture_sharp` BOOLEAN, all nullable. The v11 → v12 step adds them with `addColumn`, so every existing row, tombstones included, arrives with NULL, and nothing is enqueued.
- **The model and the repository.** `SoilRecord` gains `captureLux`, `captureDistanceMm` and `captureSharp`. `create` writes them, the mapper reads them, `SyncLocalStore` carries them on insert and apply as it carries `horizontal_accuracy`, and a delete's tombstone erases them with the rest of the content (SPEC 0093).
- **The capture screen.** The screen keeps the conditions of the photograph it holds beside it, and `_saveCapture` puts them in the record it creates. The record is created as soon as the photograph arrives (SPEC 0219), so no later write is needed.

### Where it is shown

- **The photo screen (PNG 19).** A "Captura" row sits between "Coordenadas" and "Modelo" when the record keeps any of the three. It reads "<lux> · <distance> · <focus>" with `Formatters.lux`, `Formatters.distanceCm` and "nítido" or "desfocado", for example "1.480 lx · ≈ 34 cm · nítido", leaving out what the record does not keep. A record without any shows no row.
- **The focus is the preview's verdict.** It is the frame's variance against `minBlurScore`, not a measure of the still. With the guide on, the shutter waits for it, so most guided records read "nítido"; the Developer chose on 2026-10-31 to keep and show it as the mock does.

## Alternatives Considered

- **Keep the latest sensor reading rather than the shown lux.** Rejected. The record should say what the agronomist saw on the chip when shooting; the two differ by at most half a second of refresh.
- **Leave the focus out.** Proposed, since nearly every guided shot would read "nítido". The Developer chose to keep it, as the mock shows it and a shot taken with the guide's verdict pending or failed is still worth telling apart.
- **Show the row on the details screen's info tiles.** Rejected. The mock places it on the photo screen, which already lists the record's facts row by row.
- **Add the numbers to the shared text and the CSV export.** Left out. Neither the mock nor a request asks for them, and each export's column list is its own decision.
- **Store the rounded values.** Rejected. Rounding is presentation; a study needs the numbers as read.

## Scope

- Includes:
  - `lib/core/features/capture/guided_camera/capture_camera.dart` (`CaptureConditions`, `GuidedCaptureCaptured.conditions`);
  - `lib/core/features/capture/guided_camera/guided_camera_screen.dart` (reading the shown values at the shot);
  - `lib/core/features/capture/capture_screen.dart` (holding the conditions and saving them);
  - `lib/models/soil_record.dart`, `lib/core/database/tables/soil_records_table.dart`, `lib/core/database/app_database.dart` (v12), `lib/core/database/soil_record_mapper.dart`, `lib/core/data/repositories/drift_soil_record_repository.dart`, `lib/core/data/sync/sync_local_store.dart`;
  - `lib/core/features/preview/image_preview_screen.dart` (the "Captura" row);
  - `docs/agents/project.md` (schema v12), and the generated instruction files by `mf agents sync`;
  - the tests below.
- Does NOT include:
  - the shared text, the CSV export, the details screen's tiles;
  - any change to the chips, the verdicts or the shutter (SPEC 0238);
  - iOS, whose chips show no number and whose records keep null.

## Acceptance Criteria

- `test/core/database/migration_v12_test.dart`:
  - `migrates_v11_to_v12_with_null_conditions`: a v11 database with a live record and a tombstone opens at version 12, both rows read NULL in `capture_lux`, `capture_distance_mm` and `capture_sharp`, every other column keeps its value, and the sync queue gains no row.
- `test/repositories/capture_conditions_persistence_test.dart`:
  - `create_keeps_the_conditions`: a record created with a lux of 1483.5, a distance of 339.2 mm and a sharp focus reads them back from `getById`.
  - `create_keeps_null_conditions`: a record created without them reads null in all three.
  - `delete_erases_the_conditions`: the tombstone of a deleted record reads NULL in the three columns.
  - `sync_apply_carries_the_conditions`: a remote record applied through `SyncLocalStore`, inserted and then updated, stores its three values.
- `test/features/capture/guided_camera/guided_camera_numbers_test.dart`:
  - `shot_hands_over_the_shown_numbers`: with a sensor reading of 1480 shown and optics with a found sheet, a shot pops a captured result with a lux of 1480, a distance of 337 ± 1 mm and a sharp focus.
  - `shot_hands_over_null_without_numbers`: with no reading and no optics, a shot pops a captured result whose lux and distance are null.
- `test/features/capture/capture_screen_test.dart`:
  - `guided_shot_saves_its_conditions`: a guided camera popping a lux of 1480, a distance of 339 mm and a sharp focus saves a record holding the three.
  - `system_camera_saves_no_conditions`: a guided camera reporting unavailable, then the system camera's file, saves a record holding null in all three.
  - `retake_saves_the_new_shot_conditions`: a retake whose shot carries other values saves a record holding the new ones.
- `test/features/preview/image_preview_screen_test.dart`:
  - `shows_the_capture_row_with_every_value`: a record with 1483 lx, 339 mm and a sharp focus shows "Captura" reading "1.480 lx · ≈ 34 cm · nítido", between "Coordenadas" and "Modelo".
  - `shows_the_capture_row_with_what_it_has`: a record with only a distance of 339 mm reads "≈ 34 cm"; one with only 87.4 lx reads "87 lx"; one with only a failed focus reads "desfocado".
  - `hides_the_capture_row_without_values`: a record with none shows no "Captura".
- The present suites pass, with the v11 migration test reading the current version as 12.
- On a phone, by hand: a guided shot's photo screen shows a "Captura" row whose values match the chips just before the shutter.

## Reproducibility

Flutter 3.44.1, Dart 3.12.1. Run `dart run build_runner build --delete-conflicting-outputs`, then `flutter test test/core/database test/repositories test/features/capture test/features/preview`, then `flutter test`, `flutter analyze` and `mf check`.

## Risks and Assumptions

- **Stacked on SPEC 0238.** This branch starts from SPEC 0238's, which is not merged and not yet checked on a phone. If 0238 changes, the values handed over follow its chips; if it is dropped, this spec has nothing to keep and waits.
- **The estimate's limits carry over.** The kept distance has SPEC 0238's assumptions (the stream spans the active array's long side, a flat sheet, no distortion), and the kept lux is the light on the phone's face. The row marks the distance "≈" as the chip does; none of the three is used by any verdict after the shot.
- **A remote backend.** No concrete backend exists yet, only the `RemoteSyncBackend` contract. The three fields travel on `SoilRecord`, so a backend that serialises it must add them, as it must for every other column.
