# SPEC: fix(capture): save every confirmed capture and keep its labels

## Problem

The Developer ran a field session on 2026-10-27. Three samples of each class were photographed, and each one's true class was typed into the result's "Corrigir" dialog. Two defects lost data in that session.

- **A capture is saved only when the bookmark is tapped.**
  - Capture shows the result as a draft (SPEC 0196, SPEC 0202), and only the outlined bookmark writes it.
  - Leaving the screen, by the back button or a system back, deletes the photograph (SPEC 0146).
  - So a photograph that was taken and classified is lost unless one more tap is made.
- **The draft's labels are never written.**
  - `DriftSoilRecordRepository.create` inserts the row without `field_name` and `sample_label`.
  - It returns the record it was given, so the caller sees the labels it passed and nothing reports the loss.
  - Every label typed on a draft through "Corrigir" was dropped on save. Labels edited later from details are written, through `updateLabels`.
  - The capture test that covers the draft's labels reads `FakeSoilRecordRepository.createCalls`, which records the argument and not the row, so it passed.

## Design Decision

**The record is created when the camera returns the photograph**, as the Developer chose on 2026-10-27. What arrives later is written into that record.

- **On the photograph's arrival** — from the camera or recovered after a restart (SPEC 0096) — capture calls `create` with:
  - the photograph;
  - the time;
  - `AppStrings.addressUnavailable` as the address;
  - no class.
  - The processing view shows while it is written.
- **Picked file.**
  - Once the row exists, the picker's file is deleted (SPEC 0094) and the durable copy is classified.
  - The copy's pixels and orientation are the picked file's (ADR 0005), so the classification is the same.
  - The gallery copy (SPEC 0208) is taken from the durable copy, as before.
- **Two new repository writes.** Each follows `updateLabels`: one transaction, `sync_status` back to `pending`, `updated_at` bumped and an `upsert` enqueued.
  - `updateClassification` writes:
    - the class, the confidence, the distribution and both versions;
    - or, when nothing was classified, the failure cause (SPEC 0173).
  - `updateLocation` writes the coordinates, the accuracy and the address.
    - It is called only when a reading arrives. Otherwise the record keeps the unavailable address it was created with, as a save without a fix did.
- **The writes do not depend on the screen.**
  - The repository and the provider container are read before the first await.
  - The classification and the location are written even if the screen has been left.
  - After a write, the container invalidates the record's `soilRecordByIdProvider` so that details shows the new value.
- **Where the result is shown.** When the classification is written, ok or failed, capture:
  - lets the triangle settle as today;
  - reads the record through `soilRecordByIdProvider`, so details opens with it loaded;
  - marks it in `justSavedRecordProvider` and shows "Salvo no histórico" (SPEC 0218);
  - replaces itself with `/details` (SPEC 0132), with no page transition, so the result takes the processing view's place as the draft did.
- **The bookmark.**
  - Details already shows a saved record's filled bookmark, which removes the record (SPEC 0197).
  - The draft's outlined bookmark is removed along with the draft result.
  - Saving is now automatic, and the bookmark's only action is removal.
- **Leaving while processing.**
  - The processing view's back button reads "Voltar" and pops.
  - Nothing is discarded, since the record exists, and the classification still completes and is written.
- **`create` writes the labels it is given.** `create` inserts `field_name` and `sample_label`, trimmed and empty as null, as `updateLabels` stores them.
- **A failed create.**
  - Capture keeps the photograph and says that the record could not be saved.
  - It shows the photograph with the existing "Salvar registro", "Tirar outra foto" and "Descartar" actions.
  - "Salvar registro" retries the same create.
- **A failed result write.** When writing the classification into the created record throws while capture is shown, capture asks before going on.
  - The dialog "Não foi possível salvar o resultado" says the photograph is in the history, and that without the result it stays unclassified.
  - "Tentar de novo" writes the same classification again.
  - "Continuar sem resultado" opens `/details` for the record as it is, without settling the triangle on a class the record does not hold.
  - A barrier tap does not dismiss it, so the choice is always made.
