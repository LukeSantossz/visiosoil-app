# SPEC: fix(ml): keep the backbone's BatchNorm layers in inference mode when phase two unfreezes it

## Problem

Phase two of fine-tuning unfreezes the top of the MobileNetV2 backbone without returning its BatchNormalization layers to inference mode, so every `fit` call overwrites the ImageNet moving statistics with statistics estimated from 221 photographs taken on one rig, under one device and one lighting condition — silently, and before any arm of E0 has been trained (#179).

## Design Decision

`unfreeze_model` sets every BatchNormalization layer **inside the backbone** back to `trainable = False` after computing which layers to unfreeze. This is Keras' own documented remedy for a partially unfrozen pretrained backbone, it does not change the layer count `model.unfreeze_layers` declares, and it is directly assertable. The classification head's own BatchNormalization layer is deliberately untouched: it was initialized on this dataset and has no pretrained statistics to protect, so freezing it would be a different and over-broad change.

The fix is three lines, so the decision worth recording is the second half: **what unfreezing actually did is written into each fold's artifacts, as `fine_tune.json`.** #179's third acceptance criterion asked for the trainable parameter count in `metrics.json`. That file changed owner in SPEC 0042 — `metrics.json` is now an arm-level report assembled by `src.evaluate` from stored predictions, and it never sees a model — so the criterion is satisfied in the artifact that does describe one training run: the per-fold directory that already carries `config.json`, `runtime.json`, `selection_audit.json` and `cost.json`. The record is counted off the refit model rather than restated from the config, because the config states the intent and this states the outcome, and the two agree only while `unfreeze_model` is correct.

`load_fine_tune` returns `None` for a fold produced before this record existed, for the same reason `load_runtime` does: absent is not the same as a backbone whose statistics were protected, and a comparison across folds has to be able to tell them apart rather than assuming the safe value.

## Alternatives Considered

- **Leave the BatchNormalization layers trainable and lower `fine_tune_learning_rate`.** Rejected, and it is the intuitive fix that does not work: the moving mean and variance are updated by the forward pass, not by the optimizer, so no learning rate governs them. This is recorded because the wrong remedy is cheaper to reach for than the right one.
- **Reduce `model.unfreeze_layers` so the tail contains no BatchNormalization layer.** Rejected. With `unfreeze_layers: 50` there are seventeen of them inside the tail, and MobileNetV2 interleaves them throughout, so no useful tail avoids them. It also makes the config number mean something other than what it says.
- **Freeze every BatchNormalization layer in the whole model, head included.** Rejected. The head's layer has no pretrained statistics to destroy, it was created for this dataset, and freezing it removes a normalization the head was compiled with for no stated benefit.
- **Record the trainable parameter count in `metrics.json` as #179 asked.** Rejected as written, and the reasoning is in the Design Decision: after SPEC 0042 that file is assembled without a model in scope, so satisfying the criterion literally would mean either importing the training stack into the reporting path — which SPEC 0042 deliberately kept out of it — or restating a number from the config, which would record the intent a second time and never catch a divergence.
- **Assert the fix in a comment and skip the artifact.** Rejected. A comment is invisible in a stored result. The whole point of #179 is that the damage was silent, and a record that lives only in the code cannot tell a reader of `models/v1/cnn/repeat-3/fold-2/` what that fold trained under.

## Scope

- Includes:
  - `ml/src/model.py` — freeze backbone BatchNormalization layers in `unfreeze_model`; extract `_find_backbone`; add `fine_tune_report`.
  - `ml/src/crossval.py` — `FINE_TUNE_FILENAME` and `load_fine_tune`, beside the rest of the fold artifact layout, so reading a stored result never reaches the training stack.
  - `ml/src/train.py` — write `fine_tune.json` from the refit model, before it is saved.
  - `ml/tests/test_model_output.py` — the layer-level and report-level assertions.
  - `ml/tests/test_determinism.py` — the wiring assertion, that a fold writes the record and writes it for the refit model.
- Does NOT include:
  - Any change to which layers are unfrozen, or to `model.unfreeze_layers`.
  - The head's BatchNormalization layer.
  - Reading `fine_tune.json` in any report. It is written and loadable; nothing consumes it yet, and the consumer is E0's verdict (SPEC 0044).
  - Backfilling the record for folds produced before this change. There are none — no model has ever been trained on real data — and `load_fine_tune` returns `None` rather than inventing one.
  - Any change under `lib/`.

## Acceptance Criteria

- unfreeze_leaves_no_backbone_batch_norm_trainable: after `unfreeze_model`, no BatchNormalization layer inside the backbone is trainable, asserted over the layers themselves and not over a count.
- the_backbone_carries_batch_norm_layers_to_freeze: the assertion above is not vacuous — the backbone contains at least one BatchNormalization layer.
- unfreeze_leaves_the_head_batch_norm_trainable: the BatchNormalization layer `build_model` places in the classification head is still trainable afterwards.
- unfreeze_keeps_the_declared_layer_count: every non-BatchNormalization layer in the last `model.unfreeze_layers` of the backbone is trainable, and no layer before that tail is.
- fine_tune_report_counts_the_model_not_the_config: the report's trainable and non-trainable parameter counts sum to `model.count_params()`, its trainable count rises after unfreezing, and its trainable BatchNormalization count is zero.
- fine_tune_report_records_a_backbone_that_never_unfroze: `backbone_unfrozen` is `False` for a model whose phase two never ran, which is a real outcome of nested epoch selection and not an error.
- train_fold_writes_the_record_for_the_refit_model: the fold directory carries `fine_tune.json`, taken from the model that produced the fold's predictions and written before that model is saved.
- load_fine_tune_reports_absence_rather_than_the_safe_value: a fold directory with no such file loads as `None`.

## Reproducibility

```sh
cd ml
python -m pytest tests/test_model_output.py tests/test_determinism.py -v
```

Both modules are gated on TensorFlow being importable. The pinned stack is `tensorflow==2.21.0` on Python 3.12 (`ml/requirements.txt`), which the CI `ml-tests` job installs; **the criteria above are therefore verified in CI and skipped on a developer machine without that stack**, which is the case this repository is developed on. No seed is involved: every assertion is over layer flags and parameter counts, which are deterministic given the architecture.

## Risks and Assumptions

- **Assumption: `keras.layers.BatchNormalization` is the type MobileNetV2's normalization layers are instances of** under the pinned Keras. If a future Keras changes the class, the anti-vacuity criterion above fails rather than the fix silently doing nothing — which is why that criterion exists.
- **Assumption: no trained artifact has to be re-produced.** No model has ever been trained on real data in this repository, so there is no stored result whose statistics this change invalidates. Had there been, every one would need rerunning, and the assumption is stated here so a future reader can check it rather than infer it.
- **Risk: the fix is verified only in CI.** The two modules skip wherever TensorFlow is absent, which is every local machine here. That is a property of the environment (A1, #214) and not of this change, and it is the reason the red state of these tests was observed in CI rather than claimed locally.
- **What would invalidate this spec:** a decision to stop fine-tuning at all, or a move away from a pretrained backbone — which is exactly what SPEC 0044's descriptor arm would mean if it wins, in which case `unfreeze_model` has no caller and this record retires with it.
