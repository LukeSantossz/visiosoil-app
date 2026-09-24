# SPEC: feat(descriptors): the descriptor contract and the arithmetic that reads it

## Problem

ADR 0024 makes `spec.json` a contract of numbers: the descriptor fixed points,
the feature order, a standardiser and a logistic regression. No schema for it
exists, nothing in Python writes it, nothing in Dart reads it, and nothing turns
those numbers into a class distribution. So the second half of ADR 0024's
golden, the class distribution, cannot exist either. This is A4 (2) of the
implementation map. The first half, SPEC 0078's outcome and named cause, is
merged. Its three contract causes are declared, and nothing produces them yet.

## Design Decision

**One schema, written by one Python function and read by one Dart function, and
held together by a golden.** The Python writer is the half B3 will call when it
exports the release fit, so the schema is defined here once and is not defined
again there.

**The schema, `spec_version: 2`.** Version 1 was SPEC 0035's network contract,
which was never shipped.

```json
{
  "spec_version": 2,
  "classifier": "descriptors",
  "model_version": "<string>",
  "dataset_version": "<string>",
  "classes": ["Arenosa", "Media", "Muito Argilosa", "Argilosa"],
  "geometry": {
    "canonical_mm_per_px": 0.12920342774728033,
    "patch_px": 160,
    "patch_stride_fraction": 0.5,
    "min_patches": 9
  },
  "descriptors": {
    "glcm_levels": 16,
    "glcm_offsets": [[0, 1], [-1, 1], [-1, 0], [-1, -1]],
    "lbp_points": 8,
    "lbp_radius": 1,
    "lbp_mapping": "rotation_invariant_uniform",
    "spectral_bands": 8,
    "min_cycles_per_patch": 2.0,
    "features": ["first_order.mean", "…26 names in output order…"]
  },
  "standardiser": { "mean": [26 numbers], "scale": [26 numbers] },
  "regression": {
    "coefficients": [[26 numbers], "…one row per class…"],
    "intercepts": [one number per class]
  },
  "aggregation": "mean"
}
```

The fields mean what the pipeline that produced them means:

- `classes` is the model's output order, from `cfg["classes"]`.
- `geometry` is `cfg["preprocessing"]` and `cfg["data"]["image_size"]`.
- `descriptors` holds `src.descriptors`' fixed points and `feature_names()`.
- `standardiser` is the fitted `StandardScaler`'s `mean_` and `scale_`.
- `regression` is the fitted `LogisticRegression`'s `coef_` and `intercept_`,
  with rows in `classes` order.
- `aggregation` is the rule `arms.probe._predict` applies: the mean of the
  patches' distributions.

Unknown keys are ignored, so C2's band constants can be added later without a
version change.

**The arithmetic.** For each patch:

1. `z = (x − mean) / scale`;
2. `logits = coefficients · z + intercepts`;
3. `p = softmax(logits)`, computed after subtracting the maximum logit.

The photograph's distribution is the mean of `p` over its patches. This is
exactly `Pipeline.predict_proba` for a multinomial lbfgs `LogisticRegression`,
then the mean in `_predict`.

**Refusals are split by what the reader can do, as ADR 0015 groups them.**

- **`contractMalformed`: the file is broken.** That covers text that does not
  parse; a document that is not an object; a required field that is missing or
  has the wrong type; a non-finite number; a scale of zero or below; an empty or
  duplicated class list; and lengths that disagree with each other: `mean`,
  `scale` or a coefficient row against `features`, and coefficient rows or
  `intercepts` against `classes`.
- **`contractUnsupported`: the file is well formed and describes something this
  build does not compute.** That covers a `spec_version` other than 2; a
  `classifier` other than `descriptors`; an `aggregation` other than `mean`;
  any descriptor fixed point that differs from `patch_descriptors.dart`'s
  constants; and a `features` list that is not `descriptorFeatureNames` in
  order.

  The last two are what keep a model fitted on one definition of the
  descriptors from being served by another. A descriptor that changed on one
  side and not the other still yields plausible numbers, and nothing
  downstream could tell.

**The golden.** `ml/scripts/generate_contract_golden.py` writes
`test/fixtures/contract/golden.json`. It fits the **real** `arms.probe.fit_probe`
on synthetic, seeded, four-class features, and writes the contract through the
real writer. It also writes a few "photographs", each a small block of patch
feature rows, together with the distribution the fitted pipeline gives them:
`predict_proba` averaged over the block. Dart must reproduce each distribution
within SPEC 0030's tolerance, `1e-9·|p| + 1e-12`.

**The golden is not compared byte for byte with a regeneration.** Coefficients
from lbfgs move in their last digits across the scikit-learn versions the
requirements allow. So the Python tests assert properties that do not depend on
the version:

- the committed contract's numbers, evaluated with numpy, reproduce the
  committed distributions;
- for a pipeline freshly fitted in the test, the writer's numbers reproduce that
  pipeline's own `predict_proba`, so the export is right whatever the fit is.

