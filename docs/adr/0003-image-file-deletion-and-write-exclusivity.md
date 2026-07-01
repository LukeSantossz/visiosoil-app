# Image file deletion and write-exclusivity: delete at tombstone time after commit, refuse overwrite on capture

The repository deletes a record's durable image file when the record is deleted,
through the same `ImageStorageService` boundary that owns the copy side (ADR 0002).
The affected `imagePath`s are collected **inside** the delete transaction and the
files are deleted **after** the transaction commits, so the database stays the source
of truth and a file-delete failure can never abort the tombstone. Deletion is
best-effort and unconfined: an already-absent file is an idempotent no-op, a real I/O
error propagates and is logged by the repository rather than swallowed. As part of the
same lifecycle, `saveCapturedImage` becomes an exclusive write that refuses to
overwrite an existing target.

## Status

Accepted. Implemented under issue #71 (SPEC approved at the Spec Gate). Extends
ADR 0002, which owns the storage/copy side of the same image-file lifecycle and
already deferred the delete path here.

### Decided
- **Delete at tombstone time, after commit** — `_tombstone()` collects the affected `imagePath`s in-transaction, then deletes the files once the transaction has committed. Only files of committed tombstones are removed; the DB is never left inconsistent with the filesystem in the dangerous direction (row live, file gone).
- **Single chokepoint** — `deleteImage(String imagePath)` lives on `ImageStorageService` and is called from `_tombstone()`, so every delete path (single, multi-select, delete-all) cleans up its file in one place.
- **Best-effort, unconfined** — deletes the exact stored path; an absent file is an idempotent no-op (`PathNotFoundException`), a real `FileSystemException` propagates and the repository logs it (`developer.log`) and continues, so one failure never blocks a bulk wipe and nothing is silently swallowed.
- **Exclusive write on capture** — `saveCapturedImage` refuses to overwrite an existing target (throws `FileSystemException`), so a UUID collision cannot clobber another record's image.

## Considered Options

### When the file is deleted
- **Inside the transaction** — rejected: file I/O inside the DB transaction risks a file-gone/row-live inconsistency on rollback and holds the DB lock for the duration of the I/O.
- **At a tombstone purge** — rejected: no purge step exists anywhere; tombstoned rows are never physically removed, so the file would never be deleted.
- **After commit (chosen)** — DB is the source of truth; the only residual is a crash-window orphan, accepted as graceful degradation.

### Whether to confine deletion to the managed directory
- **Confine to `soil_images`** — rejected: the stored path is always self-generated (no untrusted input on the delete path; the traversal vector is the *write*, already guarded), and confinement would leave legacy pre-#70 cache-path records un-cleaned.
- **Delete the exact stored path (chosen)** — honors "delete everything" including legacy records, and is the simplest correct behavior.

### Where best-effort policy lives
- **Concentrate in `deleteImage` (never throw)** — rejected: folds caller policy into the service and prevents a future caller from reacting to a real failure.
- **Service defines success, caller applies policy (chosen)** — `deleteImage` no-ops on absent and propagates real errors; the repository logs and continues.

### Write-exclusivity mechanism
- **Atomic `File.create(exclusive: true)`** — rejected: check-then-copy is more readable and the time-of-check/time-of-use window is irrelevant given random v4 UUIDs plus the DB unique constraint.
- **Check-then-copy throwing `FileSystemException` (chosen)**.

## Consequences

- Deleting a record (single, multi-select, or "Apagar todos os dados") now removes its durable photo; the "permanently delete all data" action no longer leaves geotagged photos on disk.
- A crash between the commit and the file deletion leaves an orphan file — the same residual-risk class as ADR 0002's already-purged-path note; no orphan GC exists yet.
- Real file-delete I/O errors are logged and tolerated; the tombstone always wins.
- A UUID collision now fails capture loudly instead of silently overwriting; because `saveCapturedImage` runs before the transaction, `create()` inserts no row in that case and the existing image is preserved.
- Forward dependency: when blob upload lands (#55/#56), the queue drain must tolerate a missing local blob for a record tombstoned before its upsert synced.
