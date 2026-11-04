# SPEC: docs: translate the design of record and bring the living docs up to date

## Problem

SPEC 0253 fixed where each document sits. Four problems remain in what they say. A reviewer reading the repository end to end meets each one:

- **The design of record is in pt-BR, stale, and named like a spec.**
  - `docs/design/spec/SPEC.md`, `docs/design/spec/haptics.md` and `docs/design/README.md` are written in pt-BR. The project allows pt-BR only for UI strings and for the capture protocol's copy (`docs/agents/project.md`).
  - `SPEC.md` points at `../app-completo-v11/index.html`, which does not exist. SPEC 0253 deleted the prototype.
  - Its §0 lists five divergences "to resolve first". All five are resolved:
    - SPECs 0178, 0179, 0181 and 0182 resolved four of them. `ConfidenceLevel.highThreshold` is `0.75`, `AppHaptics` has `blocked()` and `linked()`, `AppMotion` has the five M3 curves, and `AppPalette.sun` and `AppDensity` exist.
    - The fifth asked only that the UI not show the per-class scores. It does not: the capture screen stores the distribution (SPEC 0097) and shows only the winning class.
  - Its §12 lists fifteen PRs to build. SPECs 0178 to 0200 built them, and nothing says so.
  - Later specs changed parts of it on purpose. The document still describes the earlier design:
    - the collection counts the contract's four classes (SPEC 0223);
    - no sync status, sync action or sync-only setting shows while no backend is wired (SPEC 0235, SPEC 0236, SPEC 0250);
    - the account copy no longer promises sync (SPEC 0241).
  - Its file name `SPEC.md` reads as one of `docs/specs/`. Its screen PNGs are named in pt-BR (`telas/01-boot-peneira.png`).
- **Living documents state things that are no longer true.**
  - `studies/architecture/research-agent.md` opens "pre-SPEC, not an implementation authorization. No `lib/` code … ships with this document". `CorpusResearchService` composes tips on the device today (SPECs 0068 to 0070, 0227, 0234).
  - `studies/architecture/ml-implementation-map.md`:
    - says "Last updated: 2026-09-29", but its last revision is a note dated 2026-10-05;
    - says "the current state for other terminals lives in `ml-handoff.md`", a document SPEC 0253 deleted.
  - `studies/architecture/research-agent-implementation-map.md`:
    - says "Last updated: 2026-10-15", but it records a decision of 2026-10-28;
    - says "It has no corpus to compose from yet". Corpus `2026.10.31.1` is bundled.
    - says the corpus releases "twelve substance cells". It releases five (SPEC 0230, SPEC 0234).
  - `studies/architecture/corpus-assets.md` says the three corpus assets are "build products and none is tracked". SPEC 0227 tracks all three. It also calls `corpus.json` a "reviewed corpus release", and the release says `humanReview: false`.
- **Two plans sit under `studies/`.** The two implementation maps call themselves "the ordered backlog" and "the plan, and only the plan". A study records what was found, and a backlog records what to do next. `docs/README.md` files both under `studies/architecture/`.
- **`studies/ml/` has no index.** It holds eleven documents. One is withdrawn (`collection-protocol.md`), one reports an ADR later withdrawn (`small-disc-study.md`, ADR 0027), and the rest are run verdicts. Nothing lists which is which, so a reader learns a document is withdrawn only by opening it.

The Developer approved on 2026-11-04: translate the design of record and fix what is stale, and resolve all four problems under this spec.

## Design Decision

### 1. The design of record

- **Move and rename** with `git mv`, so history follows:

  | Before | After |
  |---|---|
  | `docs/design/spec/SPEC.md` | `docs/design/v11/redesign.md` |
  | `docs/design/spec/haptics.md` | `docs/design/v11/haptics.md` |
  | `docs/design/spec/telas/NN-<pt-BR name>.png` | `docs/design/v11/screens/NN-<English name>.png` |

  Each PNG keeps its number, because specs cite the screens by number ("PNG 14"). Only the words after the number are translated, for example `01-boot-peneira.png` becomes `01-boot-sieve.png`.
- **Translate** `redesign.md`, `haptics.md` and `docs/design/README.md` into English.
  - Product copy stays pt-BR, because it is the copy the screens show, and it is quoted or in backticks so a reader can tell copy from prose. This follows the UI-string exemption.
  - Every token, number, threshold, duration, curve and API name stays as written.
  - The translation adds no requirement and removes none.