## Alternatives Considered

- **Load the contract into `InferenceService`, move the labels to it and delete
  `SoilTextureLabels` now,** as SPEC 0035 planned. Deferred to the wiring spec,
  by the Developer on 2026-09-24. Those labels feed the TFLite path the wiring
  replaces, so the change would touch that path twice, and a descriptor contract
  would be read to run a CNN.
- **A JSON Schema file validated in both languages.** Rejected. It would add a
  validator dependency in Dart, and it still could not express the rules that
  matter most here: agreement with the Dart constants and consistent lengths.
- **Leave the arithmetic to the wiring.** Rejected. A contract that nothing can
  evaluate cannot be tested for meaning, and ADR 0024's golden names the class
  distribution alongside the features.
- **Compare the golden byte for byte with a regeneration,** as SPEC 0077 does.
  Rejected here for the version drift described above. SPEC 0077's fixtures are
  integer arithmetic; this one is a fit.

## Scope

- Includes:
  - `ml/src/contract.py`: `CONTRACT_SPEC_VERSION = 2`, and
    `descriptor_contract(pipeline, cfg, *, model_version, dataset_version)`,
    which returns the schema above from a fitted `fit_probe` pipeline. It
    refuses a pipeline fitted on a class set other than `cfg["classes"]`.
  - `ml/scripts/generate_contract_golden.py` and
    `test/fixtures/contract/golden.json`.
  - `ml/tests/test_contract.py`.
  - `lib/core/services/descriptors/descriptor_contract.dart`:
    - `DescriptorContract`, the parsed contract;
    - `parseDescriptorContract(String)`, which returns the contract or a
      `ClassificationFailureCause`;
    - `DescriptorContract.distribution(List<Float64List> patches)`, the
      arithmetic above.
  - `test/services/descriptor_contract_test.dart`.
- Does NOT include:
  - Loading `assets/models/spec.json` at run time, producing `contractMissing`,
    reading labels from the contract, deleting `SoilTextureLabels`, the
    label-literal sweep, or un-ignoring `assets/models/spec.json`. Those are the
    wiring spec.
  - Committing a real `spec.json`, or any release fit. That is B3.
  - The dispersion threshold and C2's band constants: uncalibrated, and read by
    nothing yet.
  - Any change to `src.descriptors`, `src.arms.probe` or
    `patch_descriptors.dart`.
  - The patch grid or the scale reader, which are A6 Dart (2). `geometry` is
    parsed and checked for sane values only.

## Acceptance Criteria

Python:

- `the_writer_reproduces_the_pipeline`: for a freshly fitted `fit_probe`
  pipeline, the arithmetic over the writer's numbers equals `predict_proba`
  within the tolerance.
- `the_contract_carries_the_reference_fixed_points`: `descriptors` equals
  `src.descriptors`' constants and `feature_names()`, and `classes` equals
  `cfg["classes"]`.
- `the_writer_refuses_a_pipeline_fitted_on_other_classes`
- `the_committed_golden_is_self_consistent`: numpy over the committed contract
  reproduces every committed distribution.

Dart:

- `dart_distribution_matches_the_golden`: every golden photograph's distribution
  is within the tolerance.
- `the_golden_contract_parses`: the committed contract parses, and its classes
  come back in order.
- `malformed_contract_yields_contract_malformed`: invalid JSON; a document that
  is not an object; each required field removed; a wrong type; a non-finite
  number; a non-positive scale; an empty or duplicated class list; and each
  length mismatch.
- `unsupported_contract_yields_contract_unsupported`: a `spec_version` other
  than 2, another `classifier`, another `aggregation`, each changed descriptor
  fixed point, and a reordered or renamed feature list.
- `unknown_keys_are_ignored`
- `a_photograph_with_no_patch_is_refused`: `distribution([])` and a patch of the
  wrong width raise an `ArgumentError`.

## Reproducibility

```sh
cd ml && .venv/Scripts/python.exe scripts/generate_contract_golden.py
cd ml && .venv/Scripts/python.exe -m pytest tests/test_contract.py -q
flutter test test/services/descriptor_contract_test.dart
flutter analyze && flutter test && mf check
```

Python 3.12, scikit-learn 1.5.2 and numpy 1.26.4 locally, within the ranges in
`ml/requirements.txt`. Flutter 3.44.1 and Dart 3.12.1.

## Risks and Assumptions

- **Assumption:** multinomial lbfgs `predict_proba` is the softmax of
  `decision_function` across the pinned scikit-learn range. The writer test
  checks this against the installed version on every run, so a version that
  broke it would fail rather than drift.
- **Risk:** synthetic features do not exercise magnitudes a real fit produces.
  The arithmetic has no branch that depends on magnitude, and the softmax
  subtracts the maximum logit, so overflow is not reachable.
- **What would invalidate this spec:** B3 finding that the release fit needs a
  field this schema cannot carry. It would then extend the schema, with a new
  `spec_version` if the change is not additive.
