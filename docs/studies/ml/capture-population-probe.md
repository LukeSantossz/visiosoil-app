# Capture-population probe: the verdict

The diagnostic [SPEC 0055](../specs/0055-probe-whether-the-capture-population-is-predictable.md)
specifies, run over dataset version `v1`. It asks whether the **capture
population** is recoverable from the same scale-normalised greyscale patches the
E0 texture arms see. It is a statement about the data, not an arm: it takes no
entry in `evaluation.contrasts`, is Holm-corrected with nothing, and is read
**before** the E0 verdict because it can only change how E0 is read if it is read
first.

## The answer

**The capture population is recoverable. SPEC 0040 D6 is re-opened.**

| | |
|---|---|
| Group-level accuracy | **90 / 97 = 0.928** |
| Wilson 95 % interval | **[0.858, 0.965]** |
| Majority-population prior | **63 / 97 = 0.649** |
| Predicate | lower bound `0.858` **>** prior `0.649` |
| Branch taken | **predictability demonstrated** |

The reading rule was fixed in SPEC 0055 and committed before the run, and the
report carries it so a later reader cannot substitute a different one:

> The Wilson 95 % lower bound on pooled group-level accuracy is compared against
> the majority-population prior. At or below it, predictability was not
> demonstrated at this resolution and SPEC 0040 D6 stands as written. Above it,
> the capture population is recoverable from the patches the arms see and D6 is
> re-opened by name. The lower bound rather than the point estimate, because the
> question is whether predictability was demonstrated; against the prior rather
> than against chance, because always answering the majority population scores
> the prior having learned nothing.

The lower bound clears the prior by 21 points. This is not a close call, and no
reading of the interval puts it below the prior.

## What it does and does not mean

**It does not say the E0 result is wrong.** Recovering the capture population is
not the same as the texture arms exploiting it. What the number says is that the
information is **present in the representation the arms use**, which makes SPEC
0040 D6 — the rule restricting the transported population `B` to training sides —
a mitigation whose sufficiency has not been shown. That is a different claim from
"the gate's result is invalid", and it is weaker. The tempting reading is the
stronger one, so it is named here to be refused.

What follows is an ADR written against these numbers, choosing between the two
options SPEC 0055 fixed in advance so the choice could not be invented after the
fact: **drop population `B` from training entirely**, or **restrict it to arms
that provably cannot exploit an encoding signature.** This document does not take
that decision.

## Per-population recall, and why it is reported

A pooled accuracy near the prior is consistent with a probe that recovers `B`
perfectly and confuses `A` with `C`. `B` is the population the whole question is
about — it lost its EXIF, was re-encoded with a luminance quantization table
three to four times coarser in the band soil texture lives in, and is 69 %
Argilosa and 0 % Muito Argilosa, so its encoding signature is **correlated with
the label**. The pooled figure alone would hide the finding.

| Population | Groups | Recall | What it is |
|---|---|---|---|
| `A` | 14 | 0.571 | bench, EXIF intact |
| `B` | 20 | **1.000** | transported, re-encoded |
| `C` | 63 | 0.984 | bench, second session |

**`B` was recovered 20 of 20.** Not one of its sample groups was mistaken for
anything else, and it is the population whose encoding signature is correlated
with the label. `A`, at 14 groups and 0.571, is the weakest — it is the smallest
population and is confused with `C`, which is the pair a bench-versus-bench
distinction would be expected to blur.

### Confusion matrix

Rows are the true population, columns what the probe answered.

| | → `A` | → `B` | → `C` |
|---|---|---|---|
| `A` | 8 | 1 | 5 |
| `B` | 0 | **20** | 0 |
| `C` | 1 | 0 | 62 |

**A post-hoc observation, and it is not part of the predicate.** The predicate
above is the whole of the decision; this paragraph is an observation made after
seeing the matrix and is recorded as such because it bears on the ADR that
follows. Of the 77 groups that can appear in an E0 fold's **test** side — the 14
`A` and the 63 `C`, since D6 keeps every `B` group train-only — exactly **one**
was mistaken for `B`. The encoding signature that correlates with the label
therefore sits in a region of this representation that test-side photographs
almost never occupy, which bounds how far the leak can reach a scored
photograph. It does not eliminate it, and it is evidence about **this** probe:
a regularised linear classifier over 26 classical descriptors. A
higher-capacity arm may place the boundary differently, and the argument does
not transfer to one without being measured again.