- **Correct what is stale in `redesign.md`.**
  - The header points at the screens and at the prototype's permalink at `10f4909`, not at the missing `../app-completo-v11/index.html`.
  - §0 becomes "Status". It says that SPECs 0178 to 0200 built the design and SPECs 0201 to 0218 matched the screens to the mocks.
  - It also lists the five former divergences, now resolved, each with the spec that resolved it.
  - It also lists the departures that later specs decided, each with its spec and the section it changes:
    - SPEC 0219: a capture is saved when the photograph arrives, and the bookmark's only action is removal (§3.6);
    - SPEC 0221: while classifying, the four model classes blink in turn, and there are no particles (§3.5, §6.3);
    - SPEC 0223: the collection counts the contract's classes, `N/4` today, not twelve USDA classes (§3.3, §3.7, §3.10);
    - SPEC 0235, SPEC 0236 and SPEC 0250: while no sync backend is wired, the app shows no sync status, no sync action and no sync-only setting (§3.3, §3.7, §3.10, §3.11);
    - SPEC 0241: the account copy says the analyses stay on the device (§3.2, §3.10);
    - SPEC 0243: the tips disclaimer has no fill (§3.9);
    - SPEC 0245: a record's date reads `dd/MM/yyyy · HH:mm` (§3.6, §3.8);
    - SPEC 0247: Histórico shows one total line, not three cells (§3.7);
    - capture is camera-only, so the gallery slot of §3.4 stays empty (`docs/agents/project.md`, Current Limitations).
  - §12 gains a "Delivered by" column naming the spec that built each row.
  - The rest of the text stays the approved design. Each departure is stated once, in the status, rather than edited into the section it changes. The sections keep recording what was approved on 2026-10-23 and 2026-10-24.
- `docs/README.md` names `design/v11/` and adds the three moves to its table of moved paths.

### 2. The living documents

Each correction states the current fact and cites the spec that made it true. None rewrites the history the document records.

- `research-agent.md`:
  - The status paragraph says it is the September 2026 design study, adopted by ADR 0022 and narrowed by ADR 0023, and implemented on the device (SPECs 0068 to 0070, 0227, 0234).
  - §1 and §2 are headed as the state in September 2026, which is the diagnosis the design answered.
  - The status points to `docs/agents/project.md` for the current state.
- `ml-implementation-map.md`:
  - Its opening paragraph says the reasoning and the hand-off note were deleted by SPEC 0253, with their permalinks kept.
  - Its date line reads "Last revised: 2026-10-05". A status note says the map is not maintained after that date, and that later ML work is recorded in its specs and in `docs/studies/ml/`.
- `research-agent-implementation-map.md`: its date line reads "Last revised: 2026-10-28". Its opening says:
  - corpus `2026.10.31.1` is bundled, with five grounded substance cells (SPEC 0227, SPEC 0230, SPEC 0234);
  - the corpus was published without human review, so `humanReview` is `false`.
- `corpus-assets.md`:
  - The three assets are tracked since SPEC 0227.
  - `corpus.json` is the released corpus, published without human review.

### 3. Plans get their own directory

- `docs/plans/` is a new top-level entry. Both implementation maps move into it with `git mv`.
- `docs_top_level_is_the_declared_layout` adds `plans` to its set.
- `docs/README.md` describes it, and its moved-paths table adds both maps.
- Every reference to the maps follows the move:
  - `corpus/README.md`;
  - ADRs 0014 and 0017;
  - `corpus-assets.md` and `research-agent.md`;
  - the relative links inside the maps.
- ADRs keep their decision and status. Only a path changes, as SPEC 0253 did.
- `ml/tests/test_records.py` renames `ARCHITECTURE_DIR` to `PLANS_DIR`, pointing at `docs/plans`, and `test_adoption_records.py` imports the new name. Both tests read the map exactly as before.

### 4. An index for `studies/ml/`

`docs/studies/ml/README.md` lists every document in the directory. Each row gives:

- the spec that ordered the document;
- its status, one of:
  - **Verdict**: a run's result, kept as measured;
  - **Withdrawn**: no longer applies;
  - **Superseded**: a later document or ADR replaced it;
- a one-line answer, taken from the document's own summary.

The directory stays a durable archive, and the index changes no document in it.

### Guards

- `test/standards/docs_prose_test.dart`, test `docs_prose_is_english`.
  - It scans every `.md` under `docs/`, except `docs/specs/` and any `*.pt-BR.md` copy.
  - Before checking a line, it removes fenced code, inline code, double-quoted text and link text.
  - A line fails when it still holds three or more pt-BR function words from a fixed list ("não", "para", "com", "uma", "também" and others).
  - On `main` it fails on exactly the three design documents and on nothing else.
