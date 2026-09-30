# SPEC: fix(capture): delete the picker's copy once the photograph is stored

## Problem

Every capture leaves the camera's original in the app cache after the record is saved, and every discarded capture leaves its file there too, with the original's EXIF, GPS included (#285). ADR 0005 strips that EXIF from the durable copy only.

## Design Decision

**The capture screen deletes the file it got from the picker**, best effort:
- after the repository confirms the save;
- when the user discards the capture.

A failed save keeps the file, so the retry the screen offers still has its photograph.

The deletion goes through an injectable `PickedFileDeleter` seam on `CaptureScreen`, like the picker, location and permission seams beside it. Its default, `deletePickedFile`, deletes the file and treats an absent one as done. The screen logs any failure and never lets it fail the save or the discard, following ADR 0003's policy for durable images.

## Alternatives Considered

- **Move instead of copy in `ImageStorageService.saveCapturedImage`.** Rejected: the copy runs before the database write, and `create` deletes the durable copy when that write fails. After a move, the source would be gone too, so the retry the screen offers would have no photograph left to save. It would also change that service's contract, which is about the durable copy (ADR 0002).
- **Delete the source in `DriftSoilRecordRepository.create` after commit.** Rejected: the repository would delete a file it did not create, on behalf of one caller, and it cannot tell a picker file from any other path it is handed. The screen took the file from the picker, so it owns the file's life.

## Scope

- Includes:
  - `lib/core/features/capture/capture_screen.dart`:
    - the `PickedFileDeleter` typedef and seam;
    - the top-level `deletePickedFile` default;
    - the deletion after a confirmed save and on discard.
  - `test/features/capture/capture_screen_test.dart`: the harness injects a recording deleter by default. That keeps the shared sample file every test captures from being deleted by a successful save.
- Does NOT include:
  - A photograph selected when the user leaves the capture screen without saving or discarding. The global `imageProvider` still holds it, and it comes back on return.
  - A photograph lost when the system kills the app during capture (#284).
  - The durable copy, its EXIF strip (ADR 0005) and its deletion with the record (ADR 0003, SPEC 0093).
  - Clearing files an earlier version left in the cache. The OS evicts the cache, and the app does not list it.

## Acceptance Criteria

- `a_saved_capture_deletes_the_picker_file`: after a confirmed save, the deleter receives the picked file's path, after the repository's `create`.
- `a_failed_save_keeps_the_picker_file`: when `create` throws, the deleter is not called.
- `a_discarded_capture_deletes_the_picker_file`: tapping "Descartar" passes the picked file's path to the deleter.
- `a_failed_deletion_does_not_fail_the_save`: when the deleter throws, the save still:
  - creates one record;
  - shows "Registro salvo com sucesso!";
  - pops the screen.
- `the_default_deleter_removes_the_file_and_ignores_an_absent_one`: `deletePickedFile` removes a real temp file, and completes without throwing for a path that does not exist.

## Reproducibility

`flutter test test/features/capture/capture_screen_test.dart`

Flutter 3.44.1, Dart 3.12.1.

## Risks and Assumptions

- Assumes `image_picker` hands the app a file of its own, in the app's cache on Android and in its temporary directory on iOS, which nothing else reads. Deleting it after the save removes nothing a record points at, because the record points at the durable copy.
- "Descartar" stays enabled while classification runs, so a discard can delete the file mid-classification. The discard already moves the capture to a new generation, so the late result is ignored. On Android and iOS, unlinking a file that is open does not break a read in progress.
