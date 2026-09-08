# Does the transported population change the answer?

The verdict of [SPEC 0057](../specs/0057-measure-whether-the-transported-population-changes-the-answer.md),
run over dataset version `v1`. It asks whether capture population `B` — the
transported samples SPEC 0040 D6 restricts to training sides — changes a result
scored on the groups D6 protects.

**Read this before [ADR 0021](../adr/), which is the decision it exists to
inform and which this document deliberately does not take.**

## Verdict

**Both contrasts landed in `not_significant_below_mde`. SPEC 0040 D6 stands, and
neither arm re-opened it.**

| Contrast | McNemar p | Observed difference | Minimum detectable effect | Cell |
|---|---|---|---|---|
| `descriptors_sensitivity` | 0.7539 | −0.0260 | 0.1082 | `not_significant_below_mde` |
| `cnn_sensitivity` | 0.2005 | +0.1039 | 0.1941 | `not_significant_below_mde` |

Of the four cells the reading rule defines, this is the one SPEC 0057 calls a
clean null: *"the 18 % of the training pool that dropping `B` would cost buys
nothing this experiment can see."* It is not the resolution-ceiling cell, and it
is not evidence of no effect — it is the experiment seeing what it was powered
to see, and seeing nothing.

## The two contrasts

Both are paired on the **77 splittable sample groups** of populations `A` and
`C`. Population `B` appears in no test side of any arm, which the run asserts
rather than assumes, so the two arms of each pair differ in their training sides
and in nothing else.

### `descriptors_sensitivity`

| | |
|---|---|
| Group accuracy, `B` in training | 0.6883 |
| Group accuracy, `B` withheld | 0.7143 |
| Observed difference | **−0.0260**, favouring the `B`-free arm |
| Discordant pairs | 4 favouring `B`-in-training, 6 favouring `B`-free |
| Discordance rate | 0.1299 |
| Exact McNemar, α = 0.05 | **p = 0.7539** |
| Minimum detectable effect | **0.1082** |

The difference is a quarter of what this contrast could resolve, and the test
does not reject.

### `cnn_sensitivity`

| | |
|---|---|
| Group accuracy, `B` in training | 0.4416 |
| Group accuracy, `B` withheld | 0.3377 |
| Observed difference | **+0.1039**, favouring `B`-in-training |
| Discordant pairs | 19 favouring `B`-in-training, 11 favouring `B`-free |
| Discordance rate | 0.3896 |
| Exact McNemar, α = 0.05 | **p = 0.2005** |
| Minimum detectable effect | **0.1941** |

**This contrast deserves a sentence the descriptor one does not.** Its point
estimate is +10.4 percentage points — larger than the descriptor arm's entire
measurement floor — and it still falls below its own floor of 19.4 points,
because its discordance rate is three times the descriptor arm's (0.390 against
0.130) and the minimum detectable effect is computed from that discordance. The
cell is therefore the clean null by the rule as written, and a reader who takes
only the cell name away from this document will have missed that the incumbent's
point estimate is not small. What the experiment can say is that it could not
resolve it; what it cannot say is that it is zero.

The direction is recorded and does not change which branch is taken, exactly as
SPEC 0057 fixed before the run. A difference favouring `B`-in-training is
consistent with an encoding signature helping **and** with 37 more photographs
simply helping, and this experiment does not separate those two.

## How the accuracy figures were computed

The accuracies above come from `evaluate.pooled_group_correctness`, which pools
each group's probability distributions over **all five repeats and all its
photographs** and yields one decision per group — 77 independent pairs, which is
what the paired test requires. Counting each repeat as a fresh pair would
multiply the apparent evidence by five without adding one independent sample.

They are therefore **not** the protocol's headline per-repeat figures and should
not be quoted as model performance. For the incumbent, the per-repeat group
accuracies are 0.338, 0.481, 0.325, 0.364 and 0.312, and the primary metric ADR
0020 defines — photograph-level macro-F1 — has a median of 0.293 across repeats.
Pooling across repeats is an ensemble and reads higher than any single repeat.

## Provenance