- `test/standards/docs_index_test.dart`, test `studies_ml_index_lists_every_document`: every `.md` under `docs/studies/ml/` other than the README is linked from `docs/studies/ml/README.md`.
- `docs_top_level_is_the_declared_layout` includes `plans`.
- `every_relative_doc_link_resolves` covers every moved and new file, as it already does.

## Alternatives Considered

- **Keep the design document in pt-BR under a written exception.** Rejected by the Developer. The document is for developers, which is the audience the English rule names.
- **Edit each departure into the section it changes.** Rejected. The sections then no longer say what was approved on 2026-10-23, and the reason for each change would live in no single place. One status list keeps both.
- **Rewrite the living documents as the current state.** Rejected. They are long design records, and their history is part of what they record. A dated status that says what changed, and where it is recorded, corrects them without erasing it.
- **Put the plans under `docs/adr/` or `docs/specs/`.** Rejected. `mf` reads both directories with fixed rules, and a backlog is neither a decision nor a spec.
- **Keep the pt-BR PNG names.** Rejected. File names are identifiers, and the specs cite the screens by number, which the rename keeps.
- **Edit the specs that cite `docs/design/spec/`.** Rejected for the reason SPEC 0253 gives: specs are the durable archive. The moved-paths table serves their reader.

## Scope

- Includes:
  - the moves and renames above, with `git mv`;
  - translating `redesign.md`, `haptics.md` and `docs/design/README.md`;
  - the status section and the "Delivered by" column in `redesign.md`, and the fixed prototype pointer;
  - the status corrections in the four living documents;
  - `docs/plans/`, `docs/studies/ml/README.md`, and the `docs/README.md` updates;
  - the path updates in `corpus/README.md`, ADRs 0014 and 0017, and the ML record guards;
  - the two new standards tests and the layout-test change.
- Does NOT include:
  - editing any file under `docs/specs/` or any study's content under `docs/studies/ml/`;
  - changing any ADR's decision or status;
  - changing any design decision, token or copy;
  - `corpus/prompts/*.md`. They are pt-BR prompts that produce pt-BR product copy, not documentation;
  - any code or UI behaviour.

## Acceptance Criteria

- `docs_prose_is_english` fails on `main`, on exactly `docs/design/README.md`, `docs/design/spec/SPEC.md` and `docs/design/spec/haptics.md`, and passes after the change.
- `studies_ml_index_lists_every_document` fails on `main` and passes after the change.
- `docs_top_level_is_the_declared_layout` fails once `plans` is added to its set, and passes after the move.
- `every_relative_doc_link_resolves` passes after the change.
- No living document outside `docs/specs/` names `docs/design/spec/`, `SPEC.md`, `telas/`, `app-completo-v11` or `docs/studies/architecture/*-implementation-map.md`, except in `docs/README.md`'s moved-paths table.
- Every number, token, duration and threshold in `redesign.md` and `haptics.md` equals the one in the pt-BR text it translates.
- `flutter analyze` reports no issues, and `flutter test` shows no failures beyond the four this machine has on `main`.
- `python -m pytest` in `ml/` shows no failures beyond `test_pipeline_golden_generation_is_deterministic`, and `corpus/` passes.
- `mf check` passes.

## Reproducibility

Flutter 3.44.1 / Dart 3.12.1 in CI. Checked locally on Flutter 3.47.7, `ml/.venv` (Python 3.12) and a scratch corpus venv. Run `flutter test test/standards`, `flutter test`, `flutter analyze`, `python -m pytest` in `ml/` and in `corpus/`, and `mf check`.

The numeric check compares the multiset of numbers in each pt-BR file at `main` with its translation's, by a script in the pull request's How to Test.

## Risks and Assumptions

- **The prose guard is a heuristic.** Three or more function words from a fixed list on one line is enough to catch a pt-BR sentence and too few to catch a single quoted word. A pt-BR sentence written inside quotes passes, which is deliberate, because quoted copy is the exemption. A future English document that quotes UI copy without quotes could trip it, and the fix is to quote it.
- **Translation drift.** A translated requirement that reads differently is a design change made by accident. The numeric check and R2 read the translation against the original. Each departure in the status cites a spec, so none is new.
- **Assumption:** the Designer's ownership of the design document, which SPEC 0180 noted, does not block a faithful translation that the Developer approved.
