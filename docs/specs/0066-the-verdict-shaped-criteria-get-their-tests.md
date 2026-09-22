# SPEC: test(ml): cover the E0 criteria that only its verdict can satisfy

## Problem

Five of [SPEC 0044](0044-four-arm-e0-feasibility-gate.md)'s acceptance criteria
are statements about its **verdict document**, and no test asserts any of them.
`ml/tests/test_criteria_coverage.py` reports all five as having no test named
after them, which by [SPEC 0043](0043-guard-criteria-covered-where-it-ships.md)
is the definition of uncovered.

They were not skipped. They could not be written: `verdict_is_committed_whichever_way_it_returns`
and its four neighbours assert about a file that did not exist until the gate had
run, twenty-one hours after SPEC 0044's code merged.

The verdict now exists, at `docs/ml/e0-verdict.md`. `docs/ml/*` is exempt from
the Spec Gate (SPEC 0058) and `ml/tests/` is not, so a branch carrying these
tests has to add a spec of its own, and this is it. They ride on the verdict's
own branch because they assert about that document: on a branch without it,
every one of them errors rather than passing vacuously.

## Scope

- Includes:
  - `ml/tests/test_e0_verdict.py` (new) — one test per verdict-shaped criterion
    of SPEC 0044, named after it, reading the committed document. No dataset, no
    TensorFlow, so each runs where the project ships.
- Does NOT include:
  - Any change to what `docs/ml/e0-verdict.md` reports. That document is the
    preceding commit on this branch and is exempt from the Spec Gate (SPEC
    0058); the corrections R3 raised against it — the stop condition restated in
    the registered terms, the same-device claim narrowed to the arms it holds
    for, and the reproduction block naming the stack the run recorded — ride
    here because a test that asserts a sentence and the sentence it asserts
    cannot land apart. No number, no contrast and no condition outcome moves.
  - The six SPEC 0044 criteria that are about the gate's *code* rather than its
    verdict — `unregistered_contrast_is_refused_by_name`,
    `every_arm_reads_the_same_fold_manifest`, `descriptor_arm_trains_without_a_gpu`,
    `every_arm_is_contrasted_against_the_shuffled_control`,
    `minimum_detectable_effect_is_reported_for_every_contrast` and
    `encoder_arm_probe_is_selected_inside_the_fold`. Each is a pre-existing gap,
    unchanged by this spec, and each needs a test against the code rather than
    against a document.
  - Any change to `ml/src/`, to the arms, or to the gate's numbers.

## Acceptance Criteria

- `verdict_states_each_decision_rule_condition_by_name`: a test fails when the
  verdict stops naming any one of the four adoption conditions, when any one of
  them stops carrying its own met-or-not-met outcome in its own row, when the
  two that are not met stop saying which kind of not-met they are, or when the
  verdict stops saying which path ships. The row and not the document, because a
  document that names four conditions and resolves three passes every search
  over the whole file.
- `verdict_is_committed_whichever_way_it_returns`: a test fails when the verdict
  stops recording the dataset version, the manifest digest, the per-repeat seeds,
  the library versions or any arm.
- `descriptor_ablation_names_each_component_contribution`: a test fails when the
  verdict stops naming any component group, stops carrying the removal cost of
  the group that carries the arm, or stops stating the leave-one-out design's own
  limit.
- `no_per_class_figure_is_a_headline`: a test fails when any archive class name
  appears in the verdict at all, which is the strongest form of "quotes none of
  them as a result" that a document check can take.
- `negative_verdict_blocks_lane_c`: a test fails when the verdict stops recording
  the rule that would have applied had no arm cleared the control, when that rule
  stops being one conditional — antecedent and both halves of the consequence in
  a single sentence — or when the document states a second, looser stop
  condition anywhere. The gate has one predicate, and SPEC 0044 is where it is
  registered.
- Every assertion above is proved by mutation rather than asserted to work: each
  mutation of the verdict fails exactly the test named for it and no other.
