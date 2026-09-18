# Is textural class recoverable from a photograph of a soil dish?

The verdict of [SPEC 0044](../specs/0044-four-arm-e0-feasibility-gate.md), run
over dataset version `v1`. It is the gate the programme was built on top of
without ever having tested: if no arm separates from a label-shuffled control by
more than run-to-run variance, the product premise is wrong and Lane C stops.

**This document does not adopt a method.** The adoption ADR is written against
these numbers and is not this file, per SPEC 0044's own Design Decision.

## Verdict

**Signal was demonstrated. Two of the three real arms clear the shuffled-label
control by more than the minimum detectable effect their own discordance
records, and the pre-registered decision rule ships the descriptor path.**

| Arm | Group accuracy | Photograph macro-F1 (median over 5 repeats) | Clears the control? |
|---|---|---|---|
| `shuffled_control` | 0.2727 | 0.2152 | — it is the floor |
| `cnn` | 0.4416 | 0.2935 | **no** |
| `descriptors` | 0.6883 | 0.6232 | **yes** |
| `encoder_probe` | 0.7532 | 0.6996 | **yes** |

The incumbent arm is the one that failed. That is the finding this gate exists
to be able to produce, and it is stated first rather than buried: the pipeline
the app ships today did not clear its own floor at this experiment's resolution.

## The primary family: was signal demonstrated?

Three contrasts, each arm against the one control, Holm-corrected **within the
primary family** and read on the corrected value. A difference counts only when
the exact McNemar test rejects at α = 0.05 **and** the observed group-level
accuracy difference is at least the minimum detectable effect that contrast
records from its own discordance — both clauses, so a significant result smaller
than the measurement's own resolution is not reported as a difference.

| Contrast | Observed difference | McNemar p | Holm p | Minimum detectable effect | Reading |
|---|---|---|---|---|---|
| `descriptors_vs_control` | **+0.4156** | 3.31e-06 | 6.61e-06 | 0.2629 | significant, and 1.6× the effect it could detect |
| `encoder_probe_vs_control` | **+0.4805** | 1.21e-07 | 3.63e-07 | 0.2534 | significant, and 1.9× the effect it could detect |
| `cnn_vs_control` | +0.1688 | 0.0596 | 0.0596 | 0.2434 | **neither clause holds** |

All three are paired on the **77 splittable sample groups**, which is the unit
ADR 0020 fixes for every interval and every paired contrast.

### The incumbent arm failed both clauses, not one

`cnn_vs_control` is not a near miss that a larger α would have rescued. Its
Holm-corrected p is 0.0596 against α = 0.05, and its observed difference of
0.1688 is **below** the 0.2434 this contrast could have detected. Either clause
alone would have refused it.

What that licenses saying is narrow and is worth stating precisely: **the
fine-tuned MobileNetV2 arm was not shown to beat a label-shuffled control at this
experiment's resolution.** It is not a demonstration that the architecture cannot
work. Its per-repeat macro-F1 ranges from 0.2709 to 0.4682 — the widest spread of
any arm by a factor of six — which is what fitting 2.2 M trainable parameters on
77 sample groups looks like, and instability of that size is itself why the
contrast cannot resolve.

### What the two arms that cleared it have in common

Both are a **fixed representation with a regularised linear classifier over it**:
26 classical texture features in one case, 1280 frozen ImageNet embedding
dimensions in the other. Neither fits a representation to 77 groups. The gate was
not designed to test "fine-tuning versus frozen features", and this is one
experiment on one archive, so that reading is a hypothesis the numbers are
consistent with rather than a result — but it is the hypothesis the adoption ADR
has to answer.

## The secondary family: which method ships?

| Contrast | Observed difference | McNemar p | Minimum detectable effect | Reading |
|---|---|---|---|---|
| `encoder_probe_vs_descriptors` | +0.0649 | 0.3018 | 0.1336 | not significant, and below the floor |

The encoder scores 6.5 points above the descriptors and the experiment cannot
resolve anything below 13.4. **This is the outcome SPEC 0044 was written
expecting** — its Risks section put the planning estimate at about 16 points and
fixed the default in advance precisely so this cell would not become an argument
after the fact.

### The four adoption conditions, each by name

The frozen-encoder path ships only if **all four** hold. Each is recorded
separately because each fails for a different reason and must be auditable on its
own.

