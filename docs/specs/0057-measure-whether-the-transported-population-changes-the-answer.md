# SPEC: chore(ml): measure whether the transported population changes the answer

## Problem

[SPEC 0055](0055-probe-whether-the-capture-population-is-predictable.md)'s probe
demonstrated that the capture population is **recoverable** from the same
scale-normalised greyscale patches the texture arms see — 90 of 97 sample groups,
Wilson 95 % lower bound 0.858 against a majority-population prior of 0.649, with
the transported population `B` recovered 20 of 20. Its pre-registered rule fired
and re-opened SPEC 0040 D6 by name.

**Recoverable is not exploited, and nothing in the record separates the two.**
The probe's finding is that the information is present in the representation. It
does not say a texture arm uses it, and it does not say the E0 verdict would be
wrong. D6's two written options — `B` leaves training entirely, or `B` is
restricted to arms that provably cannot exploit an encoding signature — would
both be taken on an argument rather than on a measurement.

The price of taking that argument the safe way is not small. `B` holds **20 of
the archive's 97 sample groups and 37 of its 204 photographs**, all of them in
training sides where they are the only thing standing between an arm and a
smaller training set. Dropping them costs about **18 % of the training pool** of
a dataset [ADR 0016](../adr/0016-dataset-is-the-existing-dish-archive-and-siltosa-is-out-of-v1.md)
closed at 105 samples and will not reopen.

## Design Decision

**Run the descriptor arm twice over one partition — once with `B` in the training
sides as D6 permits, once with `B` removed from training entirely — and compare
them under a rule fixed here before either runs.**

**The partition does not change, and that is the whole design.** Redrawing the
folds without `B` produces a second fold manifest with a different digest, and a
result pooled across two manifests is refused by construction — correctly, because
the two would not be scored on the same groups. So the partition is untouched and
the **arm** is what changes: a second arm name whose fold trainer drops every
entry belonging to population `B` from its own training side and touches nothing
else. Both arms read the same fold manifest, the same digest and the same test
sides, so the contrast is **paired on the group** exactly as
[SPEC 0042](0042-repeated-group-k-fold-evaluation-protocol.md)'s contrasts are.

`B` is already train-only under D6, so it appears in **no** test side of either
arm. The two runs therefore differ in their training sides and in nothing else,
which is what makes a difference between them attributable to `B`'s presence in
training rather than to the measurement.

**The question, stated so the answer can be read off it.** D6 exists to stop `B`
from contaminating a scored result. The scored result is computed on the 77
splittable groups of `A` and `C`. So the question is exactly: **does `B` in the
training sides change the result on those groups?** If it does not, D6's
sufficiency is demonstrated for this arm — the thing D6 protects is unchanged by
the thing D6 permits. If it does, `B`'s presence is materially affecting a scored
result and D6 does not neutralise it.

**The reading rule, pre-registered.** Group-level correctness on the 77 test
groups, paired, compared by the **exact McNemar test** at `evaluation.alpha`,
with the observed accuracy difference read against the **minimum detectable
effect that contrast records from its own discordance**, exactly as SPEC 0042
requires of every contrast.

**Both clauses must hold to call it a difference**, which is SPEC 0044's
discipline applied here — *"a significant result smaller than the measurement's
own resolution does not count"*. The predicate is therefore exhaustive over the
four combinations rather than defined on two of them:

| McNemar | Difference vs MDE | Reading |
|---|---|---|
| significant | at or above | **`B`'s presence changes a scored result. D6 does not neutralise it**, and the ADR takes the decision with the size and sign in hand |
| significant | below | not demonstrated at this resolution. The test resolves a difference the experiment cannot size, and a difference smaller than the measurement's own floor is not one to act on. **D6 stands** |
| not significant | at or above | not demonstrated at this resolution. A point estimate large enough to matter with a test that cannot reject — the combination that most argues for more groups, which [ADR 0016](../adr/0016-dataset-is-the-existing-dish-archive-and-siltosa-is-out-of-v1.md) says this dataset will never supply. **D6 stands**, and the report says it was this combination |
| not significant | below | not demonstrated at this resolution. **D6 stands as written**, and the 18 % of the training pool that dropping `B` would cost buys nothing this experiment can see |

