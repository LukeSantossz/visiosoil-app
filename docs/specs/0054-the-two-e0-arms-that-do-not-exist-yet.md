# SPEC: feat(ml): add the descriptor and frozen-encoder arms E0 compares

## Problem

[SPEC 0044](0044-four-arm-e0-feasibility-gate.md) is the gate that decides
whether textural class is recoverable from a photograph at all, and it compares
four arms. Two of them do not exist: the classical-descriptor arm and the
frozen-encoder-plus-linear-probe arm. Until they do, the gate cannot run and
every Lane C item stays blocked behind a premise nothing has tested.

## Design Decision

**Both arms are fold trainers with the same signature as `train.train_fold`, and
`crossval.run_arm` dispatches on the arm name.** Each writes the artifacts the
protocol already reads — `predictions.json`, `cost.json`, `runtime.json`,
`selection_audit.json` — so `evaluate.py`, the contrasts and the pooling need no
change. An arm that produced a different artifact shape would be an arm the
protocol cannot contrast, which is the whole point of running four.

**Every arm aggregates the same way: score each patch, average a photograph's
patch distributions into one.** This mirrors what [SPEC 0053](0053-train-on-scale-normalised-greyscale-patches.md)
already does for the incumbent, and it is what makes a contrast a statement
about the *method*. If the descriptor arm pooled its features across patches
into one photograph vector while the CNN averaged distributions, a difference
between them would confound the method with the pooling rule, and no amount of
significance would tell the two apart.

**The descriptors are computed on numpy, and no dependency is added.** They are
four component groups, and the groups are also the units of the ablation
SPEC 0044 requires:

| Group | What it measures | Why it is here |
|---|---|---|
| `first_order` | mean, standard deviation, skewness, kurtosis of patch intensity | The control within the arm. If this group alone carries the result, the arm learned brightness, not texture. |
| `spectral` | energy in radial spatial-frequency bands, from the 2-D FFT | The group that most directly encodes grain size. Patches are scale-normalised, so a band is the same physical frequency in every photograph — which is the property the whole pipeline was built to obtain. |
| `lbp` | rotation-invariant uniform local binary pattern histogram, P = 8, R = 1 | Local micro-texture, invariant to monotonic intensity change, so it survives the lighting differences between capture populations. |
| `glcm` | contrast, homogeneity, energy and correlation from the grey-level co-occurrence matrix, averaged over four directions | Second-order spatial statistics at a short offset — the classical granulometry descriptor, and the one whose absence from the ablation would be conspicuous. |

**Adding `scikit-image` for LBP and GLCM is rejected**, on the precedent
SPEC 0052 set when it rejected OpenCV for one `HoughCircles` call. Both are a
few dozen lines of numpy over a `uint8` patch, both are then deterministic and
inspectable in the same way `ml/src/scale.py` and `ml/src/image_quality.py`
already are, and neither is the kind of numerical work where a library's
correctness is the reason to depend on it. The implementations are tested
against hand-computed values on small arrays rather than against another
library, so the tests do not inherit a second implementation's conventions.

**The classifier for both arms is multinomial logistic regression with L2, and
its `C` is selected on the inner folds only.** Regularisation strength is the
one hyper-parameter either arm has, so it is the one thing selection can be
about; choosing it anywhere but the inner folds is the leak
[ADR 0020](../adr/0020-evaluation-is-repeated-group-k-fold-with-nested-selection.md)
exists to prevent, and `assert_selection_is_nested` is what refuses it. Features
are standardised, and **the scaler is fitted on the training side alone** —
fitting it on everything would leak the test side's distribution into every arm
at once, which is the failure that would flatter all three real arms equally and
therefore hide itself in the contrasts.

**The frozen encoder is MobileNetV2 with ImageNet weights, global-average-pooled,
and it is the same backbone the incumbent arm fine-tunes.** That is deliberate.
Holding the backbone fixed across the two arms makes the contrast between them a
statement about *fine-tuning versus a linear probe on frozen features* — a
question 77 groups might answer — rather than about two architectures at once,
which they cannot. It also needs no GPU, since inference is a forward pass, and
it is the only encoder whose on-device cost the application could plausibly
afford if it ever were adopted.

