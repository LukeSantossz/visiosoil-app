# SPEC: feat(records): persist the class distribution and the contract versions

## Problem

A classification yields a probability for every class the contract names, and
the contract that scored it names its `model_version` and `dataset_version`.
The record keeps only the top-1 label and its probability, and everything else
is discarded at save (#186). That discarded part is what any later re-analysis
needs. In particular, SPEC 0095 found the distribution underconfident on dish
photographs, and a temperature for the app must be fitted on A4-sheet
photographs. The real-photograph validation owed before the Play release will
create exactly those records. A record saved without the distribution loses it
for good.

## Design Decision

**Schema v7 adds three nullable columns to `soil_records`:**

- **`class_distribution`** (TEXT): a JSON array of `{"label", "probability"}`
  objects in the contract's class order, with probabilities as the contract
  scored them, never renormalised. JSON keeps the column count independent of
  the class list, which is the contract's to change (#186). Contract order is
  fixed, so it encodes no value. The descending view `InferenceResult`
  carries, with its tie-break by contract order, is rebuilt from it
  deterministically.
- **`model_version`** and **`dataset_version`** (TEXT): the versions of the
  contract that scored the photograph.

**All three are nullable, and null means "not known".** A record saved before
v7 has none, and neither has one saved without a classification. A made-up
value would claim a provenance the record never had, which is the reason
`management_tips.corpus_version` is nullable.

**The migration is `if (from < 7)`, adding the three columns.** No earlier
step recreates `soil_records` (v2 and v3 add columns, and v6 only updates
rows), so every upgrade path adds them exactly once. Existing rows, tombstones
included, arrive with the three set to NULL, so SPEC 0093's erased tombstones
stay erased with no v7 scrub. The v6 step's `UPDATE` does not name the new
columns, because on an upgrade from v5 it runs before they exist.

**Where the values come from.** `InferenceResult` gains `modelVersion` and
`datasetVersion`, which `reportFor` fills from the contract, beside the
distribution it already carries. The capture save passes all three to
`SoilRecord`. `SoilRecord` gains `distribution` (`List<ClassScore>?`),
`modelVersion` and `datasetVersion`. The repository encodes the distribution
on create, and `soilRecordFromRow` decodes it.

**A stored distribution that does not decode reads as none.** Only the app
writes the column, so a malformed value means corruption. The record then reads
with `distribution` null, and the failure is logged, because one bad row must
never stop history from rendering the top-1 it still has.

**Everything that writes a record carries the three.**

- **`DriftSoilRecordRepository._tombstone`** erases them on delete. They
  describe what the user captured, and a tombstone keeps only what sync reads
  (SPEC 0093).
- **`SyncLocalStore.insertFromRemote` and `applyRemote`** write them, as they
  write every other content column.

## Alternatives Considered

- **One typed column per class.** Rejected. It would take a migration whenever
  the contract's class list changes (#186).
- **A separate distribution table.** Rejected. The distribution is one-to-one
  with its record. A second table adds a join to every read, and a second place
  a delete must erase.
- **The descending order `InferenceResult` carries.** Rejected for storage.
  That order is decided by the values, and contract order rebuilds it.
- **Persisting the quality-gate flags too, as #186 proposes.** Deferred.
  `ImageQualityAnalyzer` has no production caller on `main`, so there is nothing
  to persist. They join when the gate is wired.
- **A v7 scrub of tombstones.** Rejected. A nullable column is NULL on every
  existing row, so there is nothing to erase.

## Scope

- Includes:
  - `soil_records_table.dart`: the three columns. `app_database.dart`:
    `schemaVersion` 7 and the v7 step. The generated Drift code is regenerated.
  - `SoilRecord`, `soil_record_mapper.dart`, `DriftSoilRecordRepository.create`
    and `_tombstone`, and `SyncLocalStore.insertFromRemote` and `applyRemote`.
  - `InferenceResult` and `InferenceService.reportFor`: the versions.
  - `CaptureScreen._saveRecord`: the three passed to `SoilRecord`.
  - The tests below, and `migration_v6_test.dart` moving its schema-version
    assertion into `migration_v7_test.dart`, as each migration step has done.
  - `docs/agents/project.md` (with `CLAUDE.md` regenerated): schema v7 and the
    migration line.
- Does NOT include:
  - Showing the distribution anywhere, including re-rendering the ADR 0011
    verdict from a stored record. That is the UI/UX roadmap's item 15.
  - The quality-gate flags, inference latency, or any other ADR 0013 Tier 2
    field.
  - Any change to the sync payload's transport. No backend exists.
  - Fitting a temperature (C2, after the sheet photographs).

## Acceptance Criteria

- `schema_version_is_seven`.
- `migration_v6_to_v7_adds_the_columns_as_null`:
  - a v6 database, seeded by hand with a live record and a tombstone, opens at
    v7;
  - both rows hold the three columns as NULL;
  - every other column keeps its value.
- `a_v5_database_upgrades_through_v6_to_v7`: the v6 erase and the v7 columns
  both apply, in one upgrade.
- `a_classified_record_keeps_its_distribution_and_versions`: a record created
  with a distribution and versions reads back with the same distribution, in
  contract order, and the same versions.
- `an_unclassified_record_keeps_none`: all three read back as null.
- `a_malformed_stored_distribution_reads_as_none`: the mapper returns the record
  with a null distribution and keeps the rest.
- `a_deleted_record_erases_its_distribution_and_versions`: `expectErased`
  covers the three columns.
- `a_pulled_record_writes_its_distribution`: `insertFromRemote` and `applyRemote`
  store the three.
- `the_report_names_the_contract_versions`: `reportFor` carries the contract's
  `model_version` and `dataset_version`, and `classify` returns them through the
  isolate.
- `saving_a_classified_capture_persists_the_distribution`: the capture screen
  hands the repository the result's distribution and versions.

## Reproducibility

```sh
dart run build_runner build --delete-conflicting-outputs
flutter test test/core/database test/repositories test/services/inference_service_test.dart test/features/capture/capture_screen_test.dart
flutter analyze && flutter test && mf check
```

## Risks and Assumptions

- **Stacked on #305 (SPEC 0093).** This branch starts from it, because v7
  follows its v6 and both edit the same schema lines. It merges after #305,
  #307 (0094), #309 (0095) and #308 (0096). The other session confirmed that
  #305 is not rebased.
- **Assumption: probabilities round-trip through JSON exactly.** Dart writes
  the shortest decimal that parses back to the same double, so a stored
  distribution equals the one computed.
- **Risk: storage growth.** Four label and probability pairs are about 150 bytes
  per record, which is negligible beside the photograph.
