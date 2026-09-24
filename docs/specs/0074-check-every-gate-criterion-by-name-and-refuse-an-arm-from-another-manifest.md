# SPEC: fix(ml): check every spec 0044 criterion by name, and refuse to pool an arm scored against another manifest

## Problem

Six of SPEC 0044's acceptance criteria have no test carrying their name, so the
SPEC 0043 audit reports them as unchecked. Writing those tests shows that one of
the six is not true of the code: an arm scored against another manifest is not
refused at evaluation. Its criterion, `every_arm_reads_the_same_fold_manifest`,
promises that "an arm run against … another manifest digest is refused rather
than pooled", and `evaluate` pools it whenever its groups coincide.

The audit's list, re-run on `main` on 2026-09-22:

```
descriptor_arm_trains_without_a_gpu
encoder_arm_probe_is_selected_inside_the_fold
every_arm_is_contrasted_against_the_shuffled_control
every_arm_reads_the_same_fold_manifest
minimum_detectable_effect_is_reported_for_every_contrast
unregistered_contrast_is_refused_by_name
```

Issue #249 proposed renaming five existing tests and adding the sixth. **The
renames do not work**, for a reason #249 did not check. `criterion_tests`
matches a test to a criterion by its name, exact or extended by a suffix, so one
test can carry only one criterion. Five of the tests #249 names already carry
another spec's criterion:

| Test | Criterion it already carries |
|---|---|
| `test_contrasts_are_pre_registered` | SPEC 0042's `contrasts_are_pre_registered` |
| `test_the_probe_is_selected_inside_the_fold` | SPEC 0054's `the_probe_is_selected_inside_the_fold` |
| `test_the_probe_is_selected_inside_the_fold_by_the_criterion_it_records` | the same, by suffix |
| `test_the_probe_is_selected_inside_the_fold_without_reading_a_test_group` | the same, by suffix |
| `test_selection_is_nested` | SPEC 0042's `selection_is_nested` |

Renaming any of them to a SPEC 0044 name would un-cover the other spec's
criterion. The four candidates that carry no other name each assert less than
their SPEC 0044 criterion, or something else:

- `test_an_empty_registry_refuses_every_contrast` checks an empty registry.
- `test_a_contrast_between_arms_run_on_different_groups_is_refused` checks
  different groups, not different digests.
- `test_an_undetectable_contrast_records_a_null_mde_rather_than_a_number` checks
  a single contrast with no discordance.
- `test_the_control_runs_the_incumbents_code_path` checks which trainer the
  control uses, not what it is contrasted against.

**The digest gap, precisely.** `load_arm_predictions` reads every fold's
`predictions.json` and never compares the `manifest_digest` each one records
against the fold manifest's. `one_contrast` refuses only when the two arms'
group sets differ. A manifest re-measured by `measure_scale.py` keeps its groups
and changes its digest. So an arm run before the re-measurement and an arm run
after it are contrasted as though they described the same data. At run time,
SPEC 0056's reuse rule already treats such a fold as stale. The evaluation path
has no equivalent check.

## Design Decision

**One module, `ml/tests/test_gate_criteria.py`, with one test per missing
criterion.** Each test is named exactly after its criterion and asserts that
criterion's own statement, at the level SPEC 0044 states it. The level is
generally the registry the gate actually registered in `ml/config.yaml`, the arm
bindings that actually ran, or the verdict document.

No existing test is renamed. Where another spec's test already asserts a
mechanism, the new test asserts SPEC 0044's use of it rather than repeating it.
`test_the_probe_is_selected_inside_the_fold` checks the shared probe on a fake
featuriser. `encoder_arm_probe_is_selected_inside_the_fold` checks the encoder
arm's own binding, running on its own featuriser.

**`load_arm_predictions` refuses a fold whose recorded `manifest_digest` is
absent or differs from the fold manifest's.** The refusal names the arm, the
repeat and fold, both digests, and the command that re-runs the arm. It is the
evaluation-side twin of SPEC 0056's reuse rule. It sits in the loader rather
than in the contrast because every reader goes through the loader: `evaluate`,
`run_arm`, the ablation and the sensitivity comparison all do.

Three criteria are asserted exactly as written, including where the code does
not match their wording.

- **`descriptor_arm_trains_without_a_gpu`** runs the real descriptor arm for one
  fold over synthetic measured photographs, in a subprocess where CUDA is hidden.
  It checks that the fold's `cost.json` is written. The test needs TensorFlow:
  `probe_fold` seeds through `src.train`, which imports TensorFlow at module
  level.

  So #249's reading of this criterion — "imports and trains without the training
  stack" — is false of the code today. The criterion itself asks about the GPU,
  not about the training stack. The comment in `probe_fold` claiming that the
  deferred import keeps the arm runnable without TensorFlow is corrected in the
  same change, because it is the sentence that misled #249.
- **`every_arm_is_contrasted_against_the_shuffled_control`** says `metrics.json`.
  The contrasts are written to `contrasts.json` (`CONTRASTS_FILENAME`), and that
  is the file the verdict reads. The test asserts the record `evaluate` writes
  there. SPEC 0044 is approved text and is not edited; the difference is
  recorded here.
- **`minimum_detectable_effect_is_reported_for_every_contrast`** has a second
  half: "no difference below it is described as a difference". The contrast
  records describe nothing, so that half is asserted where a difference is
  described, on the verdict's contrast tables. Every row whose observed
  difference is below its minimum detectable effect, or has none, must read as
  not a difference.