**The three cells that read "D6 stands" are not the same finding and the report
must not collapse them.** Only the last is a clean null; the middle two are the
experiment reaching its own limit, and an ADR written against them is deciding
under a resolution ceiling rather than against evidence of no effect. The report
records which of the four cells it landed in, by name.

**Direction is reported and does not change which branch is taken.** A
significant difference favouring the `B`-free arm is the leak doing damage. One
favouring `B`-in-training is consistent with the encoding signature helping *and*
with 37 more photographs simply helping, and **this experiment does not separate
those two**; it is written down here so that the more flattering reading is not
chosen after the number. Either way the finding is the same: `B` is not inert.

**What this measures, and what it therefore licenses.** It measures the
descriptor arm: a regularised linear probe over 26 classical features. A network
with more capacity may exploit what that cannot, so a null result licenses D6
**for arms of this class and not for the incumbent CNN**. The E0 verdict must say
which arms the sensitivity was measured on rather than citing it as a general
clearance. Measuring the CNN both ways as well would cost about thirteen hours
against this experiment's two, and is a decision for the Developer rather than an
omission this spec hides.

**The result is reported outside `evaluation.contrasts`.** Like SPEC 0055's
probe, this is a diagnostic about the data and not an arm-versus-arm comparison
about texture. It is Holm-corrected with nothing and takes no correction budget
from the family that answers the gate's question.

**The report is committed whichever way it reads**, in
`docs/ml/transported-population-sensitivity.md`, with the numbers, the seeds, the
dataset version, the manifest digest and the library versions. It is read
**before** ADR 0021, which is the only order in which it can inform the decision
it exists to inform.

## Alternatives Considered

- **Redraw the folds without `B` and compare the two runs.** Rejected, and it is
  the obvious first idea. It produces a second fold manifest with a different
  digest; the two runs are then scored on group sets that are equal only by
  coincidence of the seed, nothing checks that they stayed equal, and
  `load_folds_for_config` refuses the pooling for exactly that reason. Changing
  the arm instead keeps the pairing a property of the artifacts rather than a
  hope about the draw.
- **Take the safe option and drop `B` without measuring.** Rejected by the
  Developer's instruction of 2026-09-05 and on the merits: it spends 18 % of the
  training pool of a closed dataset to buy protection against an effect nobody
  has shown exists.
- **Keep D6 and argue from the probe's confusion matrix.** Rejected. Of the 77
  groups that can appear in a test side, exactly one was mistaken for `B`, which
  bounds how far the leak can reach a scored photograph and is genuinely
  reassuring — and it is an observation about a linear probe's decision boundary,
  not about whether a trained texture arm's output moves. Two hours of compute
  replaces the argument with a number.
- **Run the CNN both ways instead of the descriptor arm.** Rejected for this
  spec. Thirteen hours against two, before a decision that gates a twenty-hour
  gate, and the descriptor arm is the one whose cost makes a paired re-run
  affordable at all. Its narrower licence is stated above rather than hidden.
- **Run both arms and also register the contrast in `evaluation.contrasts`.**
  Rejected, per SPEC 0055's reasoning: that list is pre-registered comparisons
  about texture, and a diagnostic about the data would spend the correction
  budget of the family that answers the gate.
- **Wait and fold this into the E0 gate as a fifth arm.** Rejected. The gate runs
  on the folds D6's decision produces, so a measurement that informs that
  decision cannot be inside the run that depends on it.

## Scope

- Includes:
  - `ml/config.yaml` — register the second arm name. **No** entry under
    `evaluation.contrasts`.
  - `ml/src/arms/` — the `B`-free descriptor arm: `arms.probe.probe_fold` with
    the training side filtered by capture population, and nothing else changed.
  - `ml/src/` — the paired comparison and its report, reusing
    `evaluate`'s exact McNemar and minimum-detectable-effect functions rather
    than reimplementing them.
  - `ml/scripts/` — the entry point that runs both arms and writes the report.
  - `docs/ml/transported-population-sensitivity.md` (new, committed) — the
    verdict, with its numbers, whichever way it returns.
  - `ml/tests/` — one test per acceptance criterion below.
