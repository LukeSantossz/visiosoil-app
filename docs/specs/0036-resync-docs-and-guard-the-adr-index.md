# SPEC (spec-lite): docs: resync the project documents with the implemented state and guard the ADR index

## Problem

`README.md`, `CLAUDE.md`, `ml/README.md` and `docs/architecture/ml-handoff.md`
state things about this repository that are false today — the README indexes 8
of the 14 ADRs, publishes a test count 165 short, and lists as pending four
items that have shipped — and the one criterion that was supposed to prevent
this, SPEC 0010's `readme_indexes_every_adr`, is enforced by nothing.

## Scope

- Includes:
  - `README.md` Engineering Decisions: rows for ADRs 0008, 0009, 0010, 0011,
    0012 and 0013, so the table indexes all fourteen records as
    `.standards/docs/standards/INDEX.md` requires.
  - `README.md` Done: the test count, currently "260 tests passing".
  - `README.md` Pending: remove the entries for the ML tests in CI and the iOS
    build job (both shipped, `.github/workflows/ci.yml`), and the entry for the
    label-agreement test and the `SoilTextureColors` ordering (shipped with
    #116). Narrow the model-provenance entry, since SPEC 0033 landed the
    manifest, the dataset version and the split provenance.
  - `README.md` Known Issues: correct the `SoilTextureColors.all` entry (the
    ordering is fixed and the getter derives from the single label source), the
    `home_screen.dart` entry (#120 closed, `test/features/home/home_screen_test.dart`
    exists), the iOS entry (the `build-ios` job exists), and the "six
    independent copies" count.
  - `CLAUDE.md` Known Technical Debt: drop the three entries naming closed
    issues #120, #28 and #90; correct the label-copies and
    `SoilTextureColors.all` claims; point the `spec.json` entry at SPEC 0035.
  - `ml/README.md`: label the per-class image table as target counts rather
    than present state, since `ml/data/` holds only `splits/.gitkeep`; and
    correct the two places that say the Flutter `InferenceService` reads
    `spec.json`, naming SPEC 0035 as the change that makes it true.
  - `docs/architecture/ml-handoff.md`: correct the claim that ADR 0012 already
    removed the `assets/models` entries from `.gitignore`, and the stale line
    reference for the EXIF claim, which now points inside a different function.
  - `test/standards/readme_adr_index_test.dart` — a guard asserting the README
    links every record under `docs/adr/`, so this criterion is enforced rather
    than trusted, in the same shape as the numbering guard SPEC 0013 added.
- Does NOT include:
  - Any change under `lib/`, `ml/src/`, `ml/scripts/` or `ml/tests/`, and no
    test change other than the new guard.
  - The `.gitignore` change for `assets/models/`. SPEC 0035 owns it, and doing
    it here would make the ADR 0012 correction above immediately stale again.
  - Editing any text under `docs/specs/` or `docs/adr/`. SPEC 0028's tier
    marker and SPEC 0016's missing supersession note are real findings, but
    changing an approved gate-passed record is its own decision with its own
    Gate.
  - Adding a `## Status` field to the spec template. That is a change to
    `.standards`, not to this repository.
  - `ml/README.md`'s "new training starts from `v1`" line. Whether it conflicts
    with `project.version: 2` is not decidable from the repository, because the
    two are different concepts, and correcting it would mean guessing.
  - Closing, relabelling or opening any GitHub issue.

## Acceptance Criteria

- `readme_indexes_every_adr` — the guard passes: every `NNNN-*.md` under
  `docs/adr/` is linked from `README.md`.
- `readme_adr_index_guard_fails_on_an_unlinked_adr` — the guard is proved by
  mutation, not merely observed passing against today's tree.
- `readme_pending_names_no_shipped_work` — no Pending entry names work present
  in the tree. Verified by inspection against the files each entry names, which
  is how a prose claim can be checked at all.
- `readme_known_issues_name_no_fixed_defect` — same, for Known Issues.
- `claude_md_debt_names_no_closed_issue` — `#120`, `#28` and `#90` no longer
  appear in `CLAUDE.md`.
- `ml_readme_marks_the_class_table_as_target_counts` — the table does not read
  as a description of files on disk.
- `ml_readme_does_not_claim_the_contract_is_read` — neither occurrence states
  that `InferenceService` reads `spec.json` today.
- `handoff_states_the_gitignore_entries_remain` — the handoff agrees with
  `.gitignore` and with ADR 0012's own "not yet implemented" note.
- `analyze_clean_tests_green` — `flutter analyze` reports no issues and
  `flutter test` passes.
