# Image file storage and lifecycle: copy captures into app storage, repository owns the file

A captured soil photo is copied into the application documents directory
(`soil_images/<record-uuid><ext>`) and the record persists that **absolute**
path. The copy is performed by an injectable `ImageStorageService` called from
`DriftSoilRecordRepository.create()` **before** the row is inserted, making the
repository the single owner of the image-file lifecycle.

## Status

Accepted. Implemented under issue #70 (SPEC approved at the Spec Gate). The
delete side of the lifecycle is tracked separately (#71) and will live in the
same service/repository boundary.

### Decided
- **Stable location** — copy into `getApplicationDocumentsDirectory()/soil_images`, never persist the `image_picker` cache path that the OS can purge.
- **Filename** — `<record-uuid><source-extension>` (the repository's client-generated UUID v4), `.jpg` when the source has no extension; collision-free and tied to the record.
- **Absolute path stored** — the column keeps the absolute path. Relative-path resolution (robust against iOS container relocation) is deferred to a follow-up; readers stay synchronous.
- **Ownership in the repository** — `create()` copies via an injected `ImageStorageService`; the service is the home for the future delete path, so file lifecycle is not scattered across UI and persistence.

## Considered Options

### Where the copy lives
- **Inline in the repository (no service)** — rejected: mixes file I/O into the DB adapter and forces real file I/O (or platform-channel mocks) in every repository test.
- **In CaptureScreen (UI)** — rejected: splits the file lifecycle between UI (create) and repository (#71 delete), and needs file I/O inside widget tests.
- **Dedicated injected `ImageStorageService` (chosen)** — centralizes the lifecycle and keeps the repository unit-testable via a fake.

### What path is stored
- **Relative path resolved at read time** — rejected for this change: corrects a distinct iOS container-relocation fragility but touches all five readers and app init; deferred to a follow-up issue.
- **Absolute path (chosen)** — smallest correct fix for the reported cache-eviction bug; readers stay unchanged and synchronous.

## Consequences
- New captures survive OS cache eviction; existing records with already-purged paths cannot be recovered (readers already tolerate a missing file).
- `path_provider`/`path` become direct dependencies.
- On iOS the stored absolute path can break if the app container relocates on update — accepted as a known risk and a follow-up issue; Android is unaffected.
- A copy failure aborts `create()` with no row inserted; surfacing that failure to the user is tracked under #72.
- The repository now performs file I/O on `create()`; tests inject a `FakeImageStorageService` (constructor) or override `imageStorageServiceProvider`.
