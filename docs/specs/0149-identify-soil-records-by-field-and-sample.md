# SPEC: feat(records): identify Soil Records by field and sample

## Problem

A Soil Record holds a photograph, a timestamp, coordinates, an address and a
classification. The agronomist cannot name it. History cards show only the
photograph and the date, and history search matches only the address (#360).
Samples from one site share an address, or have none when the lookup failed.
They can be told apart only by opening each one, and a record with no address
cannot be found by search at all.

## Design Decision

**Schema v9 adds two nullable columns to `soil_records`:**

- `field_name` (TEXT): the field or plot the sample came from, in the
  agronomist's own words ("talhão").
- `sample_label` (TEXT): a short identifier for the sample ("amostra").

**Null means "not given".** Every record saved before v9 has neither label.
Neither has any record the agronomist has not labelled.

**The migration is `if (from < 9)`, adding both columns.** No earlier step
recreates `soil_records`, so every upgrade path adds them exactly once.
Existing rows, tombstones included, arrive with NULL. That keeps SPEC 0093's
erased tombstones erased with no v9 scrub.

**Labels are given after saving, from details.** Capture is unchanged.

- The "Identificação" tile comes first in the details info section. It reads
  "Talhão: X" and "Amostra: Y", one line each, showing only the labels the
  record has.
- With neither label, the tile reads "Sem identificação".
- The tile's "Editar" button opens a dialog with two text fields, "Talhão" and
  "Amostra", filled with the current labels. Each field is limited to 60
  characters.
- "Salvar" writes both fields and closes the dialog. "Cancelar" closes it and
  writes nothing.
- Details then re-read the record, and history follows its stream.
- If the write fails, a SnackBar reads "Não foi possível salvar a
  identificação." and the record keeps the labels it had.

**One repository write, `updateLabels`.**
`SoilRecordRepository.updateLabels(int id, {String? fieldName, String? sampleLabel})`
writes both labels in one transaction.

- Each label is trimmed. One that is empty after trimming is stored as null,
  so clearing a field removes its label. Neither "" nor whitespace is ever
  stored as a label.
- It sets `updated_at` and enqueues an `upsert`, as `create` does. A label is
  record content, and the last-write-wins sync this outbox feeds must carry
  the edit.
- A missing id, or a tombstoned record, writes nothing and enqueues nothing,
  as `deleteById` treats a missing id.

**Everything else that writes a record carries the labels.**

- **`DriftSoilRecordRepository._tombstone`** erases both on delete. They are
  the record's content, and a tombstone keeps only what sync reads
  (SPEC 0093).
- **`SyncLocalStore.insertFromRemote` and `applyRemote`** write both, as they
  write the address.

**History shows the labels on the card.** A labelled card shows them above the
date, joined as "X · Y", on one line ending in an ellipsis. A card with only
one label shows that one. The card's spoken label names them after the date.
An unlabelled card looks as it does today, with the date alone. That is the
fallback, because a card has no room for a placeholder line and the date
already identifies it.

**History search matches either label.** The search term matches when the
address, the field name or the sample label contains it. The match stays
case-insensitive and literal, with the same trimming and `%` and `_` escaping
as today. So a record with no address is found by its labels. The search hint
reads "Buscar por endereço, talhão ou amostra...".

## Alternatives Considered

- **Ask for the labels at capture.** Deferred. #360 asks to add or edit them on
  a saved record, and a capture-time field adds a step to every capture.
  Editing from details covers both a forgotten label and a typo.
- **A single free-text "identification" field.** Rejected. #360 names two
  labels, and a field shared by many samples is what lets one search find
  them all.
- **Store "" for a cleared label.** Rejected. Null already means "not given".
  A second empty value would need every reader to treat both alike.
- **Put the labels in the share caption.** Deferred. #360 asks for history and
  details. The caption names a record's place only when the user opts in
  (SPEC 0005), and labels such as a farm's field name raise the same
  question.

## Scope

- Includes:
  - `soil_records_table.dart`: both columns. `app_database.dart`:
    `schemaVersion` 9 and the v9 step. The generated Drift code is regenerated.
  - `SoilRecord`: the fields, constructor, `copyWith`, plus `hasLabels` and
    `labelsSummary` (the "X · Y" join). Also `soil_record_mapper.dart`.
  - `SoilRecordRepository.updateLabels` and its Drift implementation,
    `DriftSoilRecordRepository._tombstone`, and `SyncLocalStore.insertFromRemote`
    and `applyRemote`.
  - `watchFiltered`'s search condition.
  - `InfoSection`'s identification tile with its edit callback, the label
    dialog, and `DetailsScreen` wiring the dialog to `updateLabels` and
    re-reading the record.
  - The history card's label line and spoken label, and the search hint.
  - The tests below. `migration_v8_test.dart` moves its schema-version
    assertion into `migration_v9_test.dart`, as each migration step has done.
  - `docs/agents/project.md` (with `CLAUDE.md` regenerated): schema v9, the
    columns and the migration line.
- Does NOT include:
  - Labels at capture, in the share caption, on the home screen or in any
    filter other than the search term.
  - A list of known fields to pick from, or grouping history by field.
  - Editing any other part of a record.
  - Any change to the sync payload's transport. No backend exists.

## Acceptance Criteria

- `schema_version_is_nine`.
- `migration_v8_to_v9_adds_the_columns_as_null`:
  - a v8 database, seeded by hand with a live record and a tombstone, opens at
    v9;
  - both rows hold `field_name` and `sample_label` as NULL;
  - every other column keeps its value.
- `updating_labels_stores_them_trimmed`: "  Talhão 3 " and " A1" read back as
  "Talhão 3" and "A1".
- `a_blank_label_is_stored_as_none`: "" and "   " read back as null, which
  also clears a label set before.
- `updating_labels_marks_the_record_for_sync`: `updated_at` moves to the
  clock's time, and one `upsert` is enqueued for the record's uuid.
- `updating_a_missing_or_deleted_record_writes_nothing`: no row changes and
  nothing is enqueued.
- `a_deleted_record_erases_its_labels`: `expectErased` covers both columns.
- `a_pulled_record_writes_its_labels`: `insertFromRemote` and `applyRemote`
  store them.
- `search_matches_a_label`:
  - a term found only in the field name finds the record;
  - so does a term found only in the sample label;
  - both cases include a record with no address;
  - the match ignores case;
  - a term found in none of the three finds nothing.
- `details_show_the_labels`: "Talhão: Talhão 3" and "Amostra: A1". With
  one label, only its line shows.
- `details_show_no_identification`: "Sem identificação" for a record with
  neither label.
- `editing_labels_saves_them`:
  - tapping "Editar" opens the dialog filled with the current labels;
  - "Salvar" calls `updateLabels` with the fields' text, and details show the
    new labels;
  - "Cancelar" calls nothing;
  - a failed write shows the SnackBar.
- `the_history_card_shows_the_labels`:
  - a labelled card shows "Talhão 3 · A1" and names it in its spoken label;
  - a card with one label shows that label alone;
  - an unlabelled card shows no label line.

## Reproducibility

```sh
dart run build_runner build --delete-conflicting-outputs
flutter test test/core/database test/repositories test/features/details test/features/history
flutter analyze && flutter test && mf check
```

## Risks and Assumptions

- **Assumption: "case-insensitive" means what the address search already
  means.** SQLite's `lower()` folds ASCII letters only, so "TALHÃO" does not
  match "talhão" on the "Ã". The address search has the same limit today, and
  changing that is its own question.
- **Risk: two devices editing the same record's labels before sync.**
  Last-write-wins keeps the later `updated_at`, as for any record content.
  No backend exists yet, so nothing reaches it today.
