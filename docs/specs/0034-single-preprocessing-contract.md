# SPEC (full): fix(ml): accept only the preprocessing contract the model graph implements

## Problem

`load_config` accepts `preprocessing.normalization: imagenet`, but `build_model`
applies a `Rescaling(2.0, -1.0)` layer unconditionally and never reads
`preprocessing.bake_into_model`, so that configuration trains a model on input
its backbone was never trained on, and no error is raised.

## Design Decision

The pipeline supports exactly one preprocessing contract, so validation will say
so: `imagenet` is removed from `_VALID_NORMALIZATIONS` and `mobilenet_v2`
becomes the only accepted value. The unreachable code that existed to serve the
removed value is removed with it — `normalize_imagenet`, the `imagenet` branch
of `preprocess`, and the `imagenet` branch of `_build_spec` — rather than left
in place as an untested path that looks supported. The silent fallback in
`_build_spec`, which writes an undefined normalization method into `spec.json`
for any combination the accepted set does not cover, is replaced by a raise, on
the same reasoning SPEC 0032 used: a silent fallback is how a train/serve skew
survives review.

`build_model` keeps the unconditional `Rescaling` layer. The graph is not the
part that is wrong; the claim that a second contract exists is.

## Alternatives Considered

**Make the rescaling conditional (issue #167, Option A).** `build_model` reads
`bake_into_model` and adds the `Rescaling` layer only when it is true, which
makes `imagenet` work as documented. Rejected for now: it adds a model code path
that no end-to-end test exercises and no trained artifact has ever used, and it
makes the exported graph depend on a configuration flag, which is one more way
for the graph and `spec.json` to disagree. This becomes the right change the
moment the architecture sweep (`docs/architecture/ml-implementation-map.md`, C1)
adopts a backbone whose pretrained weights expect ImageNet normalization; making
it before the sweep is guessing at which second contract will be needed.

**Detect the conflict instead of removing the value.** Keep `imagenet` accepted
and have `load_config` reject it only when combined with a baked graph — the
shape SPEC 0032 already used for `mobilenet_v2` with `bake_into_model: false`.
Rejected: there is no conflict between two settings here, because
`bake_into_model` is never read by the code that would honour it. A conflict
rule would describe a relationship the code does not have, and would still leave
`imagenet` rejected in every case the pipeline can actually produce, which is
the same outcome reached by a longer route.

**Keep `normalize_imagenet` as documented dead code.** Leave the helper and its
tests in place with a comment saying it is unused, so Option A is cheaper later.
Rejected: an exported symbol with passing tests reads as supported, and the
project already carries one instance of that trap (a label list in six copies
with nothing asserting they agree). Git history restores the function in one
command if C1 needs it.

## Scope

- Includes:
  - `ml/src/config.py` — `_VALID_NORMALIZATIONS` becomes `{"mobilenet_v2"}`; the
    branch requiring `mean` and `std` for `imagenet` is removed; the rejection
    message names the accepted value and the reason.
  - `ml/src/preprocess.py` — `normalize_imagenet` and the `imagenet` branch of
    `preprocess` are removed. The `ValueError` on an unknown normalization stays.
  - `ml/src/export.py` — `_build_spec` loses the `imagenet` branch, and its
    fallback `else` raises instead of emitting an undeclared method.
  - `ml/tests/test_config.py` — `test_imagenet_normalization_requires_mean_std`
    and `test_imagenet_normalization_with_mean_std` are replaced by a test that
    asserts the rejection, with the reason recorded in the test docstring.
  - `ml/tests/test_preprocess.py` — the `imagenet` fixture and its three tests
    are removed.
  - New tests asserting the model graph and `spec.json` agree, by inspecting the
    built model rather than the configuration.
  - `ml/README.md` — line 124 states `mobilenet_v2` is the only accepted value.
- Does NOT include:
  - Making the `Rescaling` layer conditional on `bake_into_model` (Option A).
  - Adding a second backbone, a second preprocessing contract, or any change to
    the values in `ml/config.yaml`.
  - The Dart side of the runtime contract — `spec.json` consumption in
    `InferenceService` is A4 and issue #79.
  - The export parity gate on a real test set, checkpoint selection, and single
    model path resolution — those are B3, issues #29 (export half) and #30.
  - Changing what `_build_spec` emits for the accepted configuration. The
    `divide_255` contract stays exactly as it is today.

## Acceptance Criteria

- `load_config_rejects_imagenet_normalization`: a config with
  `preprocessing.normalization: imagenet`, with or without `mean` and `std`,
  raises `ValueError`.
- `load_config_rejection_message_names_the_accepted_value`: the raised message
  contains `mobilenet_v2`, so the operator learns the accepted value from the
  failure rather than from the source.
- `load_config_accepts_mobilenet_v2_with_bake_into_model_true`: the existing
  accepted configuration still loads (regression guard).
- `load_config_rejects_mobilenet_v2_without_bake_into_model`: SPEC 0032's rule
  survives this change (regression guard).
- `built_model_contains_rescaling_layer`: `build_model` produces a model with a
  layer named `rescaling`, asserted by walking `model.layers`, not by reading
  the config.
- `built_model_rescaling_maps_unit_range_to_signed_unit_range`: that layer's
  `scale` is `2.0` and its `offset` is `-1.0`, so the graph implements the
  contract `spec.json` declares.
- `spec_declares_divide_255_for_every_accepted_config`: for every configuration
  `load_config` accepts, `_build_spec` returns
  `input.normalization.method == "divide_255"`. The accepted set has one member
  today; the test enumerates it from `_VALID_NORMALIZATIONS` so that adding a
  value without revisiting the export fails here.
- `build_spec_raises_on_a_contract_the_graph_does_not_implement`: `_build_spec`
  called with `mobilenet_v2` and `bake_into_model: false` raises `ValueError`
  instead of returning a spec.
- `preprocess_raises_on_unknown_normalization`: the behaviour is unchanged for
  an unrecognised value.
- `no_imagenet_normalization_symbol_remains_in_ml_src`: `normalize_imagenet` is
  not importable from `ml.src.preprocess`.
- `python -m pytest ml/tests/ -v` passes, and the `ml-tests` CI job is green.

## Reproducibility

```bash
python -m pytest ml/tests/ -v
```

No randomness is involved in any criterion above: every test builds a config
dictionary or a Keras model and inspects it. `build_model` downloads ImageNet
weights on first use, which is a network dependency of the existing test suite,
not one this spec adds. Versions: Python 3.11, TensorFlow as pinned in
`ml/requirements.txt`.

## Risks and Assumptions

- Assumption: no trained artifact was produced with `normalization: imagenet`.
  `ml/config.yaml` uses `mobilenet_v2`, and `ml/models/v1` and `v2` hold only
  `.gitkeep`, so there is nothing to invalidate. A model trained elsewhere with
  `imagenet` would be unreproducible after this change — it already is, since
  such a model would have been trained through the unconditional `Rescaling`
  and does not match its own declared preprocessing.
- Assumption: the ROI and resize half of preprocessing is out of reach here.
  `preprocess` resizes without a centred square crop, which the map records as a
  defect against A4; this spec touches only the normalization branch.
- What invalidates this spec: C1 adopting a backbone whose pretrained weights
  expect ImageNet normalization. At that point Option A is the correct change
  and this decision is reversed deliberately, with a second contract that has an
  end-to-end test behind it.
- Risk: removing a public helper is a breaking change for any caller outside
  this repository. There is none — `ml/` is not published as a package.
