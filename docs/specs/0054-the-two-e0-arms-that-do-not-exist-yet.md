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
function of the pixels. The cache is keyed by the photograph's path and its
patch index, is written under the arm's directory, and is invalidated by the
manifest digest, so a cache from another dataset version cannot be read.

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
  - `ml/src/arms/` (new) — `descriptor_fold` and `encoder_probe_fold`, each with
    `train_fold`'s signature and each writing the same fold artifacts.
  - `ml/src/crossval.py` — dispatch `--arm` to the fold trainer that implements
    it, refusing an arm name nothing implements rather than silently running the
    incumbent.
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
  `predictions.json`, `cost.json`, `runtime.json` and `selection_audit.json` in
  the same shape the incumbent does, asserted by loading a completed fold through
  `crossval.load_arm_predictions`.
- an_unimplemented_arm_name_is_refused_by_name: `run_arm` with an arm nothing
  implements fails, naming the arm and the ones that exist, rather than running
  the incumbent under that name.
- each_arm_averages_patch_distributions_into_one_prediction: every arm writes
  one row per photograph whose distribution is the mean over that photograph's
  patches, so a contrast compares methods and not aggregation rules.
- the_descriptor_groups_are_computed_without_scikit_image: `ml/src/descriptors.py`
  imports neither `skimage` nor TensorFlow, asserted in a subprocess.
- lbp_and_glcm_match_hand_computed_values: both are asserted against values
  computed by hand on small arrays, not against another library's output.
- descriptors_are_invariant_to_what_they_claim_to_be: the LBP histogram is
  unchanged by a monotonic intensity shift, and the spectral bands of one patch
  scale as the arithmetic says when its contrast is scaled.
- an_ablation_removes_one_component_group_at_a_time: the descriptor arm accepts a
  set of component groups, and removing one changes the feature width by exactly
  that group's size.
- the_probe_is_selected_inside_the_fold: for both arms, `C` is chosen on the
  inner folds and the selection audit's intersection with the fold's test groups
  is empty.
- the_scaler_is_fitted_on_the_training_side_only: a test asserts that the
  standardisation statistics come from the training entries alone.
- encoder_features_are_computed_once_per_patch: a second fold over the same
  photographs reads the cache rather than the encoder, asserted by counting
  encoder calls.
- a_cached_feature_from_another_version_is_refused: the cache carries the
  manifest digest and a mismatch is refused rather than read.
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
forward pass through frozen weights. `liblinear`/`lbfgs` convergence is bounded
by an explicit iteration cap so a run cannot differ by how long it happened to
iterate.

## Risks and Assumptions

- **Assumption: the descriptor arm is cheap enough to run at 5 by 5 and to
  ablate.** Four component groups over 25 patches is milliseconds per photograph
  and a logistic regression over ~200 rows is milliseconds per fold, so the arm
  should complete in minutes. If it does not, SPEC 0044 says the ablation is
  what gets cut, not the repeats.
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
