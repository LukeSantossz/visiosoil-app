# SPEC: fix(records): delete image files on delete/clear-all and harden image writes

## Problem

Deleting a soil record (single, multi-select, or "delete all") tombstones only the
database row and never removes the durable image file it points at, so captured
geotagged photos remain on disk permanently — including after the user accepts the
"Apagar todos os dados" wipe that promises permanent removal.

## Design Decision

Centralize the image-file lifecycle in `ImageStorageService`: add
`deleteImage(String imagePath)` and call it from the repository's single delete
chokepoint, `_tombstone()`. The repository collects the affected image paths inside
the delete transaction, then deletes the files only after the transaction commits, so
a file-delete failure can never abort the database tombstone and the database stays
the source of truth. `deleteImage` treats an already-absent file as an idempotent
no-op (`PathNotFoundException`) and lets real I/O errors propagate; the repository
logs those via `developer.log` and continues, so a single failure does not block the
rest of a bulk wipe. As part of the same file-lifecycle hardening, `saveCapturedImage`
becomes an exclusive write that refuses to overwrite an existing target, so a UUID
collision cannot clobber another record's image.

## Alternatives Considered

- **Delete files inside the transaction.** Rejected: file I/O inside the DB
  transaction risks an inconsistent state (file gone, row still live) on rollback and
  holds the DB lock for the duration of the I/O.
- **Confine deletion to the managed `soil_images` directory.** Rejected: the stored
  path is always self-generated (no untrusted input on the delete path; the traversal
  vector is the write, already guarded in `saveCapturedImage`), and confinement would
  leave legacy pre-#70 cache-path records un-cleaned, contradicting "delete
  everything".
- **Concentrate best-effort + logging inside `deleteImage` (never throw).** Rejected:
  it folds caller policy into the service and prevents a future caller from reacting
  to a real failure; the service should define success (deleted, or already absent)
  and propagate real errors.
- **Defer file deletion to a tombstone purge.** Rejected: no purge step exists
  anywhere; tombstoned rows are never physically removed, so deferral would mean the
  file is never deleted.
- **Atomic exclusive create (`File.create(exclusive: true)`) for the write.**
  Rejected: check-then-copy is more readable and the time-of-check/time-of-use window
  is irrelevant given random v4 UUIDs plus the DB unique constraint.

## Scope

- Includes:
  - `deleteImage(String imagePath)` on the `ImageStorageService` interface and
    `DefaultImageStorageService`; absent-file is an idempotent no-op, real
    `FileSystemException` propagates.
  - `_tombstone()` collects affected `imagePath`s in-transaction and deletes the
    files after commit, logging real I/O failures without aborting the tombstone.
  - `saveCapturedImage` refuses to overwrite an existing target (exclusive write),
    throwing `FileSystemException` and preserving the existing file.
  - Tests for every path below, written test-first.
- Does NOT include:
  - Tombstone purge or orphan garbage-collection for files already leaked before this
    change.
  - Directory confinement / path validation on delete.
  - Remote blob upload or delete behavior (#55/#56).
  - Migrating legacy pre-#70 cache `imagePath`s.
  - Any UI/UX change to the delete flows (save-failure UX is #72).
  - Changing `create()`'s existing copy-then-rollback behavior.

## Acceptance Criteria

- `deleteById_removes_the_record_image_file_from_durable_storage`
- `deleteByIds_removes_every_selected_record_image_file`
- `deleteAll_removes_all_record_image_files`
- `deleteImage_is_a_noop_when_the_file_is_already_absent`
- `tombstone_survives_when_an_image_file_delete_throws_io_error`
  (the row stays tombstoned and `deleteById` does not rethrow; the failure is
  logged via `developer.log` — observability verified by review, not asserted
  without a logger seam the ADR deliberately omits)
- `saveCapturedImage_throws_filesystemexception_when_target_path_already_exists`
- `saveCapturedImage_preserves_the_existing_file_when_it_refuses_to_overwrite`
- `flutter_analyze_clean_and_full_test_suite_green`

## Reproducibility

- `flutter analyze`
- `flutter test` (full suite); the new service tests live in
  `test/services/image_storage_service_test.dart`, the new delete/cleanup tests
  alongside the existing repository tests.
- Versions: Flutter 3.38.5 (CI canonical); local dev runs 3.44.1 (toolchain
  divergence tracked in #100).
- No randomness in tests: the repository constructor already accepts an injectable
  `uuidFactory`/`clock`, and `DefaultImageStorageService` accepts an injectable
  `baseDirectory`, so file paths and UUIDs are deterministic; no seed is needed.

## Risks and Assumptions

- Assumption: a stored `imagePath` always points at a file this app wrote (no
  untrusted source), so unconfined deletion is safe — invalidated if external or
  user-supplied paths ever enter `image_path`.
- Assumption: no tombstone purge and no remote blob upload exist today, so deleting at
  tombstone time has no dependency — invalidated when #55/#56 add blob upload, at
  which point the queue drain must tolerate a missing local blob for a record
  tombstoned before its upsert synced.
- Assumption: `dart:io` throws `PathNotFoundException` for an absent file on delete
  (Dart 3) — if a platform throws a generic `FileSystemException` for an absent file
  it would be misclassified as a real error, but the caller logs and continues
  regardless, so the tombstone is unaffected.
- Risk: a crash between the commit and the file deletion leaves an orphan file —
  graceful degradation, the same residual risk the system already accepts today.