**Encoder features are computed once per patch and cached for the run.** The
arm is 25 folds over the same photographs; recomputing 5,100 patch embeddings
per fold would spend almost all of the arm's cost re-deriving a deterministic
function of the pixels. Measured: **0.78 s per photograph cold, so 2.6 minutes
for the whole pool once, against 17 ms per photograph warm** — without the cache
the arm's 25 folds would be about 1.1 hours of forward passes and nothing else.

The cache is written under the arm's directory and keyed by the photograph's
path, one file per photograph whose **row index is the patch index** — 204 files
per arm rather than 5,100, for the same key at a coarser granularity.

**A stale entry is refused, never silently rebuilt**, and the identity it is
refused against is more than the manifest digest. The digest identifies the
data; it cannot see `data.image_size`, `preprocessing.canonical_mm_per_px` or
`preprocessing.patch_stride_fraction`, which live in `config.yaml` and move
**where a patch is cut over the very same pixels**. A change to the canonical
scale need not change the patch *count*, so a row-count check would not catch
it either, and the arm would train on embeddings of soil it is no longer
looking at. The store therefore records all three beside the digest, the feature
width, and the preprocessing convention, and a disagreement in any of them stops
the run naming the directory to delete. Rebuilding silently would leave feature
files whose provenance nobody established claiming to describe this version.

The digest is `manifest.manifest_digest` and deliberately **not**
`unmeasured_digest`: the latter blanks the four scale columns so it can be
stable across `measure_scale.py`'s own write, and those columns are exactly what
decides where a patch is cut. A cache keyed by it would survive a re-measurement
that moved every patch.

**The label-shuffled control stays a single arm on the incumbent's path.**
SPEC 0044 registers three primary contrasts, each real arm against one control,
not three controls. The control's job is to show what accuracy the class priors
and the capture artefacts alone permit, and the most capable arm is the
strongest control to hold every other arm against.

## Alternatives Considered

- **Add `scikit-image` and call `local_binary_pattern` and `graycomatrix`.**
  Rejected, above. The precedent is SPEC 0052's rejection of OpenCV, and the
  reason is the same: a dependency admitted for one call is a dependency the
  release path, the CI image and every future reader now carry.
- **Pool descriptors across a photograph's patches into one feature vector.**
  Rejected. It is the cheaper and more natural shape for a descriptor arm, and
  it makes the arm incomparable to the CNN: the two would differ in method *and*
  in aggregation, and the contrast could not attribute a difference to either.
- **Use a deeper probe — an MLP head — on the frozen features.** Rejected. A
  non-linear head stops measuring the representation and starts measuring the
  head, and the question this arm exists to ask is whether ImageNet features
  already separate the classes.