| # | Condition | Met? | Evidence |
|---|---|---|---|
| 1 | **Executed** — ran to completion over all 5 repeats and 5 folds, on the same fold manifest as every other arm | **yes** | 25 fold directories under `models/v1/encoder_probe/`, `not_executed` empty in `contrasts.json`, 125 trainings recorded in `metrics.json` |
| 2 | **Won the secondary contrast** — significant after Holm within the secondary family, sign favouring `encoder_probe`, and at or above that contrast's minimum detectable effect | **no** | p = 0.3018 against α = 0.05; observed +0.0649 against a minimum detectable effect of 0.1336. The sign favours the encoder and neither of the other two clauses holds |
| 3 | **Fast enough** — passes the on-device latency gate on the reference device | **no — not run** | The latency gate is #215 and has not been run. Recorded as not met rather than as passed by default: an unmeasured condition is not a satisfied one |
| 4 | **Amendments accepted** — the Developer accepts amending SPEC 0037's input-size criterion, ADR 0018's rationale and ADR 0012's artifact-size consequence | **no — not sought** | Not put to the Developer, because condition 2 already settles the rule and amendments are not worth seeking for a difference the experiment could not resolve |

**Conditions 2, 3 and 4 fail, so the descriptor path ships.** Condition 1 holds,
which matters for what the record is allowed to say: the encoder arm ran, and it
is not reported as having lost a comparison it never entered.

## The descriptor ablation: what carries the signal?

The arm that ships is four groups of features, and the gate asks which of them
the result rests on. Each group was removed in turn — four arms over the same
folds, paired against the full arm, Holm-corrected **within the ablation family
alone** ([SPEC 0065](../specs/0065-the-descriptor-ablation-the-gate-reports.md)).
No ablation arm is registered in `evaluation.contrasts`, so none of this can
enter the decision rule above.

| Group removed | Group accuracy without it | Difference | Holm p | Minimum detectable effect | Carries signal? |
|---|---|---|---|---|---|
| `lbp` | 0.5325 | **+0.1558** | 0.0167 | 0.1467 | **yes** |
| `first_order` | 0.6753 | +0.0130 | 1.0 | 0.1282 | no |
| `spectral` | 0.6753 | +0.0130 | 1.0 | none | no |
| `glcm` | 0.6753 | +0.0130 | 1.0 | none | no |

**One group carries the arm: the local binary patterns.** Removing `lbp` costs
15.6 points of group accuracy — 0.6883 down to 0.5325 — which is significant
after correction and above the 0.1467 this contrast could resolve. Both clauses,
so it is a measured contribution rather than a point estimate.

**The other three are each individually removable without a measurable cost**,
and that sentence is exact in a way worth preserving. Removing any one of them
moves group accuracy by a single group — 0.6883 to 0.6753, one sample out of 77 —
with discordance of 2 against 3. For `spectral` and `glcm` the minimum detectable
effect is **`none`**: at that discordance the exact McNemar test has **no
rejection region at all**, so the experiment could not have detected a difference
of any size. That is the measurement declaring itself blind, not a demonstration
that the groups are inert.

Three things this does **not** say, each of which the shape of a leave-one-out
ablation invites:

- **It does not say the three are useless.** Leave-one-out measures what a group
  adds *given the other three*. Two groups carrying the same information would
  each be individually removable and jointly essential, and this design cannot
  tell that apart from either being idle.
- **It does not license dropping them.** Removing three groups at once is a fifth
  arm nobody ran, and three differences that each failed to resolve do not add up
  to one that would.
- **It does not make `lbp` the whole result.** The arm without it still scores
  0.5325 against the control's 0.2727.

The diagnostic is the one SPEC 0044 wanted for a reason: *"an arm that wins on
`first_order` alone learned brightness, not texture."* That failure mode did not
happen. The group that carries this arm is a local texture operator, which is
what the product premise requires it to be — soil texture read from the grain of
the surface, and not from how bright the photograph was.

Each ablation arm cost about 15 minutes over its 25 folds, and the base arm 14.3.
The featurisation dominates and is memoised per fold, so removing a group makes an
arm barely cheaper rather than proportionally so.

## No per-class figure is a headline

`metrics.json` carries per-class precision, recall and F1 for every arm, each one
tagged `"headline": false` with the reason in the artifact itself: *"a per-class
figure rests on three to four test groups per fold and is a diagnostic, not a
reportable result"*. This verdict quotes none of them as a result, and neither
should anything downstream of it.

## What this does not license

- **It does not say the app works.** It says the information is present in these
  photographs at a resolution this experiment can detect, over an archive of 194
  samples captured under one protocol.
- **It does not rank the encoder against the descriptors.** At 77 groups the
  secondary contrast cannot, and the pre-registered rule is what resolves the tie
  rather than the point estimate.
- **It does not retire the CNN arm.** It records that the incumbent was not shown
  to beat its own control here.
- **It does not clear any per-class claim**, and in particular says nothing about
  the classes the archive holds fewest of.