## The partition, which is the probe's own

The probe **does not** run under the SPEC 0042 folds, and this is a correction to
what #213 proposed rather than a convenience. All twenty of `B`'s sample groups
are train-only under SPEC 0040 D6, so `B` is in **no** E0 fold's test side: a
probe scored on those folds could never be scored on the population it exists to
ask about, and would instead answer "can `A` be told from `C`".

So it draws its own: repeated stratified group k-fold at the same `k = 5` and
`R = 5`, grouped on `sample_id` exactly as the protocol requires, stratified on
**capture population** instead of texture class, with every group splittable.
That is legitimate precisely because the probe is a diagnostic about the data and
not an arm — it is reported outside `evaluation.contrasts` and shares no
correction family with anything, so it borrows no arm's partition and spends no
arm's correction budget.

**No sample group spans two capture populations**, asserted over the manifest, so
grouping on `sample_id` leaks no population across a fold boundary.

The alternative — making `B` splittable in the E0 folds so one partition serves
both — was rejected firmly. It would reverse D6 to make a diagnostic convenient,
putting the transported population into the test sides of the very experiment
whose contamination is in question. The probe exists to test the mitigation, not
to remove it.

## What was measured, over what

| | |
|---|---|
| Dataset version | `v1` |
| Manifest digest | `49cc469f8923f5f41e5cdba5c6413712a40559479d7092ccdc0efd3e13af59f9` |
| Photographs | 204 (221 ingested, 11 refused by the patch grid, 6 outside the model's class list) |
| Sample groups | 97 — `A` 14, `B` 20, `C` 63 |
| Features | `ml/src/arms/descriptors.py`, which cuts the patches and calls `ml/src/descriptors.py` — all four groups, 26 dimensions |
| Classifier | `arms.probe`, L2 logistic regression, `C` selected on the inner folds over `(0.01, 0.1, 1, 10, 100)` |
| Folds | k = 5, R = 5, grouped on `sample_id`, stratified on capture population |
| Repeat seeds | 42, 1042, 2042, 3042, 4042 (from `data.seed` via `derive_repeat_seed`) |
| Libraries | scikit-learn 1.5.2, numpy 1.26.4, Python 3.12 |
| Wall clock | 1696 s |

The probe runs on the **same patches the arms see**, asserted by identity rather
than by resemblance: `population_probe.probe_featuriser is
arms.descriptors.descriptor_features`. The same two restrictions the arms apply
are applied here — the four classes the model emits rather than the archive's
five (ADR 0016), and the photographs the patch grid can cut — and a test over the
real archive asserts the probe's partition and the arms' cover one set of sample
groups.

## Reproducing it

```sh
cd ml
.venv/Scripts/python.exe scripts/run_population_probe.py --version v1
```

Machine-readable output at `ml/models/v1/population_probe/probe.json`, which is a
build product and is not tracked. This document is the tracked record.

## A note on how this number was produced

It was produced three times, and the first two are recorded here because the
audit trail is what makes the third checkable.

The first run scored **100** sample groups against a prior of **0.614**. Two
defects, both found by reading the report against the spec before committing it,
and both a case of the code disagreeing with the approved specification rather
than the specification being wrong:

1. **It probed the archive's five-class vocabulary where the arms partition the
   four the model emits.** Three Siltosa sample groups — which no arm ever sees,
   per ADR 0016 — entered the probe, all in population `A`. That is the whole of
   the 100 versus 97 gap.
2. **The prior was counted over photographs and the accuracy over groups.** The
   populations photograph their samples at different rates, so the two differ;
   SPEC 0055 fixed the group-level prior, and comparing a group-level accuracy
   against a photograph-level one compares two quantities.

The second run was correct in both and was discarded before it finished for a
third defect, which changed no number: the probe's fold manifest recorded **zero**
refusals over a version that lost eleven photographs, so the record could not
distinguish that from a version that lost none.

Neither of the first two defects changed the direction of the result — a lower
bound of 0.858 clears 0.614 and 0.649 alike — and that is worth stating plainly
rather than leaving to be inferred: the correction was made because the record
must carry the predicate the spec fixed over the photographs the arms actually
see, not because the answer was in doubt.