| | |
|---|---|
| Dataset version | `v1` |
| Manifest digest | `49cc469f8923f5f41e5cdba5c6413712a40559479d7092ccdc0efd3e13af59f9` |
| Fold manifest | 97 groups, 77 splittable, 20 train-only, 204 photographs, 11 refused |
| Protocol | repeated stratified group k-fold, k = 5, R = 5 (ADR 0020) |
| Repeat seeds | 42, 1042, 2042, 3042, 4042 (from `data.seed` via `derive_repeat_seed`) |
| Fold-draw libraries | scikit-learn 1.5.2, numpy 1.26.4 |
| Run libraries | scikit-learn 1.5.2, numpy 1.26.4, TensorFlow 2.21.0, Keras 3.14.0 |
| Operator determinism | on, for all 100 folds |
| Devices | `descriptors`, `descriptors_without_b` on CPU; `cnn`, `cnn_without_b` on GPU |
| Measured arms | `descriptors`, `descriptors_without_b`, `cnn`, `cnn_without_b` |

`require_uniform_runtime` accepted every arm, so no arm straddles two devices.
The two pairs ran on different devices, which the protocol permits: uniformity is
required within an arm, not across arms, and determinism was on throughout.

### The partition travelled, and was proved to have travelled

The experiment moved to a machine with a GPU. The fold manifest stores absolute
image paths (issue #233), so the Linux side could not read the copy drawn on
Windows. The partition was carried across by two independent routes and the two
were required to agree:

1. **Mechanical re-root** — the fold assignment copied verbatim, only the path
   root rewritten, with every other field asserted byte-identical and every
   re-rooted path asserted to resolve.
2. **Independent redraw** — the partition drawn again through
   `create_folds_for_config` under the same scikit-learn 1.5.2, and compared
   group by group.

The two agreed exactly: identical fold assignment across 5 repeats × 5 folds over
97 groups, identical counts, identical digest. The re-rooting tool is operational
scaffolding and is not tracked; #233 is the durable fix.

## Cost

| Arm pair | Folds | Trainings | Wall clock |
|---|---|---|---|
| descriptors | 50 | 250 | ~0.9 h (CPU) |
| CNN | 50 | 250 | **46.5 h** (GPU) |

SPEC 0057 budgeted "about six and a half hours" for measuring the incumbent, on
the premise that half of it would be the E0 gate's `cnn` arm paid early. The
measured cost is roughly eight times that estimate. Two findings explain the gap
and both are worth carrying into SPEC 0044's planning:

- **`inner_k: 4` means five trainings per outer fold**, not one — 250 trainings
  per pair, which the estimate did not account for.
- **A GPU does not accelerate this workload.** Measured on the same machine,
  CPU and GPU both run ~20 s per epoch. With `enable_op_determinism()` on — which
  comparability requires and throughput cannot override — the bottleneck is the
  input pipeline, not the convolutions, and moving the device does not move it.

The `cnn_without_b` arm cost 47.9 min per fold against the incumbent's 63.7,
consistent with 37 fewer photographs in each training side.

## Scope of this result

**This is a diagnostic about the data, not an arm-versus-arm comparison about
texture.** It is reported outside `evaluation.contrasts`, is Holm-corrected with
nothing, and takes no correction budget from the family that answers the E0
gate's question. Each contrast is read on its own; neither is pooled with nor
corrected against the other.

**The licence, recorded with the result:** measured on `descriptors`,
`descriptors_without_b`, `cnn` and `cnn_without_b`, each with and without the
withheld population in its training side. It does **not** clear `encoder_probe`,
which SPEC 0044 permits to be recorded as *not executed*.

**What this does not establish.** A null at this resolution is not proof of
absence. The planning estimate for a paired contrast at 77 groups was about 16
percentage points; the descriptor arm resolved to 10.8 and the incumbent only to
19.4. With a dataset [ADR 0016](../adr/0016-dataset-is-the-existing-dish-archive-and-siltosa-is-out-of-v1.md)
closed at 105 samples, no larger `N` is coming, so this is the resolution the
question will ever be answered at.

**This document does not decide D6.** That is ADR 0021, written against these
numbers by the Developer.

## Reproducibility

```sh
cd ml
.venv/Scripts/python.exe -m pytest tests/ -q
.venv/Scripts/python.exe scripts/run_d6_sensitivity.py --version v1
```

`--arms descriptors` runs the cheap pair alone and `--arms cnn` the expensive
one, so the two halves can be split across machines; the report carries each
arm's own runtime, read back from that arm's folds. The machine-readable verdict
is `models/v1/d6_sensitivity/sensitivity.json`.

The run was interrupted three times and resumed under
[SPEC 0056](../specs/0056-an-interrupted-arm-resumes-instead-of-starting-over.md)
each time — a killed parent session, an environment missing `ptxas` that trained
27× slower until corrected, and a WSL2 VM shutdown. **No completed fold was ever
recomputed**; each interruption cost only the fold in flight, which is the
guarantee SPEC 0056 exists to provide and which this run exercised in earnest
rather than in rehearsal.