**The audit's verdict for SPEC 0044 becomes an assertion.** SPEC 0043 kept the
repository-wide verdict a warning so that a criterion added tomorrow cannot fail
a test written today, and that still holds for the other specs. For SPEC 0044
the criteria are fixed and every one now has a named test, so a test asserts
that none of them is unmatched.

## Alternatives Considered

- **Rename the tests, as #249 proposed.** Rejected: five of them carry SPEC 0042
  and SPEC 0054 criteria, and a rename would move the gap rather than close it.
- **Loosen `criterion_tests` so one test can match several criteria.** Rejected,
  as #249 itself rejects it: the match is the contract, and a looser one reports
  coverage that is not there.
- **Copy the SPEC 0042 and SPEC 0054 tests under the SPEC 0044 names.** Rejected:
  two copies of one assertion drift apart, and neither would test SPEC 0044's use
  of the mechanism, which is what its criteria are about.
- **Name the manifest test after the half that holds, and leave the digest gap.**
  Rejected: a test named for a criterion that asserts half of it is the false
  coverage SPEC 0043 exists to prevent.
- **Refuse in `contrast_results` rather than in `load_arm_predictions`.**
  Rejected: `arm_metrics`, the ablation and the sensitivity readers never reach
  the contrast, and all of them load through the loader.
- **Make the descriptor arm runnable without TensorFlow**, by moving the seeding
  out of `src.train`. Rejected for this change: it is not what the criterion
  asks, and whether the Python side keeps TensorFlow after ADR 0024 is a
  question for the release fit's spec.

## Scope

- Includes:
  - `ml/tests/test_gate_criteria.py` (new): the six criterion tests, the
    SPEC 0044 audit assertion, and the refusal test for the digest check.
  - `ml/src/crossval.py`: the digest check in `load_arm_predictions`.
  - `ml/src/arms/probe.py`: the one comment that misstates what the deferred
    import buys.
  - Any existing test whose fixture writes predictions under a digest other than
    its fold manifest's, corrected so the fixture and the manifest agree. Each
    one is named in the pull request.
- Does NOT include:
  - Renaming any existing test, or changing `criterion_tests`.
  - The criteria of other specs that the audit reports as unmatched. Most of them
    are the Dart suite, which SPEC 0043's Scope excludes.
  - Making the descriptor arm runnable without TensorFlow.
  - Editing SPEC 0044, or re-running any arm.
  - Deduplicating `_write_measured_version`, of which two copies already exist.
    The new module imports the one in `test_encoder_arm.py` rather than adding a
    third.

## Acceptance Criteria

Each is a test in `ml/tests/test_gate_criteria.py`, named exactly as below.

- `unregistered_contrast_is_refused_by_name`: against the registry in
  `ml/config.yaml`, a request for a pair of the gate's arms that it did not
  register is refused, and the refusal names the request.
- `every_arm_reads_the_same_fold_manifest`: `run_arm` hands every one of the
  four arms the manifest `load_folds_for_config` returned, and evaluation refuses
  a fold scored against another manifest digest rather than pooling it.
- `descriptor_arm_trains_without_a_gpu`: with CUDA hidden, the descriptor arm
  completes one fold and writes a `cost.json` that records its trainings and
  seconds.
- `encoder_arm_probe_is_selected_inside_the_fold`: the encoder arm's binding,
  run with a stand-in forward pass, writes a selection audit whose groups are
  disjoint from the fold's test groups.
- `every_arm_is_contrasted_against_the_shuffled_control`: over the registered
  family, each of the three real arms has one primary contrast against
  `shuffled_control`, carrying a McNemar p-value and a Holm p-value corrected
  within a primary family of three.
- `minimum_detectable_effect_is_reported_for_every_contrast`: every computed
  contrast records the minimum detectable effect of its own discordance, and no
  row of the verdict below its effect reads as a difference.
- `an_arm_scored_against_another_manifest_is_refused_by_name`:
  `load_arm_predictions` refuses a fold with a different digest, and one with no
  digest, naming the fold and the digests.
- `every_spec_0044_criterion_has_a_named_test`: the SPEC 0043 audit reports none
  of SPEC 0044's criteria as unmatched.

## Reproducibility

```sh
cd ml && .venv/Scripts/python.exe -m pytest tests/test_gate_criteria.py -q
cd ml && .venv/Scripts/python.exe -m pytest tests/ -q
mf check
```

Python 3.12.13, with the pinned stack in `ml/requirements.txt`. The two
end-to-end tests need TensorFlow, which the `ml-tests` job installs. The
unmatched list in the Problem was produced by running `audit(SPECS_DIR,
ML_TESTS_DIR)` from `tests/test_criteria_coverage.py` on `main` at `69dbbfc`.

## Risks and Assumptions

- **Assumption:** the four arms behind the E0 verdict all recorded the fold
  manifest's digest. They postdate SPEC 0056, which made the digest a required
  field, and the verdict's condition 1 says they ran on one manifest. Their
  artifacts are on the machine that ran them, not here, so this was not
  re-checked. If one differs, re-evaluating the verdict will now refuse, which is
  the correct outcome: the verdict would then have pooled two manifests.
- **Risk:** existing fixtures may write predictions under one digest and load
  them against a manifest carrying another. The suite finds them on the first
  run. They are corrected in the fixture, and none is corrected by relaxing the
  check.
- **Risk:** the two end-to-end tests add TensorFlow start-up time to the suite.
  They run one fold over a fixture of a few dozen small photographs, which is
  what the existing probe-arm tests already pay.
- **What would invalidate this spec:** a criterion of SPEC 0044 that turns out
  to be false of the code in a way this change cannot fix within its Scope. The
  test would then fail by design, and the criterion would be reported rather
  than renamed around.