- **It is one dataset, one capture protocol, one operator.** ADR 0016 closed the
  dataset at the delivered archive, so nothing here is an estimate of what the
  model would do on photographs from another source.

### The negative-verdict rule, recorded although it did not fire

SPEC 0044 fixes what a negative result would have meant, and this verdict records
it so the rule cannot be re-read after the fact: had no arm cleared the control,
the honest statement would have been that **signal was not demonstrated at this
experiment's pre-registered resolution** — not that no signal exists, since
failing to reject a null is not evidence for it — and **no Lane C item would start
before SPEC 0044 was revisited.** Two arms cleared it, so that branch did not
fire and Lane C continues.

## Provenance

| | |
|---|---|
| Dataset version | `v1` |
| Manifest digest | `49cc469f8923f5f41e5cdba5c6413712a40559479d7092ccdc0efd3e13af59f9` |
| Protocol | repeated stratified group k-fold, k = 5, R = 5, nested selection with `inner_k` = 4 (ADR 0020, SPEC 0042) |
| Base seed | 42 |
| Per-repeat seeds | 42, 1042, 2042, 3042, 4042 (`seed_r = data.seed + 1000 * r`) |
| Groups per repeat | 97, of which **77 are splittable** and carry every interval and contrast |
| Train-only samples | 25 (SPEC 0040 D6, ADR 0021) |
| Refused photographs | 11 |
| α, power | 0.05, 0.8 |
| Fold partition | `scikit-learn` 1.5.2, `numpy` 1.26.4 — recorded in the fold manifest because `StratifiedGroupKFold` assigns differently across releases |

### The library stack, and where it diverges from the pin

Every arm ran under **TensorFlow 2.21.0, Keras 3.14.0, scikit-learn 1.5.2,
numpy 1.26.4**, recorded per fold in `runtime.json`.

`ml/requirements.txt` has pinned **Keras 3.15.1** since [SPEC 0060](../specs/0060-close-the-keras-model-loading-advisories.md)
moved it, and this run does not use that pin. The choice was made deliberately on
2026-09-17: `cnn` and `descriptors` were already complete under 3.14.0, and the
alternatives were to finish the gate under the stack its finished arms recorded,
or to recompute both under the current pin at a cost of about 53 hours.
`require_uniform_runtime` refuses an arm whose folds disagree, so the divergence
is uniform within every arm and across all four. **A reproduction of these
numbers needs 3.14.0**; `ml/tests/test_requirements.py` skips rather than passes
in that environment, and that skip is expected here rather than a defect.

### Devices

| Arm | Device | Host |
|---|---|---|
| `cnn` | GPU (RTX 3070) | WSL2 |
| `shuffled_control` | GPU (RTX 3070) | WSL2 |
| `encoder_probe` | GPU (RTX 3070) | WSL2 |
| `descriptors` | CPU | Windows |

The control was run on the same device as the arm it is the floor for, which is
what keeps `cnn_vs_control` a statement about the method. The descriptor arm is
scikit-learn over 26 features and is CPU-bound whatever the host, which SPEC 0044
records in advance.

## Cost

| Arm | Trainings | Wall clock |
|---|---|---|
| `cnn` | 125 | 26.5 h |
| `shuffled_control` | 125 | 19.6 h |
| `encoder_probe` | 125 | 0.8 h |
| `descriptors` | 125 | 0.2 h |

`inner_k = 4` means five trainings per outer fold — four to select the epoch
count or the regularisation strength, one to refit on the whole training side —
so 125 per arm rather than 25.

**The wall clock is what the folds recorded, contention included.** The Windows
test suite was run twice during the control arm's first folds on 2026-09-17, so a
few of that arm's `cost.json` figures carry it. Predictions are unaffected: the
seeds and `enable_op_determinism()` fix them, and the contention reaches the
clock and nothing else.

## Reproducibility

```sh
cd ml
python -m src.crossval --version v1 --shuffled-control
python -m src.crossval --version v1 --arm cnn
python -m src.crossval --version v1 --arm descriptors
python -m src.crossval --version v1 --arm encoder_probe
python -m src.evaluate --version v1 --contrasts
python scripts/run_descriptor_ablation.py --version v1
```

`--shuffled-control` and not `--arm shuffled_control`: the flag is what permutes
the labels and the arm name follows from it, and `require_control_matches_arm`
refuses the two if they disagree.

The machine-readable results are `models/v1/contrasts.json`, each arm's
`models/v1/<arm>/metrics.json`, and `models/v1/descriptor_ablation/ablation.json`.
None of them is committed: [ADR 0019](../adr/0019-a-dataset-version-is-a-build-product-and-nothing-under-it-is-versioned.md)
makes everything under a dataset version a build product, and this document is
the committed record of what they said.