- **Removed from capture:**
  - the draft result and the failed draft result;
  - the draft's labels and its "Corrigir";
  - the bookmark that saved.
- **The true class is out of scope.** Recording it in its own field, and removing the Talhão label, is SPEC 0220. Until then "Corrigir" on details writes the labels as it does today.

## Alternatives Considered

- **Save on leaving, keeping the draft.** Rejected by the Developer. A process killed while the draft is shown loses the photograph, and every way out of capture would have to save.
- **Save only once classified.** Rejected. Leaving during classification would still lose the photograph.
- **Keep showing the result inside capture, read from the saved record.** Rejected. Capture would hold a second copy of details' behaviour: its bookmark, its "Corrigir" and its delete. Details already shows a saved record.
- **Wait for the location before showing the result.** Rejected. The location can take 20 s to time out, and a record already exists to receive it.

## Scope

- Includes:
  - `create` writing the labels;
  - `updateClassification` and `updateLocation` in the repository and its fake;
  - capture saving at the photograph's arrival and handing the result to details;
  - the `/details` route opening without a transition when capture hands over;
  - their tests.
- Does NOT include:
  - the true-class field, the Talhão label's removal, schema v11 and the delay when "Corrigir" opens (SPEC 0220);
  - the triangle's animation (SPEC 0221);
  - a record left without a class or a cause by a process killed while classifying.

## Acceptance Criteria

- `create_persists_the_labels`: against an in-memory Drift database, `create` with a field name `' Talhão 3 '` and a sample label `''`:
  - stores `Talhão 3` and null;
  - `getById` returns them.
- `update_classification_writes_the_result`: against Drift, `updateClassification` on a record:
  - writes the class, the confidence, the distribution and both versions;
  - leaves the cause null;
  - sets `sync_status` to `pending` and bumps `updated_at`;
  - enqueues one `upsert`.
- `update_classification_writes_the_cause`: with a cause and no class, it writes the cause and leaves the class null.
- `update_location_writes_the_reading`: against Drift, `updateLocation` writes the coordinates, the accuracy and the address, and enqueues one `upsert`.
- `updates_skip_a_tombstone`: neither update changes a deleted record.
- `capture_saves_when_the_photograph_arrives`: when the camera returns a photograph, one record is created before the classification ends, with the photograph and no class.
- `capture_writes_the_classification_and_opens_details`: a classification that succeeds:
  - is written to the created record;
  - opens `/details` for that record;
  - shows "Salvo no histórico".
- `capture_writes_a_failed_classification`: a classification that fails writes its cause to the record and opens `/details`.
- `failed_result_write_offers_a_retry`: when `updateClassification` throws, capture:
  - shows "Não foi possível salvar o resultado" and neither opens `/details` nor shows "Salvo no histórico";
  - writes the class when "Tentar de novo" is tapped and the write then succeeds, and opens `/details`.
- `declined_result_write_opens_the_record`: "Continuar sem resultado" opens `/details` for the record without a class, after one write attempt.
- `leaving_while_classifying_keeps_the_record`: popping capture while classifying:
  - deletes no record;
  - still writes the classification when it ends.
- `capture_writes_the_location`: a location reading that arrives after the classification is written to the record.
- `failed_create_keeps_the_photograph`: when `create` throws, capture:
  - shows the error;
  - keeps the photograph with "Salvar registro";
  - creates the record when it is tapped.
- Existing tests pass. Those that read the draft result are replaced by the criteria above.

## Reproducibility

Flutter 3.44.1, Dart 3.12.1. Run `flutter test`, `flutter analyze` and `mf check`.

## Risks and Assumptions

- **A process killed while classifying** leaves a record with neither a class nor a cause. Details reads it as an unclassified photograph, and it can be removed there. Before this spec, the same kill lost the photograph.
- **The location can arrive after the result is shown.**
  - Details shows the unavailable address until the invalidation re-reads the record.
  - History updates on its own, through `watchAll`.
- **Every confirmed photograph is now a record.** That includes a photograph retaken because it was poor. Removing it is one tap on the filled bookmark.
- **"Tirar outra foto" after a failed classification** opens a new capture from details. The failed record stays until it is removed.
