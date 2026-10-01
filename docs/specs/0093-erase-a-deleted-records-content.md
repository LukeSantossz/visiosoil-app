# SPEC: fix(records): erase a deleted record's content and keep only what sync reads

## Problem

Deleting a record, one or all of them, keeps the following in the database for good, although the app tells the user the records are removed permanently (#277):
- its coordinates, address, capture time and texture class;
- its cached management tips.

## Design Decision

**Scrub the tombstone.** When the repository tombstones a record, it also, in the same transaction:
- clears the content columns:
  - `latitude`, `longitude`, `address`, `texture_class` and `confidence_score` become NULL;
  - `image_path` becomes empty;
  - `timestamp` becomes the deletion instant;
- deletes the record's `management_tips` row.

`timestamp` is NOT NULL, so it takes the deletion instant, which the row already holds as `updated_at`. Nulling it would mean rebuilding the table.

The row keeps `uuid`, `remote_id`, `updated_at`, `deleted` and `sync_status`, and a `delete` is still enqueued. That is everything sync reads from a tombstone:
- `SyncLocalStore.findByUuid` finds it by uuid;
- `SyncEngine` merges on `updated_at` and `deleted`.

Schema v6 applies the same scrub, once, to tombstones written before this change, and deletes their cached tips. It is a data-only step, and no table changes shape.

## Alternatives Considered

- **Hard-delete while no backend is configured.** Remove the rows, their queue entries and their tips, and restore tombstones when a backend lands. Rejected:
  - It suspends the sync design, with its tombstones and delete-wins merge, and the path has to be re-added and re-tested later.
  - "No backend is configured" is not a state the app can observe today, since `SyncEngine` is not wired. So the switch would need a flag of its own.
- **Hard-delete the records no backend has seen, and tombstone the rest.** Rejected:
  - "Never synced" would be inferred from `remote_id` and `sync_status`. A crash between `pushRecord` and `markRecordSynced` leaves those wrong. A record the backend already holds would then come back on the next pull, which is the failure tombstones exist to prevent.
  - It adds a second delete path to test.
- **Scrub new deletions only, with no migration.** Rejected: tombstones already on an upgraded device would keep their coordinates for good, including those on the Developer's test devices. The confirmation their owner answered was the same "removidos permanentemente".

## Scope

- Includes:
  - `DriftSoilRecordRepository._tombstone`, which every delete path goes through, scrubs the content columns and deletes the record's cached tips in the same transaction. Deleting the image file after commit is unchanged (ADR 0003).
  - `AppDatabase`: `schemaVersion` 6, and a cumulative `if (from < 6)` step. For every row with `deleted = 1`, it applies the same scrub and deletes that row's `management_tips` row. By that step, every column and table it touches exists, whatever version the database started from.
  - Tests:
    - the repository's delete paths, asserting the stored row rather than only that reads exclude it;
    - a v5 → v6 migration test;
    - a `SyncEngine` test over a scrubbed tombstone.

    `migration_v5_test.dart`'s `schema_version_is_five` moves to the v6 test as `schema_version_is_six`.
  - `docs/agents/project.md`: the schema is v6 and gains the v5 → v6 step. `CLAUDE.md` and `AGENTS.md` are regenerated with `mf agents sync`.
- Does NOT include:
  - The sync queue. `delete` and earlier `upsert` entries stay pending until a backend drains them. They hold only a uuid, an operation, a status and a date.
  - Hard-deleting rows (see Alternatives Considered).
  - A tombstone pulled from a backend. `SyncLocalStore.insertFromRemote` and `applyRemote` store it as the backend sends it, and scrubbing there belongs to the backend work (#53), since no backend exists.
  - The picker's cached copy of a photograph (#285).
  - The confirmation copy in Settings, the details screen and the history screen. It stays as it is, because with this change it is true: what remains is a random id and the time of deletion.
  - The privacy policy and the Data safety answers (#276).

## Acceptance Criteria

- `delete_by_id_erases_the_record_content`: after `deleteById`, the stored row has:
  - NULL `latitude`, `longitude`, `address`, `texture_class` and `confidence_score`;
  - an empty `image_path`;
  - a `timestamp` equal to its `updated_at`.
- `delete_keeps_what_sync_reads`: after `deleteById`, the row keeps its `uuid`, `deleted = 1`, `sync_status` `pending` and the deletion's `updated_at`. A `delete` operation is enqueued for its uuid.
- `delete_by_ids_erases_only_the_selected_records`: `deleteByIds` scrubs every selected row, and an unselected record keeps all of its content.
- `delete_all_erases_every_record`: after `deleteAll`, no row holds a coordinate, an address, a texture class or a confidence score.
- `delete_removes_the_record_cached_tips`: the deleted record's `management_tips` row is gone, and another record's tips remain.
- `a_scrubbed_tombstone_still_syncs_its_delete`: `SyncEngine` drains the `delete` to a fake backend. The backend receives the record's uuid with `deleted` true and none of its content.
- `schema_version_is_six`.
- `migration_v5_to_v6_erases_existing_tombstones`: in a v5 database, a tombstoned row loses its content, as in the first criterion, and its cached tips.
- `migration_v5_to_v6_keeps_live_records_and_their_tips`: in the same database, a live record and its cached tips are unchanged.

## Reproducibility

`flutter test test/repositories/ test/core/database/ test/services/sync_engine_test.dart`

Flutter 3.44.1, Dart 3.12.1. The migration test builds a v5 database directly with `package:sqlite3`, as the v5 test builds its v4 one.

## Risks and Assumptions

- Assumes nothing outside sync reads a tombstone's content. Every repository read filters `deleted = false`, and `SyncLocalStore` is the only other reader of `soil_records`.
- Take a record deleted before its first sync. When a backend lands, its pending `upsert` pushes an empty row with `deleted` true, instead of the content the user deleted. That is the intent, but the backend's `pushRecord` has to accept a tombstone. This is a note for #53.
- A tombstone's `timestamp` is its deletion time. A backend that reads it as a capture time would be misled. The merge reads `updated_at` first.
- The v6 step runs once, at the first launch after the update, over every tombstone: one `UPDATE` and one `DELETE`.
- A crash between the commit and the image deletion still leaves an orphan image file. That is ADR 0003's residual, unchanged.
