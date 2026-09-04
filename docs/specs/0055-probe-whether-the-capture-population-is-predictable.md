# SPEC: chore(ml): probe whether the capture population is predictable from the patches

## Problem

The archive is three capture populations out of one device, and one of them —
the transported population `B` — lost its EXIF and was re-encoded with a
luminance quantization table three to four times coarser in the band soil
texture lives in. **It is also 69 % Argilosa and 0 % Muito Argilosa**, so its
encoding signature is correlated with the label. If a model can recover the
capture population from the same patches it classifies texture from, the E0
verdict may be measuring a compression artefact rather than soil, and nothing
in the gate would say so.

## Design Decision

**A probe predicts the capture population from the same scale-normalised
greyscale patches the texture arms see, using the cheapest arm, and its reading
rule is fixed here before it runs.** It reuses `ml/src/descriptors.py` and
`ml/src/arms/probe.py` unchanged: same features, same regularised linear
classifier, same nested selection, same aggregation of patch distributions into
one prediction per photograph. Only the **label** changes, from texture class to
`source_group`. Nothing new is trained and nothing new is written.

**The probe draws its own partition, and that is a correction to what #213
proposed.** The issue says the probe runs "under the SPEC 0042 folds". It
cannot, and the reason is decisive: **all twenty of population `B`'s sample
groups are train-only** under SPEC 0040 D6, so `B` appears in **no fold's test
side** and a probe scored on those folds could never be scored on the very
population it exists to ask about. Measured over the fold manifest this
repository currently holds — 97 groups after the patch grid's refusals:

| Capture population | Groups | Splittable under SPEC 0042 |
|---|---|---|
| `A` (bench, EXIF intact) | 14 | 14 |
| `B` (transported, re-encoded) | 20 | **0** |
| `C` (bench, second session) | 63 | 63 |

Under the E0 folds the probe would answer "can `A` be told from `C`", which is
not the question. So it draws a partition of its own: repeated stratified group
k-fold at the same `k` and `R`, grouped on `sample_id` exactly as the protocol
requires, stratified on **capture population** instead of texture class, and
with every group splittable. This is legitimate precisely because the probe is a
**diagnostic about the data and not an arm**: #213 already requires it to be
reported outside `evaluation.contrasts`, so it shares no correction family with
any arm and borrows none of their partition.

**No sample group spans two capture populations**, checked over the manifest, so
the population is a property of the group and grouping on `sample_id` leaks
nothing.

**The reading rule, pre-registered as a predicate rather than a judgement.** The
probe's group-level accuracy is compared against the **majority-population
prior, which is 63 / 97 = 0.649**, and the comparison is made on the **Wilson
95 % lower bound** of that accuracy, computed on the pooled group count:

- **Lower bound at or below 0.649** — the probe has not demonstrated that the
  capture population is recoverable at this resolution. SPEC 0040 D6's
  train-only rule **stands as written**, and the E0 verdict is read as it stands.
- **Lower bound above 0.649** — the population *is* recoverable from the
  patches, D6 is a mitigation that has not been shown to be sufficient, and the
  record **re-opens it by name**. The two options are stated now so the choice
  is not invented after the number: drop population `B` from training entirely,
  or restrict it to arms that provably cannot exploit an encoding signature.
  Which one is an ADR written against the number, not this spec.

The lower bound rather than the point estimate, because the question is whether
predictability was *demonstrated*; and against the prior rather than against
chance, because the populations are unbalanced enough that always answering `C`
scores 0.649 while having learned nothing.

**Per-population recall is reported, and `B`'s is the number that matters.** A
pooled accuracy at the prior is consistent with a probe that recovers `B`
perfectly and confuses `A` with `C`, which would be the finding. A probe
reported without its prior and without per-population recall is unreadable when
the populations are this unbalanced.

**The verdict is committed whichever way it goes**, in
`docs/ml/capture-population-probe.md`, with the accuracy, the interval, the
prior, the per-population recall, the confusion matrix, the seeds, the dataset
version, the manifest digest and the library versions. It is read **before** the
E0 verdict, which is the order the map records and the only order in which it
can change how E0 is read.

## Alternatives Considered

- **Run the probe under the E0 fold manifest, as #213 proposed.** Rejected on
  the measurement above: `B` is in no test side, so the probe could not be scored
  on the population it exists to ask about. Keeping the shared folds would buy
  comparability with the arms that the probe does not need — it is not in their
  correction family — at the cost of the answer.
- **Make `B` splittable in the E0 folds so one partition serves both.**
  Rejected, and firmly. That reverses SPEC 0040 D6 to make a diagnostic
  convenient, putting the transported population into test sides of the very
  experiment whose contamination is in question. The probe exists to test the
  mitigation, not to remove it.
- **Use the CNN arm rather than the descriptor arm.** Rejected. The probe is a
  diagnostic that must be cheap enough to run over every repeat and fold, and
  the descriptor arm is the one that is. A stronger probe would also be harder
  to read: it would answer "can *something* recover the population", which is
  almost always yes given enough capacity, rather than "can the representation
  the arms actually use recover it".
