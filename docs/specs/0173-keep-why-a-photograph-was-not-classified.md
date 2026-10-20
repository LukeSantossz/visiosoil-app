# SPEC: feat(details): keep why a photograph was not classified and show it on the record

## Problem

A record saved without a classification keeps no cause, so its details say only "Não classificado" and "capture a amostra de novo seguindo o passo a passo", and the agronomist who reopens it in the field cannot tell whether the sheet was not found, the soil was too small or the phone was too far.

## Design Decision

The record keeps the failure cause the capture preview already names. A nullable `classification_failure` text column holds the cause's enum name, and schema v10 adds it, null on every existing row as v7 to v9 did. `SoilRecord` carries it as `ClassificationFailureCause?`. The capture save writes it only when classification failed, and a stored name the app no longer knows reads as null rather than failing the record. The details header shows the same label the capture chip shows (`classificationFailureChip`) under "Não classificado", and the management-tips empty state names it as the reason. A tombstone erases it with the rest of the content (SPEC 0093). A retried classification that succeeds leaves it null.

## Alternatives Considered

- **Keep the cause only in the session, as today.** Rejected: the record is what the agronomist reopens, and this is where the Developer met the missing reason.
- **Store the label text instead of the cause.** Rejected: a later change to the wording, such as SPEC 0171's, would leave old records with the old advice, and the enum name lets the details show the current label.
- **Reclassify the stored photograph on opening the details to recover the cause.** Rejected: seconds of work on every opening to recover a fact known at save time, and it would change the record's meaning if the reader changes.

## Scope

- Includes:
  - `soil_records_table.dart`: the `classification_failure` column; `AppDatabase` schema v10 and its migration step; the regenerated Drift code.
  - `SoilRecord` and `soil_record_mapper.dart`: the field and its mapping, unknown names read as null.
  - `DriftSoilRecordRepository`: writing it on create and erasing it on tombstone.
  - `CaptureScreen._saveRecord`: passing the shown failure cause.
  - The details header and the management-tips empty state: the label.
  - `docs/agents/project.md` (the source `CLAUDE.md` is generated from): schema v10 and the column.
  - Tests for each criterion.
- Does NOT include:
  - Sync's wire format, which has no backend yet.
  - The history card, the compare screen and the share text.
  - Reclassifying existing records, or recovering the cause of the six saved on 2026-10-19.

## Acceptance Criteria

- `migrates_v9_to_v10_with_a_null_cause`: a v9 database migrates to v10 with the column present and null on every row, tombstones included.
- `a_failed_capture_keeps_its_cause`: saving after a classification failed with `photographTooCoarse` stores `photographTooCoarse`, and saving after a success stores null.
- `an_unknown_cause_reads_as_null`: a stored name that is not a `ClassificationFailureCause` maps to a record with a null cause.
- `a_tombstone_erases_the_cause`: deleting a record with a cause leaves the column null.
- `the_details_name_the_cause`: an unclassified record with `sheetCropped` shows "Folha cortada no quadro · tire outra foto" in the header and in the tips' empty state; one with no cause shows today's text.
- The existing database, repository, capture and details tests pass.

## Reproducibility

```sh
dart run build_runner build --delete-conflicting-outputs
flutter test test/database test/data test/features/capture test/features/details
flutter analyze && flutter test && mf check
```

Flutter 3.44.1, Dart 3.12.1, `mf` v0.8.0.

## Risks and Assumptions

- Assumption: the enum's names are stable identifiers; a renamed cause would read as null on old records, which shows today's text rather than wrong advice.
- Risk: a schema bump is hard to reverse on installed devices. The column is nullable and additive, as v7 to v9 were.
- What would invalidate this spec: a record whose stored cause disagrees with the chip the capture preview showed for it.
