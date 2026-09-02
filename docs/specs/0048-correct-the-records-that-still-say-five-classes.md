# SPEC: docs(ml): correct the live records that still say five classes, and assert the label list across both languages

## Problem

SPEC 0046 took the model's class list from five to four, and the live records that state the class count were not corrected with it — including `docs/agents/project.md`, which generates the instruction file every agent reads, and a doc comment in shipped Dart that derives the verdict design from a chance level that has changed.

## Design Decision

Every **live** record that states the class count or reasons from it is corrected to four. Three kinds of correction, and they are different in kind rather than in size:

- **Plain counts** — `README.md`, `ml/README.md`, `docs/agents/project.md` — say four, and name the distinction SPEC 0046 introduced: the archive holds five classes, the model emits four.
- **Arithmetic derived from the count** — the UX dossier's "chance is twenty percent" and `classification_verdict.dart`'s "With five classes, chance is 0.20" — becomes twenty-five percent. The verdict *structure* is unaffected: ADR 0011 calls its constants "labelled placeholders" and decides the two-quantity shape, not the numbers. What changes is that the conclusive bar of 0.50 is now twice chance rather than two and a half times, which is an input to calibration (#187, #193) and is recorded as such rather than acted on here.
- **A rejection whose reason no longer holds** — `soil-classification.md` rejects an ordinal loss because "Siltosa is defined by low sand and sits off that axis". With Siltosa out, the remaining four *do* track increasing clay, so the stated reason is gone. The row is corrected to say the option is reopened by the class change and still not chosen, rather than silently keeping a rejection its own argument no longer supports.

**Archived records are not touched.** ADR 0011, ADR 0016 and every spec under `docs/specs/` also say five; `spec_method.md` is explicit that the archive holds what was decided at the time, and ADR 0016 in particular *predicted* this state.

**The cross-language drift is closed rather than reworded.** `docs/agents/project.md` has carried a debt item saying nothing asserts the Dart label list against `ml/config.yaml` — the exact defect that lets one language change without the other. A standards test now reads the `classes:` block out of `ml/config.yaml` and compares it to `SoilTextureLabels.ordered`, in order. It parses the file directly rather than adding a YAML dependency, which is what the other tests under `test/standards/` already do with markdown.

Two smaller items travel with this because they are the same fact: `V1_EVALUATION_CLASSES` in `ml/tests/support.py` was a legitimate second list while the config declared five and the protocol evaluated four, and SPEC 0046 made it an unasserted duplicate of `cfg["classes"]` — so the tests read the configured list, as production does. And SPEC 0046's criterion `config_declares_four_classes_without_siltosa` has no test named after it, which SPEC 0043's audit reports; it gets one.

## Alternatives Considered

- **Leave the documents and let readers infer the count from the code.** Rejected. `docs/agents/project.md` is the source `mf agents sync` generates `CLAUDE.md` and `AGENTS.md` from, so a false count there is read by every agent before it reads any code, and it is the kind of error that produces confidently wrong work.
- **Correct the ADRs and specs too, so nothing in the repository says five.** Rejected, and it would be a standards violation: `spec_method.md` requires a superseded record to be marked in place rather than rewritten, because the archive's value is holding what was decided at the time.
- **Recalibrate the verdict thresholds now that chance has moved.** Rejected as out of scope and not this change's to make. ADR 0011 records the constants as placeholders to be set by calibration, and #187 and #193 own that. Changing them here would be a product decision taken inside a documentation correction.
- **Reword the cross-language debt item to say "four-class" and leave it open.** Rejected. The item describes a missing assertion, and the assertion is a dozen lines. Rewording a debt item so it stays accurate while staying open is the cheapest possible non-fix.
- **Add the `yaml` package and parse `ml/config.yaml` properly in Dart.** Rejected. A dependency added to a Flutter app for one test in `test/standards/` is a production-tree cost for a test-tree benefit, and `durable_numbering_test.dart` and `readme_adr_index_test.dart` already establish reading a repository file by pattern.
- **Assert the Dart list against the Python constant instead of the config.** Rejected. `ml/config.yaml` is what the training reads and what the exported model's output order comes from; a test tying Dart to a test fixture would assert agreement between two copies while neither is the source.

## Scope

- Includes:
  - `docs/agents/project.md` — the class count, and the two debt entries about the label list; then `mf agents sync` regenerates `CLAUDE.md` and `AGENTS.md`.
  - `README.md`, `ml/README.md` — the class count and the Siltosa paragraph, whose stated blocker is now resolved.
  - `docs/design/ux-2026/03-problems.md`, `08-results-and-uncertainty.md` — chance and the worked cases.
  - `docs/architecture/soil-classification.md` — the task-formulation table's ordinal-loss row and the five-way row.
  - `lib/models/classification_verdict.dart` — the doc comment's chance figure.
  - `test/standards/class_list_test.dart` (new) — the cross-language assertion.
  - `ml/tests/support.py`, `ml/tests/test_folds.py` — drop `V1_EVALUATION_CLASSES` for the configured list.
  - `ml/tests/test_config.py` — the missing test for SPEC 0046's criterion.
  - `ml/src/model.py` — remove an unused `tensorflow` import. No criterion is written for it: asserting that one module has no unused import is not worth a test, and asserting it repository-wide is a linting decision nobody has taken. It is a one-line removal, verified by the suite still passing.
- Does NOT include:
  - Any ADR or spec under `docs/specs/`. They are archive.
  - Changing any verdict threshold, or any behaviour at all. No production code path changes; the only `lib/` edit is a comment.
  - The roadmap identifier reconciliation in `ml-implementation-map.md`, which is its own change.
  - Reading the label list from `spec.json`, which is the map's A4.

## Acceptance Criteria

- dart_label_list_matches_the_configured_classes: `SoilTextureLabels.ordered` equals the `classes:` list in `ml/config.yaml`, in order, asserted by a test that reads the file.
- the_class_list_test_is_not_vacuous: the same test fails if the parser stops finding classes in `ml/config.yaml`, so an unreadable file cannot pass as agreement.
- config_declares_four_classes_without_siltosa: `load_config()["classes"]` is exactly Arenosa, Media, Muito Argilosa, Argilosa, in that order.
- tests_read_the_configured_class_list: no test module declares its own copy of the model's four classes; the fold tests take them from the config, as production does.
- no_live_record_states_five_model_classes: no file outside `docs/adr/` and `docs/specs/` claims the model emits five classes.
- chance_is_stated_as_one_in_four: every live record deriving a chance level from the class count says twenty-five percent, not twenty.

## Reproducibility

```sh
cd ml && python -m pytest tests/ -q
```

```sh
flutter analyze && flutter test test/standards/ test/models/
mf check && mf agents sync --check
```

No seed, no dataset, no randomness: every criterion is over file contents and a configured list.

**How each criterion is checked, since they are not all checked the same way.** `config_declares_four_classes_without_siltosa` and `tests_read_the_configured_class_list` run under `ml/tests/`. `dart_label_list_matches_the_configured_classes` and `the_class_list_test_is_not_vacuous` run under `test/standards/`, which SPEC 0043's audit does not scan — so it reports them as uncovered, correctly, and that is the audit working rather than a gap. `no_live_record_states_five_model_classes` and `chance_is_stated_as_one_in_four` are verified by the greps recorded in the pull request and by nothing else: a repository-wide prose guard is the sweep SPEC 0043's Scope excludes, and it would fire on every archived record by design.

## Risks and Assumptions

- **Assumption: `ml/config.yaml`'s `classes:` block stays a flat list of quoted scalars.** The Dart test parses it by pattern. If the block gains an anchor, a merge key or a nested form, the parser stops matching — and the anti-vacuity criterion fails rather than the agreement silently passing, which is the failure mode that matters.
- **Assumption: the archive's own five-class statements are not misleading in place.** They sit in records that carry their own date and decision, and ADR 0016 is the one that decided the four. A reader who arrives at ADR 0011 and reads "chance is 0.20" is reading a 2026-08 decision correctly.
- **Risk: the corrected chance figure invites a threshold change nobody has decided.** Stated in both the record and the code comment as an input to calibration rather than as a reason to move a constant, and the constants stay exactly as ADR 0011 left them.
- **What would invalidate this spec:** ADR 0016 being superseded so that Siltosa returns to the model, which would move the count back and reopen the ordinal-loss row on its original argument.
