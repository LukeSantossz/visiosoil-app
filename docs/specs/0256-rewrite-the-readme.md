# SPEC: docs(readme): rewrite the README to the standards' model

## Problem

The README is what a visitor reads first, and on 2026-11-04 it says several things that are no longer true and departs from the README model in `.standards/docs/standards/github.md`:

- **Stale facts.**
  - "Database schema (v9)" lists columns up to v9. The schema is v12 (`AppDatabase.schemaVersion`), with `classification_failure`, `true_texture_class` and the three capture readings added since.
  - "No reviewed corpus has shipped yet, so the section reads as no coverage" appears under What It Does, Known Issues and Pending. Corpus `2026.10.31.1` is bundled with five grounded cells and `humanReview: false` (SPEC 0227, SPEC 0230, SPEC 0234), so a record composes tips today.
  - "992 Dart tests on `main` on 2026-10-15". The suite has roughly doubled since.
  - Tech Stack names `image_picker (camera)`. Capture uses the in-app guided camera on the `camera` package (SPEC 0165, ADR 0028), with `image_picker` as the system-camera fallback.
  - Project Structure lists `docs/architecture/`, which does not exist. The top level of `docs/` is `adr`, `agents`, `design`, `guides`, `plans`, `specs` and `studies` (SPEC 0253, SPEC 0254).
  - The Engineering Decisions row "Training pipeline isolated in `ml/` (TF/Keras)" describes the retired CNN path. The released classifier is the descriptor contract (ADR 0024).
  - Pending lists "Track the artifacts a training run would produce". ADR 0012 and ADR 0019 decided that experiment outputs stay untracked, so it is not pending work.
- **Departures from the model.**
  - The Engineering Decisions table restates each ADR's rationale in a "Why this approach" column. The model says the section "indexes; it never restates", because a second copy drifts.
  - Architecture carries the full schema and migration list, which belongs to `docs/agents/project.md` and the database code, not to a one-to-three-sentence topology note.
  - The badge strip has no license badge.
- **Typography the Developer asked to remove.** The text uses em dashes throughout, the title included. On 2026-11-04 the Developer asked that no em or en dash appear in any text produced for this work.

## Design Decision

### 1. Follow the model's section order

What It Does, What It Is, Tech Stack, Architecture, Engineering Decisions, Getting Started, Project Structure, Project Status, Known Issues & Limitations, Contributing, License.

- **Results is left out.** It is optional and needs defensible numbers. E0's group accuracy was measured on Petri-dish photographs, not on the A4-sheet captures the app makes, and ADR 0026 says no accuracy is stated until one is measured on them.
- **API Reference is left out.** Its condition does not hold: the app exposes no REST, CLI or library surface. The Python side-builds document their own commands in `ml/README.md` and `corpus/README.md`.

### 2. The title

The model's form separates `{Project Name}` and `{One-Line Subtitle}` with an em dash. The Developer's instruction for this work forbids the dash, so the title reads `VisioSoil: Geolocated Soil Texture Analysis`. The colon keeps the model's two parts.

### 3. Engineering Decisions becomes an index

One row per ADR, all 28, because `test/standards/readme_adr_index_test.dart` requires every record under `docs/adr/` to be linked. Columns: the ADR link, the decision in one line, and its status (Accepted, Amended, Retired or Withdrawn, with the record that changed it). No rationale and no alternatives: the ADR holds them.

### 4. Every fact is checked against the repository

- Feature claims name only what the code does today.
- Counts are taken from a run on the day of the rewrite and dated, or left out.
- Every relative link resolves (`test/standards/docs_links_resolve_test.dart`).
- The release-signing section keeps the `key.properties`, `keytool` and app-bundle commands that `test/android_signing_test.dart` reads.

### 5. Room for the cover

A cover image is a separate decision: the Developer picks one of three proposals after this README lands. This spec writes no image reference. The spec that adds the cover places it above the title.

## Alternatives Considered

- **Edit only the stale lines.** Rejected: the restated rationale in Engineering Decisions is the larger departure, and fixing it means rewriting that section anyway.
- **Keep the full schema in the README.** Rejected: it duplicates `docs/agents/project.md` and drifted from v12 to v9 there already.
- **Keep the model's dash in the title.** Rejected by the Developer's instruction.

## Scope

- Includes:
  - `README.md`, rewritten;
  - this spec.
- Does NOT include:
  - any code, asset, test or workflow change;
  - the cover image, the logo exports or any brand asset;
  - `ml/README.md`, `corpus/README.md`, `docs/README.md` or any other document;
  - the GitHub repository description, topics, avatar or social preview, which are public settings changed only with the Developer's authorization.

## Acceptance Criteria

- The sections appear in the model's order, with Results and API Reference absent.
- `README.md` contains no em dash (U+2014) and no en dash (U+2013).
- Every ADR under `docs/adr/` is linked, and no link dangles (`readme_adr_index_test.dart`).
- Every relative link resolves (`docs_links_resolve_test.dart`).
- `android_signing_test.dart` passes.
- The README states schema v12, the bundled corpus `2026.10.31.1` with `humanReview: false`, and the guided camera, and does not state that no corpus has shipped.
- `flutter test` shows no failures beyond those this machine has on `main`.
- `mf check` passes.

## Reproducibility

Flutter 3.44.1 / Dart 3.12.1 in CI. Run `flutter test test/standards test/android_signing_test.dart`, then `flutter test` and `mf check`. The dash check is `grep -nP "[\x{2013}\x{2014}]" README.md`, which must print nothing.

## Risks and Assumptions

- **A count goes stale.** Every count is dated. A reader can tell a dated count from a claim about today.
- **Assumption:** the Developer's no-dash instruction applies to this README and to the artifacts of this work, and does not ask for the existing specs, ADRs or code comments to be rewritten.
