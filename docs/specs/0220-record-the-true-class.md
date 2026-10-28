# SPEC: feat(details): record the true class in place of the field label

## Problem

In the field session of 2026-10-27 the Developer typed each sample's true class into the result's "Corrigir" dialog. The app had nowhere to put it.

- **"Corrigir" edits two free-text labels**, Talhão and Amostra (SPEC 0149, SPEC 0202). Nothing in the app records which class a sample really is.
  - A class typed into either label is text. It cannot be compared with the predicted class, filtered, or exported as a class.
  - A typo, a missing accent or a different case is a different value.
- **The Talhão label is not wanted.** The Developer asked for it to be removed for good.

## Design Decision

**A record gets a true class, chosen from the model's four classes**, as the Developer chose on 2026-10-27. Amostra stays beside it, and Talhão leaves every screen.

- **Schema v11.** `soil_records` gets `true_texture_class`, a nullable text column holding a contract class name (`Arenosa`, `Media`, `Argilosa`, `Muito Argilosa`). Null means not given.
  - `SoilRecord.trueTextureClass` carries it, through the mapper, `create`, sync's `insertRemote` and `applyRemote`.
- **Backfill, in the v10 → v11 step.** The Developer typed classes into the labels, so a record whose label already names a class gets it.
  - A label names a class when, trimmed and compared without case, it is a class's contract name or its display label (`Média` for `Media`).
  - Either label may name it. When both name a class and the classes differ, the record gets none, since the step cannot tell which was meant.
  - Tombstones are skipped; their content was erased (SPEC 0093).
  - The labels are left as they are. The backfill only adds.
  - The step does not enqueue a sync operation. No backend exists, and the next edit of the record enqueues it whole.
- **The model's classes.** `SoilTextureReference.modelClasses` lists the four in texture order: Arenosa, Média, Argilosa, Muito argilosa.
  - `class_list_test` asserts that the list holds exactly the contract's classes, so the picker cannot drift from what the model emits.
  - Siltosa is not offered. ADR 0016 keeps it out of the model.
- **"Corrigir" opens the correction dialog.** Its title is "Corrigir classificação". It holds:
  - the four classes as a radio list, plus "Não informada", with the record's true class selected;
  - the Amostra field, below the list.
  - "Salvar" writes both and "Cancelar" writes nothing, as today.
- **The write.** `updateLabels` becomes `updateCorrection(id, {trueTextureClass, sampleLabel})`, in the same transaction pattern: `pending`, `updated_at` bumped, one `upsert` enqueued, a tombstone skipped.
  - A class outside `modelClasses` throws `ArgumentError` and writes nothing.
  - The sample label is trimmed and stored as null when empty, as before.
  - `field_name` is no longer written by an edit, and is left as stored.
- **Where it shows.**
  - Details' Identificação tile reads "Classe real: Argilosa" and "Amostra: 12", each when present, or "Sem identificação". Its "Editar" opens the same dialog.
  - Every place that showed "Talhão · Amostra" shows the Amostra alone: the overview, the Dicas header, the history grid and compare.
- **Talhão leaves the app.** No screen shows `field_name`, and history search stops matching it. The column stays, since dropping a column rewrites the table and it may still hold what was typed.
- **The prediction is untouched.** The true class never changes `texture_class`, its confidence or its distribution, and the triangle never reads it.

## Alternatives Considered

- **Keep the free-text labels and parse a class out of them on read.** Rejected. The same typo problem, and every reader would need the parser.
- **Offer all five archive classes.** Rejected by the Developer. A true class the model cannot emit is never comparable with its prediction.
- **Drop the `field_name` column.** Rejected. SQLite needs a table rewrite, and it would destroy text the backfill could not place.
- **Clear a label once the backfill reads a class from it.** Rejected. The step would destroy what was typed, and an Amostra that repeats the class costs nothing.

## Scope

- Includes:
  - schema v11, its migration and backfill;
  - the model field, its mapper and its sync mapping;
  - `updateCorrection` in the repository and its fake, replacing `updateLabels`;
  - `SoilTextureReference.modelClasses` and its contract assertion;
  - the correction dialog, the Identificação tile, and Talhão's removal from the screens and from search;
  - their tests.
- Does NOT include:
  - the delay when "Corrigir" opens on the phone. Its cause has not been measured, and a profile on the device comes first;
  - the triangle's animation (SPEC 0221);
  - filtering or exporting by the true class.

## Acceptance Criteria

- `migration_v11_adds_the_true_class`: a v10 database migrates to v11 with `true_texture_class` null on every row that names no class.
- `migration_v11_backfills_a_class_from_the_labels`: rows labelled `' argilosa '` (Talhão), `'Média'` (Amostra) and `'Muito Argilosa'` (Amostra) get `Argilosa`, `Media` and `Muito Argilosa`, and their labels are unchanged.
- `migration_v11_leaves_conflicting_labels_alone`: a row whose Talhão names `Arenosa` and whose Amostra names `Argilosa` gets no true class.
- `migration_v11_skips_tombstones`: a tombstone gets no true class.
- `update_correction_writes_the_class_and_the_sample`: against Drift, it writes both, leaves `field_name` as stored, marks `pending`, bumps `updated_at` and enqueues one `upsert`.
- `update_correction_rejects_a_class_outside_the_model`: `Siltosa` throws `ArgumentError` and the row is unchanged.
- `model_classes_match_the_contract`: `SoilTextureReference.modelClasses` holds exactly the classes of `assets/models/spec.json`.
- `correction_dialog_offers_the_model_classes`: the dialog lists the four display labels and "Não informada", has no Talhão field, and preselects the record's true class.
- `correction_dialog_writes_the_choice`: choosing Argilosa, typing an Amostra and tapping "Salvar" calls `updateCorrection` with `Argilosa` and the text; "Cancelar" calls nothing.
- `identification_shows_the_true_class`: the Identificação tile shows "Classe real: Argilosa" and "Amostra: 12", and no "Talhão".
- `history_search_ignores_the_field_label`: a search for a record's Talhão text no longer finds it.
- Existing tests pass. Those that read Talhão are updated to the criteria above.

## Reproducibility

Flutter 3.44.1, Dart 3.12.1. Run `dart run build_runner build --delete-conflicting-outputs`, `flutter test`, `flutter analyze` and `mf check`.

## Risks and Assumptions

- **A label the backfill does not recognise stays text.** A misspelt class, such as "Argiloza", is left in its label for the Developer to set from "Corrigir".
- **Labels typed on capture's draft before SPEC 0219 never reached the database**, so the backfill cannot recover them. It reads only labels written from details.
- **A hidden Talhão still syncs.** `field_name` keeps travelling in the sync mapping, so a value typed before v11 is not lost by a later sync.
