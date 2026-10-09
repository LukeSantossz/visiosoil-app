# SPEC: feat(location): retain GPS accuracy with each Soil Record

## Problem

The device reports a horizontal accuracy, in metres, with every GPS reading.
The capture flow keeps only latitude, longitude and the reverse-geocoded
address, so the accuracy is discarded and never reaches the record (#363).
Record details then show six decimal places for every point, which reads as
centimetre precision whether the fix was good to 4 m or to 400 m. An
agronomist cannot tell a usable point from a poor one. A record saved without
the accuracy loses it for good.

## Design Decision

**Schema v8 adds one nullable column to `soil_records`:**
`horizontal_accuracy` (REAL), the radius in metres the device reported for the
fix.

**Null means "not known".** A record saved before v8 has none. Neither has a
record saved without a location, nor one whose device reported no usable
accuracy. A made-up value would claim a quality the fix never had, the same
reason the SPEC 0097 columns are nullable.

**The migration is `if (from < 8)`, adding the column.** No earlier step
recreates `soil_records`, so every upgrade path adds it exactly once. Existing
rows, tombstones included, arrive with NULL, so SPEC 0093's erased tombstones
stay erased with no v8 scrub. The v6 step's raw `UPDATE` does not name the new
column, because on an upgrade from v5 it runs before the column exists.

**Where the value comes from.**

- `LocationService.horizontalAccuracyOf(Position)` returns the reading's
  accuracy, or null when it is not finite or not positive. Android reports
  `0` when the fix carries no accuracy, and iOS reports a negative value when
  the accuracy is invalid. Neither is a measurement.
- `LocationReading` gains `accuracy` (`double?`). The default locator fills it
  from that helper.
- `CaptureUiState` gains `horizontalAccuracy`. It is set with the coordinates
  and cleared with them when a new capture starts.
- The capture save passes it to `SoilRecord`, which gains
  `horizontalAccuracy` (`double?`).
- The repository writes it on create, and `soilRecordFromRow` reads it.

**Everything that writes a record carries it.**

- **`DriftSoilRecordRepository._tombstone`** erases it on delete. It describes
  where the user collected, and a tombstone keeps only what sync reads
  (SPEC 0093).
- **`SyncLocalStore.insertFromRemote` and `applyRemote`** write it, as they
  write the coordinates.

**Details show it under the coordinates.** The "Localização" tile's subtitle
keeps the coordinates and adds a second line:

- "Precisão estimada: ± N m" when the accuracy is known. N is the accuracy
  rounded up to whole metres, so the shown radius never claims more precision
  than the device reported.
- "Precisão não disponível" when the record has coordinates and no accuracy.
  This is how an existing record reads, with no fabricated value.

A record without coordinates shows no accuracy line, as it shows no
coordinates. The wording says "estimada" because a phone's figure is the
device's own estimate, not a survey-grade measurement (#363).

**Shared output carries it only beside the coordinates.** When the user opts
into sharing the location, the caption adds "Precisão estimada: ± N m" after
the coordinates if the accuracy is known. An unknown accuracy is omitted, as
the caption omits every missing field. The share card draws the caption, so it
follows.

## Alternatives Considered

- **Treat `0` as a perfect fix.** Rejected. Android reports `0` for a fix with
  no accuracy, so storing it would claim a zero-metre radius the device never
  measured.
- **Show the accuracy on the capture screen as well.** Deferred. The capture
  preview shows coordinates only in place of an address the lookup could not
  find, before anything is saved. #363 asks for details and shared output.
- **Store the GPS fix time too.** Deferred. #363 mentions it under Current
  State, but its acceptance criteria ask only for the accuracy. A fix time is
  its own column and its own question about the record's timestamp.
- **Round to the nearest metre.** Rejected. Rounding 4.4 m down to 4 m shows a
  tighter radius than the device reported. Rounding up never does.

## Scope

- Includes:
  - `soil_records_table.dart`: the column. `app_database.dart`:
    `schemaVersion` 8 and the v8 step. The generated Drift code is regenerated.
  - `SoilRecord` (field, constructor, `copyWith` and a
    `formattedHorizontalAccuracy` getter), `Formatters.horizontalAccuracy`,
    `soil_record_mapper.dart`, `DriftSoilRecordRepository.create` and
    `_tombstone`, and `SyncLocalStore.insertFromRemote` and `applyRemote`.
  - `LocationService.horizontalAccuracyOf`, `LocationReading.accuracy`, the
    default locator, `CaptureUiState.horizontalAccuracy` and
    `CaptureScreen._saveRecord`.
  - `InfoSection`'s location subtitle and `ShareContentBuilder.caption`.
  - The tests below. The existing `LocationReading` literals in the capture
    tests gain `accuracy`, because a record literal names every field.
    `migration_v7_test.dart` moves its schema-version assertion into
    `migration_v8_test.dart`, as each migration step has done.
  - `docs/agents/project.md` (with `CLAUDE.md` regenerated): schema v8, the
    column and the migration line.
- Does NOT include:
  - The GPS fix time, altitude or any other `Position` field.
  - Showing the accuracy on the capture screen, in history or on the map.
  - Refusing or warning about a poor fix. Any threshold is a field-protocol
    decision this spec does not make.
  - Any change to the sync payload's transport. No backend exists.

## Acceptance Criteria

- `schema_version_is_eight`.
- `migration_v7_to_v8_adds_the_column_as_null`:
  - a v7 database, seeded by hand with a live record and a tombstone, opens at
    v8;
  - both rows hold `horizontal_accuracy` as NULL;
  - every other column keeps its value.
- `a_located_record_keeps_its_accuracy`: a record created with an accuracy
  reads back with the same value.
- `a_record_without_accuracy_keeps_none`: it reads back as null.
- `a_deleted_record_erases_its_accuracy`: `expectErased` covers the column.
- `a_pulled_record_writes_its_accuracy`: `insertFromRemote` and `applyRemote`
  store it.
- `an_unusable_accuracy_reads_as_none`: `horizontalAccuracyOf` returns null
  for `0`, a negative value, NaN and infinity, and the value itself for a
  positive one.
- `saving_a_located_capture_persists_the_accuracy`: the capture screen hands
  the repository the reading's accuracy. A reading without one saves null.
- `a_new_capture_clears_the_accuracy`: `startingCapture` resets it with the
  coordinates.
- `details_show_known_accuracy`: "Precisão estimada: ± 5 m" for 4.2 m.
- `details_show_unavailable_accuracy`: "Precisão não disponível" for a record
  with coordinates and no accuracy, and no accuracy line for a record without
  coordinates.
- `the_caption_names_known_accuracy_with_the_location`: the line follows the
  coordinates when the location is included and the accuracy is known. It is
  absent when the location is not included, and when the accuracy is unknown.

## Reproducibility

```sh
dart run build_runner build --delete-conflicting-outputs
flutter test test/core/database test/repositories test/utils/location_service_test.dart test/features/capture test/features/details test/services/share_content_builder_test.dart
flutter analyze && flutter test && mf check
```

## Risks and Assumptions

- **Assumption: the plugin reports accuracy as a 68% radius in metres.** That
  is what Android's `Location.getAccuracy` and iOS's `horizontalAccuracy`
  document, and `geolocator` passes it through unchanged. The app shows it as
  the device's estimate and makes no stronger claim.
- **Risk: an old record reads "Precisão não disponível" next to a point that
  was in fact good.** That is accurate: the app never kept the figure, so it
  cannot know. Showing nothing would read as if the question did not apply.