- **Report the probe inside `evaluation.contrasts`.** Rejected, per #213. That
  list is pre-registered arm-versus-arm comparisons about texture; a diagnostic
  about the data would take correction budget from the family that answers the
  gate's question.
- **Skip the probe and read E0 directly.** Rejected. It is cheap, it reuses
  machinery that already exists, and the failure it guards against — a gate that
  returns positive because the model learned which session a photograph came
  from — is not detectable from the gate's own numbers.
- **Compare against chance (1/3) rather than the prior.** Rejected. The
  populations are 14 / 20 / 63 groups; always answering `C` scores 0.649 without
  learning anything, so chance is not the floor here.

## Scope

- Includes:
  - `ml/src/population_probe.py` (new) — draw the probe's own partition, relabel
    entries by `source_group`, run the descriptor featuriser through
    `arms.probe.probe_fold`, and pool group-level accuracy with a Wilson
    interval and per-population recall.
  - `ml/scripts/run_population_probe.py` (new) — the entry point, writing the
    probe's artifacts under `ml/models/<version>/population_probe/`.
  - `docs/ml/capture-population-probe.md` (new, committed) — the verdict, with
    its numbers, whichever way it returns.
  - `ml/tests/` — one test per acceptance criterion below.
- Does NOT include:
  - **Changing SPEC 0040 D6.** If the probe reads above the prior, D6 is
    re-opened in an ADR written against the number. This spec fixes the rule and
    runs the probe; it does not take the decision the rule triggers.
  - Any change to `evaluation.contrasts`, the E0 arms, the fold manifest schema
    or `ml/src/evaluate.py`.
  - Running the E0 gate or writing its verdict, which is SPEC 0044.
  - Any change under `lib/`.

## Acceptance Criteria

- the_population_comes_from_the_manifest_and_is_never_inferred: every
  photograph's capture population is read from the manifest's `source_group`
  column, and a row without one fails the probe by name rather than being
  guessed at from its pixel dimensions.
- no_sample_group_spans_two_capture_populations: asserted over the manifest, so
  grouping on `sample_id` cannot leak a population across a fold boundary.
- the_probe_partition_makes_every_population_splittable: population `B` appears
  in at least one test side of the probe's own partition, which it does in none
  of the E0 folds. A test asserts the probe refuses to run on a partition where
  any population is absent from every test side.
- the_probe_runs_on_the_same_patches_the_arms_see: the featuriser is the
  descriptor arm's, over the same scale-normalised greyscale patches, asserted
  by identity rather than by resemblance.
- accuracy_is_reported_against_the_population_prior: the report carries the
  pooled group-level accuracy, its Wilson 95 % interval on the pooled group
  count, the majority-population prior, and the recall of each population by
  name.
- the_reading_rule_is_recorded_before_the_run: the predicate — Wilson lower
  bound against the prior — is in this spec and in the report, and the report
  states which branch it took.
- the_probe_is_reported_outside_the_contrast_family: the probe writes no entry
  to `evaluation.contrasts` and its result is not Holm-corrected with the arms,
  and the record says why.
- the_verdict_is_committed_whichever_way_it_returns: the report is committed with
  its numbers, the seeds, the dataset version, the manifest digest and the
  library versions, including when the probe reads at or below the prior.

## Reproducibility

```sh
cd ml
.venv/Scripts/python.exe -m pytest tests/ -q
.venv/Scripts/python.exe scripts/run_population_probe.py --version v1
```

Python 3.12.13 and the pinned stack of `ml/requirements.txt`, unchanged. The
probe's partition is drawn with `derive_repeat_seed` from `data.seed` exactly as
the protocol's is, so it is reproducible and is recorded in its own fold
manifest. The descriptors are arithmetic over pixels with no sampling. The
measured cost of the descriptor arm is 147 s per fold, so the probe is about an
hour at `k = 5`, `R = 5` — the same order as one E0 arm, which is what makes it
affordable as a diagnostic.

## Risks and Assumptions

- **Assumption: `source_group` identifies the capture population correctly.** It
  is written by ingest from pixel dimensions and EXIF presence, which is a
  property of the file rather than a judgement, and SPEC 0040 records the
  derivation. The probe reads it and never re-derives it.
- **Risk: the probe reads above the prior and the programme's dataset premise
  weakens.** That is the probe working. It is cheap, and finding it out before
  the E0 verdict is read is the entire reason it runs first.
- **Risk: a high reading is over-interpreted.** Recovering the capture
  population is **not** the same as the texture arms exploiting it. A high
  reading says the information is present in the representation, which makes D6
  a mitigation of unproven sufficiency; it does not say the gate's result is
  wrong. The report must say this in those words, because the tempting reading —
  "the E0 result is invalid" — is stronger than the evidence.
- **Risk: 97 groups is few, and `A` has 14 of them.** The interval will be wide
  and the per-population recall for `A` will rest on a handful of groups. The
  Wilson bound is what keeps that honest, and a wide interval that does not clear
  the prior is a real answer at this resolution, not a failed measurement.
- **What would invalidate this spec:** a change to `source_group`'s derivation, a
  change to SPEC 0040 D6 taken before the probe runs, or a change to the patch
  geometry that alters what the descriptors are computed over.
