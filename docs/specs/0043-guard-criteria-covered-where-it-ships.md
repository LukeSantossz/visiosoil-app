# SPEC: test(ml): guard against an acceptance criterion whose only test is skipped in CI

## Problem

An acceptance criterion can hold a passing test that never runs in the configuration the project ships, and nothing says so: `folds_are_stratified_and_group_aware` was verified only against the git-ignored dataset, so it skipped in every CI run, and the fold-balance defect it existed to prevent reached `main`'s branch and was caught by a different test.

## Design Decision

A test parses the acceptance-criterion names out of the specs under `docs/specs/`, matches each to the test functions named after it in `ml/tests/`, and fails when **every** matching test is gated on the dataset being present. The gate reads the criterion names from the specs rather than from a list maintained beside it, because the spec is already this project's source of truth for what a change must satisfy, and a second list would drift from it exactly as the README's ADR index drifted before SPEC 0036 made it a test.

Dataset gating is recognised by naming the three helpers that produce it — `real_manifest_or_skip`, `real_folds` and the `real_only` marker — and a companion assertion fails if any other skip in `ml/tests/` gives a reason mentioning the dataset, so a fourth helper cannot appear and be silently unaudited. That is the same shape as the pin-parser guard added in `3a7622b`: a check that reads a list has to prove the list is the real one, or it can pass while checking nothing.

**TensorFlow skips are deliberately not audited.** They are the reverse case: absent locally, present in CI, so a TensorFlow-gated test does run where the project ships. The failure this spec addresses is specific to gating on something CI never has, which today is the dataset and nothing else.

## Alternatives Considered

- **A registry pairing each dataset-gated test with a synthetic companion**, asserted to exist and to be ungated. Rejected: it states the pairing rather than the property, so a companion that drifts to testing something else still satisfies it, and it adds a second list to maintain beside the specs — the drift this project has already been bitten by.
- **Collect the suite dynamically, run it with the dataset hidden, and read which criterion tests skipped.** Rejected: it is the most faithful measurement and the most expensive, running pytest inside pytest, and it reports on the machine it runs on rather than on CI. The static reading answers the same question at a fraction of the cost, and its blind spot — a gating mechanism nobody named — is closed by the companion assertion above.
- **Fail on any skipped test in CI, with no notion of criteria.** Rejected: it would fail the nine dataset tests that are *correctly* skipped per ADR 0019, which are facts about the real archive that no synthetic fixture can carry. The rule is not "nothing skips"; it is "no criterion is left with only skips".
- **Extend the audit to the Dart suite in the same change.** Rejected for scope, not for merit: `test/standards/` already parses documents this way and SPEC 0030's criteria live in Dart, so the same hole may exist there. It is recorded here as the next question rather than answered badly in passing.
- **Do nothing and rely on review.** Rejected: R1 read this repository's criteria three times over and missed the gap twice, for a reason it recorded — a criterion-to-test walk never asks whether the test runs. A discipline that has demonstrably failed is not a control.

## Scope

- Includes:
  - `ml/tests/test_criteria_coverage.py` — the audit and its own guard tests.
  - `ml/tests/support.py` — only if a helper must be exported for the audit to name it.
  - `docs/architecture/ml-implementation-map.md` — a line recording that the audit exists, so a later reader knows the property is enforced rather than assumed.
- Does NOT include:
  - Changing which tests skip, or adding companions for criteria the audit reports. The audit's first run may fail; fixing what it names is the work it authorises, not the work it does.
  - The Dart suite under `test/`.
  - TensorFlow-gated tests.
  - Any change under `lib/` or `ml/src/`.
  - Enforcing that every criterion has a test at all — a criterion with no test is a different defect, and the specs are not yet uniform enough to assert it without a sweep this spec does not fund.

## Acceptance Criteria

- criteria_are_read_from_the_spec_archive: the audit collects criterion names from the `## Acceptance Criteria` section of every file in `docs/specs/`, asserted against a fixture spec written to a temporary directory, so the parser is tested rather than trusted.
- a_criterion_tested_only_behind_the_dataset_gate_fails: given a criterion whose sole matching test calls `real_folds`, the audit fails, naming the criterion and the test.
- a_criterion_with_one_ungated_test_passes: the same criterion with a second, ungated test passes.
- an_unknown_dataset_skip_reason_fails: a test in `ml/tests/` that skips with a reason naming the dataset while using none of the three known helpers fails the companion assertion, naming the file, so a new gating mechanism cannot go unaudited.
- tensorflow_gating_alone_does_not_fail: a criterion whose only test carries `requires_tensorflow` passes, since CI installs TensorFlow.
- a_criterion_with_no_matching_test_is_reported_not_failed: the audit prints such criteria and does not fail on them, which keeps this change from silently becoming the sweep its Scope excludes.
- the_audit_reports_every_offender_at_once: two offending criteria produce one failure naming both, matching how `manifest.py` and `ingest.py` report.
- the_audit_runs_without_the_dataset_and_without_tensorflow: the audit itself imports neither, so it is never the thing that skips.
- existing_ml_tests_pass: the tests under `ml/tests/` pass, with any change to an existing test recorded and justified.
- analyze_clean_tests_green: `flutter analyze` reports no issues, `flutter test` passes, and `cd ml && python -m pytest tests/ -v` passes.

## Reproducibility

- Python 3.12 with the pins in `ml/requirements.txt`; the audit itself needs only the standard library and pytest, so it also runs on the interpreter this repository is developed on.
- Verify: `cd ml && python -m pytest tests/test_criteria_coverage.py -v`, then the whole suite.
- Every criterion above is exercised against fixture specs and fixture test modules in temporary directories. The audit's verdict on this repository's real specs is reported by the suite, not asserted by these tests: a criterion legitimately added tomorrow must not fail a test written today.

## Risks and Assumptions

- **Assumes tests are named after the criteria they satisfy**, which is this repository's convention and is stated in `github.md`'s PR checklist but enforced nowhere. Where the convention is not followed, the audit sees a criterion with no matching test and reports rather than fails, so the cost of a miss is a quiet gap rather than a false alarm. That is the deliberate direction of the error, and it is also the audit's main limitation.
- **Assumes the dataset is the only thing CI never has.** If a second such resource appears — a network fixture, a device — the audit is blind to it until its helper is named. The companion assertion catches the case where the skip reason mentions the dataset, not the general case.
- **The audit's first run against the real specs may fail**, and that is the intended outcome if a criterion is genuinely uncovered. What it names is fixed under a separate change, per Scope.
- **Invalidated if** the specs stop carrying acceptance criteria in the shape `spec_method.md` fixes, or if `ml/data/datasets/` ever becomes tracked, which would make the dataset gate disappear and this audit moot for its founding case.