- **Use a stronger encoder — EfficientNet, a ViT, a self-supervised backbone.**
  Rejected for this gate. There is no local GPU, the on-device latency gate
  (#215) cannot run for want of hardware, and SPEC 0044's decision rule makes
  encoder adoption impossible while that condition is unmet. A stronger encoder
  would spend the arm's cost on a comparison whose result could not be acted on.
- **Select more than the regularisation strength — the descriptor subset, the
  LBP radius, the band count.** Rejected. Every added selection dimension is
  paid for out of the same inner folds, and at this N the selection variance
  would exceed the effect the gate is trying to detect. The component groups are
  fixed here, before the run, and the ablation reports them rather than choosing
  among them.
- **Skip the encoder arm entirely, since it cannot be adopted.** Rejected. It
  cannot win the *secondary* contrast, but it is one of the three arms in the
  **primary** family, which asks whether any method clears the shuffled control.
  Dropping it would remove a chance for the gate to return positive.

## Scope

- Includes:
  - `ml/src/descriptors.py` (new) — the four component groups over a `uint8`
    patch, pure numpy, no TensorFlow, and a named grouping so the ablation can
    remove one group at a time.
  - `ml/src/arms/probe.py` (new) — the shared fold trainer both arms are thin
    wrappers around, parameterised by a featuriser. The nested selection, the
    standardisation, the aggregation back to one prediction per photograph and
    every fold artifact live here, in one place, because two arms that differed
    in any of them would not be comparable.
  - `ml/src/arms/descriptors.py` and `ml/src/arms/encoder.py` (new) —
    `descriptor_fold` and `encoder_probe_fold`, each with `train_fold`'s
    signature and each a binding of a featuriser to `probe_fold`.
  - `ml/src/crossval.py` and `ml/src/train.py` — dispatch `--arm` to the fold
    trainer that implements it, refusing an arm name nothing implements rather
    than silently running the incumbent. **Both** entry points, not one:
    `crossval.run_arm` runs a whole arm and `train.train` runs a single fold,
    and the latter is what CI dispatches one job per fold to — so it is the path
    a published result comes from, and it took the arm name for the directory
    while always running the incumbent.
  - `ml/src/crossval.py` — refuse an arm name and a `shuffled_control` flag that
    disagree. They travel independently into both entry points, and either
    mismatch writes a result the artifacts cannot correct: unpermuted labels
    under `shuffled_control` is a control that is not one, and every primary
    contrast is read against it. SPEC 0044 warns about it in prose, and prose is
    not a guard.
  - `ml/config.yaml` — register the four arm names and the four contrasts:
    three `primary`, each real arm against `shuffled_control`, and exactly one
    `secondary`, `encoder_probe` against `descriptors`.
  - The encoder feature cache, keyed by manifest digest.
  - `ml/tests/` — one test per acceptance criterion below.
- Does NOT include:
  - **Running the gate, or writing its verdict.** That is SPEC 0044, and it runs
    after the capture-population probe is read.
  - The capture-population probe (#213), which reuses the descriptor arm and is
    its own spec.
  - The descriptor ablation's *verdict*. The machinery to run the arm with a
    group removed is here; reporting the ablation is part of SPEC 0044's verdict.
  - Any change to `ml/src/evaluate.py`, the contrast machinery, the pooling, or
    the fold manifest schema. All four already exist and this spec is written to
    fit them.
  - Adopting a method, or any change under `lib/`.
  - The on-device latency gate (#215), which needs hardware nobody here has.

## Acceptance Criteria

- every_arm_writes_the_artifacts_the_protocol_reads: each new arm produces
  exactly those four artifacts — `predictions.json`, `cost.json`, `runtime.json`
  and `selection_audit.json` — in the shape the incumbent writes them, asserted
  by loading a completed fold through `crossval.load_arm_predictions`. Four and
  not "the same as the incumbent": the incumbent also writes `model.keras` and
  `fine_tune.json`, and a probe over frozen or arithmetic features has no
  backbone to unfreeze and no checkpoint worth keeping.
- the_selection_never_reads_a_test_group_even_when_the_audit_is_clean: a test
  asserts that of every featurisation a fold performs, only the last may be the
  test side. The audit alone cannot establish this — it is written from what
  `inner_folds` returned, so an arm that builds honest inner folds and then
  scores its candidates on the outer test side files a **clean** audit. That
  blind spot is in `train.train_fold` too, and closing it there is not this
  spec's, but it is recorded here rather than left for someone to rediscover.
- an_unimplemented_arm_name_is_refused_by_name: `run_arm` with an arm nothing
  implements fails, naming the arm and the ones that exist, rather than running
  the incumbent under that name.
- the_single_fold_entry_point_runs_the_arms_own_method: `train.train` resolves
  the trainer through the same dispatch, so `--arm descriptors` on the entry
  point CI uses cannot write a CNN's checkpoint into the descriptor arm's
  directory for every contrast downstream to read as the descriptor arm's.
- an_arm_name_and_a_control_flag_that_disagree_are_refused: both entry points
  refuse unless `arm == shuffled_control` exactly when the labels are permuted.
- the_registered_contrasts_are_exactly_the_four_e0_names: the shipped config
  carries those four `(name, arms, family)` triples and no others. Counting
  families is not enough — three differently-named `cnn`-against-control entries
  would satisfy a count of three primaries while leaving two real arms
  uncontrasted, and the gate would return a verdict on one arm believing it had
  read three.
- a_cache_directory_without_its_sidecar_is_refused: `.npy` entries with no
  `index.json` are entries whose provenance nothing establishes. Adopting them
  would write a sidecar claiming this run's geometry over embeddings computed
  under another, and the row-count check cannot see the difference.
- each_arm_averages_patch_distributions_into_one_prediction: every arm writes
  one row per photograph whose distribution is the mean over that photograph's
  patches, so a contrast compares methods and not aggregation rules.
- the_descriptor_groups_are_computed_without_scikit_image: `ml/src/descriptors.py`
  imports neither `skimage` nor TensorFlow, asserted in a subprocess.
- lbp_and_glcm_match_hand_computed_values: both are asserted against values
  computed by hand on small arrays, not against another library's output.
- descriptors_are_invariant_to_what_they_claim_to_be: the LBP histogram is
  unchanged by a monotonic intensity shift.
- the_spectral_bands_scale_as_the_arithmetic_says: band energies scale by the
  square of a contrast scaling, the normalised distribution is therefore
  unchanged, and adding a constant changes nothing because DC is excluded.
- the_whole_descriptor_is_invariant_to_a_quarter_turn: the entire feature vector
  is unchanged when the patch is rotated by 90 degrees. This is the property the
  four-direction GLCM average and the rotation-invariant LBP mapping exist to
  obtain, and it was missing from this list — the dish's placement in the frame
  is arbitrary, so a descriptor that moved with it would report the
  photographer's hand. It holds exactly rather than approximately: the Fourier
  magnitude is symmetric under the same turn, the four co-occurrence offsets
  permute among themselves once the pair is unordered, and each LBP code is a
  circular shift.
- an_ablation_removes_one_component_group_at_a_time: the descriptor arm accepts a
  set of component groups; removing one changes the feature width by exactly that
  group's size **and leaves every remaining value identical**. The width alone is
  not enough: if the other groups moved when one left, the ablation would confound
  "this group carried the signal" with "the arm changed when it was removed", and
  telling those apart is what the ablation is for.
- the_probe_is_selected_inside_the_fold: for both arms, `C` is chosen on the
  inner folds and the selection audit's intersection with the fold's test groups
  is empty.
- the_scaler_is_fitted_on_the_training_side_only: a test asserts that the
  standardisation statistics come from the training entries alone.
- encoder_features_are_computed_once_per_patch: a second fold over the same
  photographs reads the cache rather than the encoder, asserted by counting
  encoder calls.
- a_cached_feature_from_another_version_is_refused: the cache carries the
  manifest digest, the input size, the canonical scale, the stride fraction, the
  preprocessing convention and the feature width, and a disagreement in any of
  them is refused by name rather than read or silently rebuilt.
- a_partly_written_cache_is_not_read_as_complete: every entry is written to a
  scratch file and renamed over its destination, so an interrupted run leaves
  either the whole entry or none of it. A torn entry is recomputed rather than
  served as short rows, and a failed write leaves nothing at the destination and
  no scratch file behind.
- contrasts_are_registered_before_the_first_run: `ml/config.yaml` carries the
  four contrasts, three `primary` and exactly one `secondary`, and `load_config`
  accepts them.
- the_descriptor_arm_needs_no_gpu: one fold of the descriptor arm completes on
  CPU and writes its per-fold cost.

## Reproducibility

```sh
cd ml
.venv/Scripts/python.exe -m pytest tests/ -q
.venv/Scripts/python.exe -m src.crossval --arm descriptors
.venv/Scripts/python.exe -m src.crossval --arm encoder_probe
```

Python 3.12.13 and the pinned stack of `ml/requirements.txt`, unchanged by this
spec. Both arms are seeded through `seed_everything(derive_repeat_seed(...))`
exactly as the incumbent is, and both are deterministic given the fold manifest:
the descriptors are arithmetic over pixels with no sampling, and the encoder is a
forward pass through frozen weights.

The solver is `lbfgs`, which is multinomial for more than two classes without
being told so — `liblinear` cannot fit a multinomial model at all, being
one-vs-rest only, and this spec first named it in error. `multi_class` is not
passed: it is deprecated across the whole pinned scikit-learn range, so its
absence is the correct call rather than the requirement being unmet. Convergence
is bounded by an explicit iteration cap so a run cannot differ by how long it
happened to iterate.

**The arms need TensorFlow installed even though the descriptors do not use it.**
`seed_everything` and `runtime_mode` live in `src/train.py`, which imports
TensorFlow at module scope, and every arm is seeded through them because a fold
seeded differently from the incumbent is not on the same protocol. So
`ml/src/descriptors.py` imports no TensorFlow and is tested to prove it, while
the descriptor *arm* still requires the training stack to be present. Moving the
seeding out of `src/train.py` would make the arm independent of it and would
touch the incumbent, which is why it is recorded here and not done.

## Risks and Assumptions

- **The descriptor arm is cheap enough to run at 5 by 5 and to ablate, but not
  as cheap as this spec first claimed.** It said "milliseconds per photograph",
  wrong by two orders of magnitude. Measured after implementing, at a 160 px
  patch: **4.5 to 6.2 ms per patch**, so roughly 150 ms per photograph, 31 s for
  one pass over the 204 photographs a fold sees, and **about 13 minutes of
  descriptor time over the full 25 folds**. The conclusion survives — the arm is
  minutes, not hours, and decoding and resampling the photographs dominates it —
  but the premise is corrected here rather than left as a figure nobody checked.
  The logistic regression over a few thousand patch rows remains milliseconds per
  fold. If the arm does prove too slow, SPEC 0044 says the ablation is what gets
  cut, not the repeats.

  **Measured end to end on the real archive**, one outer fold of `v1` — 174
  training and 30 test photographs over 82 and 15 sample groups — the arm takes
  **147 s**, so **about one hour for the full 25 folds**. Its `cost.json` shows
  where that goes: five trainings at 75.9, 0.36, 0.42, 0.47 and 0.13 seconds. The
  fitting is sub-second; the featurisation is everything, and the first training
  carries it because the descriptors of a photograph are memoised for the fold
  once computed. An hour is well inside what the gate can spend, and the ablation
  multiplies it by the number of groups removed.
- **Risk: the encoder arm's feature extraction is the expensive step and it is
  paid once.** 204 photographs at 25 patches is 5,100 forward passes through
  MobileNetV2 at 160 px. On CPU that is minutes, not hours, and the cache makes
  it once rather than twenty-five times. If it proves infeasible anyway, the arm
  is recorded as **not executed** — SPEC 0044's condition 1 — and is never
  reported as having lost a comparison it did not enter.
- **Risk: a hand-rolled LBP or GLCM is subtly wrong.** This is the real risk, and
  it is why the tests assert hand-computed values on small arrays rather than
  agreement with a library: a wrong implementation that happens to agree with a
  wrong expectation is the failure mode, and a second implementation would not
  catch it. The invariance tests are the second line — a descriptor that claims
  rotation or monotonic-intensity invariance and does not have it is wrong
  whatever its values.
- **Risk: the descriptor arm beats the incumbent.** Not a risk to this spec; it
  is a result, and it is one the gate is built to be able to return.
- **The encoder cannot be adopted in this round whatever it scores.** SPEC 0044's
  condition 3 is the on-device latency gate, #215, which needs a physical device
  nobody has. The verdict must record condition 3 as *not met for want of
  hardware*, which is not the same as the encoder having lost, and the descriptor
  path ships on that ground.
- **What would invalidate this spec:** a change to the evaluation protocol, a
  change to the patch geometry that moves what a descriptor is computed over, or
  a decision to compare architectures rather than fine-tuning against a probe.
