# SPEC (full): fix(ml): make training deterministic and the data pipeline fail loud

## Problem

`ml/README.md:3` advertises a "Reproducible TensorFlow/Keras pipeline". It is
not one. Four defects, all in the training path, each of which independently
makes one training run incomparable to the next.

**No global seed.** `train()` never calls `tf.keras.utils.set_random_seed`,
`tf.random.set_seed`, or `np.random.seed`. The only seeding is local:
`train_test_split(random_state=seed)` at `ml/src/dataset.py:143` and `:151`, and
`ds.shuffle(seed=...)` at `:286`. Neither touches weight initialization, dropout
masks, or augmentation draws, so two runs of one config produce different
weights and different `metrics.json` (#80).

**Augmentation layers are constructed unseeded.** Every layer in
`build_augmentation_layer` (`ml/src/preprocess.py:87-127`) is built without a
`seed=` argument, so the augmented batches differ per run even once a global
seed is set (#80).

**A corrupt image crashes training at iteration time.** `_parse_image`
(`ml/src/dataset.py:254-260`) calls `tf.io.decode_image` with no error handling
and `scan_dataset` never opens the files it lists, so an undecodable file is
discovered only when the training loop reaches it — after the model is built and
some epochs may already have run (#25).

**Augmentation ranges silently drop their lower bound.** `build_augmentation_layer`
derives the Keras factor from the upper bound alone —
`factor = brightness[1] - 1.0` (`preprocess.py:102`) and
`factor = contrast[1] - 1.0` (`preprocess.py:109`) — while `RandomZoom` in the
same function correctly maps both. With the current `config.yaml` the ranges
happen to be symmetric (`[0.85, 1.15]`, `[0.9, 1.1]`), so **this is latent, not
live**: nothing is wrong in the realized distribution today. It becomes wrong the
moment anyone configures an asymmetric range, which is exactly what tuning
augmentation means (#81).

**A leakage test has been failing, unseen.** `ml/tests/` has never run: CI does
not invoke it (#28) and TensorFlow was absent from the development machine until
2026-08-01. Installing it revealed `test_no_sample_leakage_between_splits`
failing. The failure is real but the test is what is wrong. `create_splits`
groups by `f"{class_name}::{sid}"` (`ml/src/dataset.py:117`), while the test
compares bare `_extract_sample_id` stems, and its fixture names files
`sample_0 … sample_7` inside *every* class folder. Two files with the same stem
in different class folders are different physical samples — one soil sample has
one laboratory texture class, so it cannot appear in two folders — and the test
reports their appearance in different splits as a leak. Fifty-six other tests
pass.

Together these make experiment E0 unrunnable. E0 compares a real model against a
label-shuffled control and asks whether the difference exceeds run-to-run
variance. Without a seed there is no denominator: every difference is
attributable to noise, and no verdict can be reached
(`docs/architecture/soil-classification.md` §11).

## Design Decisions

### Seed once, at the entry point, and thread it into every stochastic layer

`tf.keras.utils.set_random_seed(cfg["data"]["seed"])` is called at the top of
`train()`, before any dataset or model is constructed. It seeds Python `random`,
NumPy, and TensorFlow in one call. Every augmentation layer additionally receives
`seed=cfg["data"]["seed"]`, because a Keras preprocessing layer holds its own
generator and a global seed alone does not make its draws reproducible across
runs of the same process.

`tf.config.experimental.enable_op_determinism()` is **not** enabled. It is the
obvious next step and it is deliberately declined: it forces deterministic GPU
kernels at a real throughput cost, and the free Kaggle and Colab tiers this
project trains on are exactly where that cost hurts. The seed plus per-layer
seeding gives run-to-run reproducibility on one machine, which is what E0 needs.
If a future comparison proves non-reproducible despite the seed, enabling op
determinism is a one-line change and this decision is where to revisit it.

### Validate the dataset before training, not during it

`scan_dataset` gains a verification pass that opens every listed file and
reports **all** unreadable ones at once, before the model is built.

This departs from #25's suggested approach, which asks for corrupt images to be
"logged and skipped with a warning". Skipping is rejected for two reasons. A
warning inside a long training log is not a report anybody reads, which makes it
silencing at scale. More importantly, a skipped file changes the effective
dataset without changing `splits.json`, so two runs of the same configuration
would train on different data and the reproducibility this spec exists to
establish would be false. In a dataset assembled from laboratory-labelled
samples, an unreadable file is a collection defect to fix, not a runtime
condition to tolerate.

The failure names every bad file, so one run tells the operator everything to
fix rather than one file per attempt.

### Both bounds of every augmentation range are honoured

Brightness and contrast map their configured lower and upper bounds, as
`RandomZoom` already does. The acceptance criteria below are stated as
**behavioural assertions over sampled outputs** rather than as a prescribed
Keras argument, so the implementation is free to use whatever the pinned
Keras 3.14.0 API provides and the test proves the realized distribution rather
than the call signature.

### Config validation covers what silently degrades a run

From #29, this spec takes only the validations that let a bad config produce a
plausible-looking but meaningless run:

- `image_size` must be 224 when `architecture` is `mobilenetv2`. Pretrained
  weights expect it, and any other value degrades transfer learning without
  erroring.
- `seed` must be a non-negative integer. A float or a negative silently changes
  seeding behaviour.
- Augmentation ranges must be two floats in ascending order. Today a single
  value or an inverted pair fails deep inside Keras with an `IndexError` that
  names nothing.
- `normalization` and `preprocessing.bake_into_model` must not both apply the
  same transformation. Today the combination is undefined and silent.
- `freeze_backbone` gets a declared default in `config.py` rather than an
  undeclared `.get("freeze_backbone", True)` at `model.py:51`.

The TFLite export threshold, also part of #29, is **not** in scope: it belongs
with the export parity gate, which needs real held-out images to be meaningful.

### The leakage test asserts the grouping key it is testing

`test_no_sample_leakage_between_splits` is corrected to compare the key
`create_splits` actually groups by, not a bare filename stem. It still fails on
a real leak; it stops failing on a fixture whose naming repeats across classes.

The alternative — dropping the class prefix from the group id so bare stems
become globally comparable — is **not** taken here. It presumes sample
identifiers are unique across the whole dataset, which is a collection
convention nobody has decided yet: an identifier could be a laboratory report
reference (globally unique) or a per-class counter (not). That decision belongs
to the dataset protocol spec, which is where the naming convention is fixed.
Deciding it here, inside a determinism fix, would settle a data-collection
question as a side effect of a test repair.

Whether the class prefix should survive that decision is therefore left open,
and #25's framing of it as a defect is recorded as questionable rather than
accepted: it describes "the same physical sample ID across class folders", a
situation the one-sample-one-class rule makes impossible except as a labelling
error.

### CI runs the Python tests

From #28, this spec takes only item 1: a workflow job that installs
`ml/requirements.txt` and runs `pytest ml/tests/`. Coverage tracking, release
signing, and ProGuard rules are unrelated to training determinism and are left
in #28. Signing and R8 keep rules were already addressed by SPEC 0004 and
SPEC 0015.

## Alternatives Considered

- **Enable `tf.config.experimental.enable_op_determinism()`** — declined for now,
  with the reasoning and the revisit condition stated above. Recorded rather than
  omitted because its absence is the first thing a reviewer will ask about.
- **Skip corrupt images with a warning, as #25 suggests** — rejected. It makes
  the effective dataset differ between runs of one configuration, which
  contradicts the purpose of this spec, and a warning in a training log is not a
  report.
- **Validate images inside `_parse_image`** — rejected. It is inside the tf.data
  graph, where raising names one file and aborts, and where the check would rerun
  every epoch. Validation belongs at scan time, once, before anything is built.
- **Fix the whole of #25 here** — rejected. Its other parts (nested files ignored
  by `scan_dataset`, the `_extract_sample_id` regex, and group ids that embed the
  class name so one physical sample can split across folders) are all about how
  samples are identified and grouped. That is the dataset protocol's subject and
  it is specified there, where the naming convention is decided, not here.
- **Fix the whole of #29 and #28 here** — rejected. Both are multi-part audit
  issues spanning unrelated subsystems. Taking them whole would mix an export
  parity gate and a release-signing change into a determinism fix.
- **Assert determinism by training twice end to end** — rejected as the primary
  criterion. There is no dataset, and a full double training run is a slow test
  to keep in a suite. The criteria below assert determinism at the three places
  randomness enters — initialization, dropout, augmentation — on synthetic
  inputs, which is faster, needs no data, and localizes a failure.

## Scope

- Includes:
  - `ml/src/train.py` — the global seed call at the entry point.
  - `ml/src/preprocess.py` — per-layer seeds; both bounds of brightness and
    contrast.
  - `ml/src/dataset.py` — a pre-training verification pass in `scan_dataset`.
  - `ml/src/config.py` — the five validations listed above.
  - `ml/src/model.py` — `freeze_backbone` reads its declared default.
  - `ml/tests/` — tests for each criterion below, and the corrected assertion in
    `test_no_sample_leakage_between_splits`.
  - `.github/workflows/ci.yml` — an `ml-tests` job.
- Does NOT include:
  - `enable_op_determinism()`.
  - The TFLite export parity threshold (#29 item 2) and anything in
    `ml/src/export.py`.
  - `scan_dataset` directory recursion, `_extract_sample_id`, and group-id
    composition (#25) — the dataset protocol spec owns these, including whether
    the class prefix survives.
  - Coverage tracking, release signing, ProGuard rules (#28 items 2-5).
  - Any change under `lib/`, any Dart file, any database or UI surface.
  - Training a model, or any change to the architecture, loss, or metrics.

## Acceptance Criteria

- seed_is_set_before_anything_is_built: `train()` calls
  `tf.keras.utils.set_random_seed` with the configured seed before the first
  dataset or model is constructed, asserted by patching the call and recording
  ordering.
- model_init_is_reproducible: building the model twice, each preceded by seeding
  from the same config, yields element-wise identical initial weights.
- dropout_is_reproducible: two forward passes in training mode over one fixed
  input, each preceded by seeding, produce identical outputs.
- augmentation_is_reproducible: the augmented pipeline over a fixed synthetic
  batch produces element-wise identical tensors across two seeded runs.
- augmentation_differs_across_seeds: the same pipeline under two different seeds
  produces different tensors, proving the previous criterion is testing seeding
  and not an accidentally disabled augmentation.
- brightness_honours_both_bounds: with `brightness_range: [0.7, 1.15]`, sampled
  outputs over many draws span the asymmetric configured range, and their
  extremes do not match those produced by a symmetric `[0.85, 1.15]`.
- contrast_honours_both_bounds: the same assertion for `contrast_range`.
- symmetric_ranges_are_unchanged: with the current `config.yaml` values the
  realized distribution is identical to today's, so this fix is proven latent
  rather than behaviour-changing.
- corrupt_image_fails_before_training: a directory containing one truncated file
  raises from `scan_dataset` naming that file, and the failure happens before any
  model is built.
- every_bad_file_is_named: a directory with three unreadable files raises once,
  naming all three, rather than failing on the first.
- valid_dataset_scans_clean: a directory of readable images scans without error
  and returns every file.
- image_size_is_validated_against_architecture: `image_size: 128` with
  `architecture: mobilenetv2` raises from `load_config` naming both keys.
- seed_is_validated: a negative seed and a float seed each raise from
  `load_config`.
- augmentation_ranges_are_validated: a single-element range and an inverted range
  each raise from `load_config` naming the offending key.
- normalization_conflict_is_detected: `normalization: imagenet` together with
  `bake_into_model: true` raises from `load_config`.
- freeze_backbone_default_is_declared: the default lives in `config.py` and
  `model.py` reads it from the validated config rather than supplying its own.
- leakage_test_compares_the_grouping_key:
  `test_no_sample_leakage_between_splits` compares the key `create_splits`
  groups by, and passes against the existing fixture.
- leakage_test_still_catches_a_real_leak: a fixture where one group's photos are
  forced into two splits makes that test fail, proving the correction did not
  weaken it into always passing.
- existing_ml_tests_pass: the other 56 tests under `ml/tests/` pass unchanged.
- ci_runs_ml_tests: the workflow has a job that installs
  `ml/requirements.txt` and runs `pytest ml/tests/`, and it is required for the
  build job in the same way `analyze` and `test` are.
- analyze_clean_tests_green: `flutter analyze` reports no issues, `flutter test`
  passes, and `python -m pytest ml/tests/ -v` passes.

## Reproducibility

- Toolchain: Flutter 3.44.1 / Dart 3.12.1 for the unchanged Dart suite; Python
  with the pins in `ml/requirements.txt`, notably `tensorflow==2.21.0` and
  `keras==3.14.0`.
- TensorFlow 2.21.0 and Keras 3.14.0 are installed in `ml/.venv` as of
  2026-08-01. Before that the environment held only NumPy, Pillow and pytest,
  and the existing `ml/tests/` files could not even be collected — which is how
  a failing leakage test went unseen.
- oneDNN is enabled by default in this TensorFlow build and warns that operation
  ordering can change floating-point results. It is a warning about numerical
  reproducibility across builds, not within one; the determinism criteria below
  compare two runs in one process, where it does not apply. If a criterion ever
  fails intermittently, `TF_ENABLE_ONEDNN_OPTS=0` is the first thing to try
  before reaching for `enable_op_determinism()`.
- Every criterion is verified against synthetic tensors and temporary
  directories. No dataset and no trained model is required.
- Verify: `cd ml && python -m pytest tests/ -v`.
- Determinism criteria assert equality across two runs in one process. Equality
  across machines and across TensorFlow versions is explicitly not claimed.

## Risks and Assumptions

- Assumption: `tf.keras.utils.set_random_seed` plus per-layer seeds is sufficient
  for run-to-run reproducibility on one machine with the pinned versions. What
  would invalidate it: a determinism criterion failing intermittently, which
  would mean a nondeterministic kernel is involved and `enable_op_determinism()`
  is needed after all. The criteria are written to fail loudly in that case
  rather than to be retried.
- Assumption: the Keras 3.14.0 preprocessing layers accept an asymmetric range
  for brightness and contrast. Not verified against a running TensorFlow, which
  is why the criteria assert sampled behaviour rather than a call signature. If
  the API only accepts a symmetric factor, the fix becomes an explicit shift plus
  a symmetric draw, and the behavioural criteria still hold unchanged.
- Risk: the CI job adds a TensorFlow install to every push, which is a multi-
  minute download. Mitigated by pip caching keyed on `ml/requirements.txt`. If it
  proves too slow, running the job only on changes under `ml/` is the fallback,
  at the cost of missing a cross-cutting break.
- Risk: making `scan_dataset` fail on a corrupt file will block a training run
  that used to start. That is the intent. The mitigation is that it names every
  bad file at once, so the fix is one pass rather than one file per attempt.
