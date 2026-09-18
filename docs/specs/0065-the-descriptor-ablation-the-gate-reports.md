# SPEC: feat(ml): run the descriptor ablation the E0 gate reports

## Problem

[SPEC 0044](0044-four-arm-e0-feasibility-gate.md) requires the E0 verdict to
report "the descriptor arm with each component group removed in turn, over the
same folds", and nothing runs that. [SPEC 0054](0054-the-two-e0-arms-that-do-not-exist-yet.md)
built the machinery — `descriptor_features` takes a `groups` argument and
`describe_patch` returns the same numbers a shorter list asks for — and then
excluded the reporting from its own Scope by name, leaving it to this gate. The
gate cannot be written today: `fold_trainer_for` refuses every name but the six
arms it registers, so there is no way to run the arm with a group removed and no
artifact for a verdict to read.

## Design Decision

**Each removed group is its own arm, run through `crossval.run_arm` like every
other arm, and the four are read as one diagnostic family paired against the
full descriptor arm.**

**Four arms rather than one loop.** `descriptors_without_first_order`,
`descriptors_without_spectral`, `descriptors_without_lbp` and
`descriptors_without_glcm`, registered in `ARM_TRAINERS` beside the arms already
there and each binding `descriptor_features` to `GROUPS` minus its own group.
The alternative — an in-process loop that refits four feature sets inside one
fold — would produce a bespoke artifact nothing else in the protocol reads, and
would give up the four properties the orchestrator already has and this
diagnostic needs as much as the gate does: a fold is reused rather than
recomputed (SPEC 0056), its partition is verified before reuse (SPEC 0063), its
cost is recorded per fold, and its selection is audited against the fold's test
groups. The naming follows `descriptors_without_b`, which is the same shape of
question asked of a population instead of a feature group.

**The ablation registers no contrast, and that is deliberate.** SPEC 0044
pre-registers exactly four contrasts and `evaluation.contrasts` stays as it is:
three `primary` against `shuffled_control` and one `secondary`. Each ablation
arm pairs with `descriptors`, and the pair is computed by `evaluate.one_contrast`
outside the registry — the precedent is SPEC 0057's sensitivity pairs, which
pair the same way and take no entry for the same reason. Registering them would
enlarge the families whose correction the ship decision is read under, so a
diagnostic would move the threshold the decision rule uses. It must not.

**Corrected within its own family of four, and never beyond it.** The four
contrasts are Holm-corrected among themselves, because four tests asked of one
question is where an uncorrected family invents a winner. The correction stays
inside the ablation: no ablation contrast enters the primary or the secondary
family, and the report says so in the words it carries.

**Read with the same two clauses as everything else.** A group's removal is a
difference only when the exact McNemar test is significant at `evaluation.alpha`
after the within-family correction **and** the observed group-level accuracy
difference is at least the minimum detectable effect that contrast records from
its own discordance. At 77 splittable groups most cells are expected to fail the
second clause, which is the point of recording it: "removing the spectral group
changed nothing we could measure" and "removing it changed nothing" are different
statements and the report is required to make the first.

**A variant that did not run is recorded, not raised.** SPEC 0063 settled this
for the gate's own contrasts, and the same rule holds here: an ablation arm with
no predictions is named as not executed and its contrast is omitted, while every
other contrast is computed. A four-hour diagnostic that returns nothing because
one arm was interrupted would be a diagnostic nobody runs twice.

**The report is `models/<version>/descriptor_ablation/ablation.json`**, beside
`d6_sensitivity/sensitivity.json` and in the same shape: the reading rule in
prose, the contrasts with their statistics, and what was measured. The verdict
SPEC 0044 commits reads that file rather than recomputing anything, because two
implementations of one McNemar test is how a diagnostic and a gate come to
disagree about the same groups.

## Alternatives Considered

- **Report each group alone instead of each group removed.** Rejected: SPEC 0044
  names "each component group removed in turn", and leave-one-out answers what
  the gate asks — whether the arm still works without a group — where
  leave-one-in answers what a group can do by itself. The second is a different
  and weaker question at this N, since four one-group arms would each be
  compared against a full arm they differ from in three groups at once.
- **Both directions, eight arms.** Rejected as cost for a question nobody asked:
  it doubles a four-hour diagnostic and doubles the family the correction runs
  over, which makes every cell harder to resolve at the N that is already the
  binding constraint.