- Does NOT include:
  - **Taking the D6 decision.** That is ADR 0021, written against this number,
    exactly as SPEC 0055 refused to take the decision its own rule triggered.
  - The CNN or frozen-encoder arms, in either configuration.
  - Any change to the fold manifest, its schema, its digest, or SPEC 0040 D6.
  - Running the E0 gate, which is SPEC 0044.
  - Any change under `lib/`.

## Acceptance Criteria

- both_arms_read_one_fold_manifest: the two runs load the same fold manifest and
  record the same digest, so the comparison is paired by construction and a run
  against another manifest is refused rather than pooled.
- the_test_sides_are_identical_fold_by_fold: asserted directly — for every repeat
  and fold, the two arms' scored groups are the same set. A difference here would
  make the contrast meaningless and nothing else in the run would say so.
- the_b_free_arm_drops_b_from_training_and_nothing_else: its training side is the
  other arm's minus every entry whose `source_group` is `B`, and its test side is
  untouched.
- population_b_is_in_no_test_side_of_either_arm: it is train-only under D6, and
  the run asserts that rather than assuming it.
- the_contrast_is_mcnemar_on_groups_with_its_own_mde: the report carries the
  exact McNemar statistic on group-level correctness, the observed accuracy
  difference, and the minimum detectable effect computed from that contrast's own
  discordance.
- the_reading_rule_is_recorded_before_the_run: the predicate is in this spec and
  in the report, and the report states which branch it took and in which
  direction.
- the_reading_rule_is_exhaustive: all four combinations of significance and
  minimum detectable effect have a defined reading, and the report names which
  cell it landed in rather than collapsing the three that leave D6 standing into
  one null.
- the_result_is_reported_outside_the_contrast_family: no entry is written to
  `evaluation.contrasts` and the result is Holm-corrected with nothing, and the
  record says why.
- the_licence_is_recorded_with_the_result: the report states that the sensitivity
  was measured on the descriptor arm and does not clear the incumbent CNN.
- the_verdict_is_committed_whichever_way_it_returns: the report is committed with
  its numbers, the seeds, the dataset version, the manifest digest and the
  library versions, including when the difference is not significant.

## Reproducibility

```sh
cd ml
.venv/Scripts/python.exe -m pytest tests/ -q
.venv/Scripts/python.exe scripts/run_population_sensitivity.py --version v1
```

Python 3.12.13 and the pinned stack of `ml/requirements.txt`, unchanged; no
dependency is added. Both arms are the descriptor arm at its measured 147 s per
fold, so the pair is about **two hours** at `k = 5`, `R = 5`.

Both runs resume under [SPEC 0056](0056-an-interrupted-arm-resumes-instead-of-starting-over.md),
which is why that spec precedes this one: two hours is long enough that an
interruption discarding the whole arm has already happened once on this machine,
to the SPEC 0055 probe at 17 of 25 folds.

## Risks and Assumptions

- **Assumption: `B` is train-only in the fold manifest this runs against.** It is,
  under SPEC 0040 D6, and the run asserts it rather than assuming it. If D6 has
  already been changed when this runs, the experiment is measuring something else
  and must not run.
- **Risk: the result is null and is read as a general clearance.** It is not one.
  It licenses D6 for the descriptor arm, and the report and the E0 verdict must
  both say so by name. This is the most likely way for a correct number to be
  misused, which is why the licence is an acceptance criterion rather than a
  remark.
- **Risk: the result is significant and favours `B`-in-training, and is read as
  "the leak helps".** The experiment cannot separate an encoding signature from
  37 additional photographs. The rule above takes the same branch either way and
  says so before the number exists.
- **Risk: 77 paired groups is few, and the minimum detectable effect will be
  large.** The planning estimate for a paired contrast at this N is about 16
  percentage points. A null result therefore means "no difference this experiment
  could resolve", not "no difference", and the report must use those words. That
  is a real limit on what two hours can buy and it is stated rather than
  discovered afterwards.
- **What would invalidate this spec:** a change to SPEC 0040 D6 taken before it
  runs, a change to the fold manifest or the patch geometry, or a change to
  `source_group`'s derivation.