- **Fold the ablation into `src/sensitivity.py`.** Rejected. That module reads
  one fixed question — the transported population — and its pairs, licence and
  reading rule are written for it. Sharing the file would mean a report whose
  name says population and whose contents sometimes say feature groups.
- **Run the ablation inside the same process as the gate's arms, concurrently.**
  Rejected on this machine. `cost.json` is an artifact of the protocol, and two
  arms sharing twelve cores record a wall clock that describes the contention
  rather than the arm. The runs are serialised and the report says which machine
  and which other arm was idle.
- **Wait for the gate's own arms to finish and fold the ablation into the
  verdict's own change.** Rejected: the verdict is blocked on 26.5 hours of
  control training and this diagnostic is not, so building it now is free time,
  and a verdict that must also introduce four arms is a change nobody can review
  as one thing.

## Scope

- Includes:
  - `ml/src/ablation.py` (new) — the four arm names derived from
    `descriptors.GROUPS`, the featurisers, the reading rule in the words this
    spec fixes, and the report the runner writes.
  - `ml/src/crossval.py` — register the four arms in `ARM_TRAINERS`, derived
    from `ablation`'s names rather than spelled a second time.
  - `ml/scripts/run_descriptor_ablation.py` (new) — run the four arms over the
    fold manifest and write `ablation.json`, mirroring
    `scripts/run_d6_sensitivity.py`.
  - `ml/tests/test_ablation.py` (new) — one test per acceptance criterion, none
    of them gated on the git-ignored archive (SPEC 0043).
- Does NOT include:
  - The E0 verdict document. That is SPEC 0044's, and it reads this report.
  - Running the gate's own arms, the encoder arm, or the control.
  - Any change to `ml/config.yaml`, to `evaluation.contrasts`, to
    `ml/src/evaluate.py`'s contrast machinery, to the pooling, or to the fold
    manifest schema.
  - Any change under `lib/`, and any adoption decision.

## Acceptance Criteria

- `ablation_removes_one_group_per_arm`: the four arms cover `descriptors.GROUPS`
  exactly once each, and each arm's featuriser asks for every group but its own.
- `ablation_arm_runs_through_the_orchestrator`: `crossval.fold_trainer_for`
  resolves each ablation arm name, and a completed fold of one loads through
  `crossval.load_arm_predictions` carrying the four artifacts the protocol reads.
- `ablation_registers_no_contrast`: `evaluation.contrasts` still holds exactly
  the four entries SPEC 0044 pre-registers, and no ablation arm appears in any of
  them.
- `ablation_is_corrected_within_its_own_family`: the report's contrasts are
  Holm-corrected over the ablation family alone, asserted by a report built from
  fixture predictions whose corrected alphas are the family's own.
- `ablation_reads_a_difference_only_above_the_minimum_detectable_effect`: each
  contrast records the minimum detectable effect computed from its own
  discordance, and a contrast that is significant below it is reported as no
  measured difference.
- `ablation_names_a_group_that_did_not_run`: an ablation arm with no predictions
  is recorded as not executed, no contrast is computed for it, and every other
  contrast is still computed.
- `ablation_report_names_what_it_does_not_clear`: the report states that it is a
  diagnostic and that no cell of it is an input to SPEC 0044's decision rule.

## Reproducibility

```sh
cd ml
python scripts/run_descriptor_ablation.py --version v1
```

The four arms read the same fold manifest as every other arm and refuse a
manifest whose digest differs, so the diagnostic cannot be computed over a
partition the full descriptor arm was not scored on. The report records the
dataset version, the manifest digest, the library versions per arm and the
`descriptors` arm it is paired against.

## Risks and Assumptions

- **Assumption: four arms cost about four hours on this machine.** SPEC 0054
  measured the full descriptor arm end to end at 147 s for one outer fold and
  about an hour for 25, featurisation dominating. Removing a group does not make
  featurisation cheaper in proportion — the patches are decoded and resampled
  either way — so four ablation arms are four passes of roughly that hour.
- **Risk: the diagnostic is read as a ship input.** The mitigation is written
  into the artifact rather than left to discipline: the report carries the
  sentence saying it is not, and no ablation arm is in `evaluation.contrasts`,
  so the gate's own contrast machinery cannot compute one.
- **Risk: the ablation runs while the gate's control arm is training**, which
  would put contention into both arms' recorded cost. The runs are serialised on
  this machine, and the report records the wall clock it observed rather than
  claiming an uncontended figure.
