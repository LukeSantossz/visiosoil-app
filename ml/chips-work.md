# Chip Huyen — Principles Applied in VisioSoil ML Pipeline

> References:
> - **DMLS** — *Designing Machine Learning Systems* (O'Reilly, 2022)
> - **AIE** — *AI Engineering* (O'Reilly, 2025)
>
> This document maps each principle to where it was applied in the `ml/` pipeline, how it manifests in code, and why it matters for this project specifically.

---

## 1. Start Simple, Iterate

**Source:** DMLS Ch. 6 — Model Development & Training

> "The simplest model that solves the problem is the best starting point. Complexity should be added incrementally, justified by evidence."

### Where

- `src/model.py` — `_build_squeezenet_backbone()` and `build_model()`
- `config.yaml` — `model.architecture: "squeezenet"`

### How

SqueezeNet 1.1 (~750K parameters) was chosen as the baseline architecture. It is implemented directly in Keras via fire modules (Iandola et al. 2016), with no pretrained weights — training from scratch on the soil dataset. MobileNetV2 (4M+ params, ImageNet pretrained) exists as a fallback controlled by a single config field, but it is not the default.

```yaml
# config.yaml
model:
  architecture: "squeezenet"   # swap to "mobilenetv2" only if SqueezeNet underperforms
```

```python
# src/model.py — build_model()
if architecture == "squeezenet":
    features = _build_squeezenet_backbone(inputs)
elif architecture == "mobilenetv2":
    backbone = keras.applications.MobileNetV2(...)
```

### Why (project context)

VisioSoil runs inference on-device via TFLite in a Dart isolate (`lib/core/services/inference_service.dart`). Model size directly impacts APK size and inference latency on mid-range Android devices. Starting with a 750K-param model gives a deployable baseline fast. If accuracy is insufficient after real data evaluation, switching to MobileNetV2 is a one-line config change — not a code rewrite.

---

## 2. Configuration as Single Source of Truth

**Source:** DMLS Ch. 10 — Infrastructure and Tooling; AIE Ch. 7 — Engineering Fundamentals

> "All experiment parameters should live in a config file, not scattered across scripts. Reproducibility requires knowing exactly what ran."

### Where

- `config.yaml` — central config (classes, hyperparams, normalization, augmentation, export)
- `src/config.py` — `load_config()`, `_validate()`, `resolve_paths()`
- `models/v1/config.json` — snapshot saved at training time by `src/train.py`

### How

Every module in the pipeline reads from `config.yaml` via `load_config()`. No module hardcodes hyperparameters, class names, or preprocessing values. At the start of each training run, `train.py` saves a `config.json` snapshot into `models/vN/`, creating a permanent record of the exact settings used.

```python
# src/train.py — train()
cfg = load_config(config_path)
cfg = resolve_paths(cfg)

# Save config snapshot alongside model artifacts
with open(output_dir / "config.json", "w") as f:
    json.dump(cfg, f, indent=2)
```

The config is validated at load time with strict schema checks (`_validate()`), catching errors like invalid architectures, split ratios that sum to >= 1, or missing keys before any training starts.

### Why (project context)

The soil classifier will iterate through multiple versions as the dataset grows (starting with 5 classes, potentially expanding). Without centralized config, each version would require auditing scattered constants across 7+ files to understand what changed. With `config.yaml` + `config.json` snapshots, any `models/vN/` directory is self-documenting: open `config.json` to see exact classes, learning rate, augmentation, and normalization used.

---

## 3. Train Set Statistics for Normalization

**Source:** DMLS Ch. 5 — Feature Engineering

> "Normalization statistics must come from the training set only. Using validation or test data leaks information about the evaluation distribution into the model."

### Where

- `config.yaml` — `preprocessing.mean` and `preprocessing.std`
- `src/preprocess.py` — `normalize_imagenet()`
- `src/export.py` — `_build_spec()` embeds normalization into `spec.json`
- `spec.json` — consumed by Flutter `InferenceService` at inference time

### How

ImageNet mean `[0.485, 0.456, 0.406]` and std `[0.229, 0.224, 0.225]` are used as the normalization reference. These are pre-computed statistics from the ImageNet training set — a standard practice for transfer learning pipelines. They are declared once in `config.yaml` and flow through the entire pipeline:

```
config.yaml → preprocess.py (training) → spec.json (export) → InferenceService (Flutter app)
```

```python
# src/preprocess.py — normalize_imagenet()
image = tf.cast(image, tf.float32) / 255.0
mean_t = tf.constant(mean, dtype=tf.float32)
std_t = tf.constant(std, dtype=tf.float32)
return (image - mean_t) / std_t
```

```json
// spec.json — contract for InferenceService
"normalization": {
  "method": "imagenet",
  "mean": [0.485, 0.456, 0.406],
  "std": [0.229, 0.224, 0.225]
}
```

### Why (project context)

The VisioSoil `InferenceService` runs in a Dart isolate with no access to the Python pipeline. If normalization values were computed dynamically or left undocumented, the Dart side would have no way to replicate the exact preprocessing. `spec.json` makes the contract explicit: TASK-001 (InferenceService integration) will read `mean` and `std` directly from this file, ensuring train-time and inference-time normalization are identical.

---

## 4. Stratified Data Splits with Versioned Manifests

**Source:** DMLS Ch. 5 — Training Data; DMLS Ch. 6 — Model Development

> "Splits must be stratified when class distribution is imbalanced. Splits must be fixed and versioned for reproducibility."

### Where

- `src/dataset.py` — `create_splits()`, `load_splits()`
- `data/splits/splits.json` — manifest file (versioned in git)

### How

`create_splits()` uses `sklearn.train_test_split` with `stratify=all_labels` to preserve class proportions across train/val/test. The manifest is saved as `splits.json` with full metadata: seed, class mapping, counts, and per-sample path/label pairs. Subsequent runs call `load_splits()` to reuse the same split.

```python
# src/dataset.py — create_splits()
train_val_paths, test_paths, train_val_labels, test_labels = train_test_split(
    all_paths, all_labels,
    test_size=test_split,
    stratify=all_labels,       # preserves class proportions
    random_state=seed,         # deterministic
)
```

The split manifest is committed to git (`data/splits/` is not gitignored), while raw images are gitignored. This means the exact sample allocation is reproducible even if the pipeline runs on a different machine with the same dataset.

### Why (project context)

Soil texture classes will likely be imbalanced in practice — "Media" samples may outnumber "Siltosa" 10:1 depending on the collection region. Without stratification, a random split could put zero "Siltosa" samples in the test set, making evaluation meaningless. Versioning the manifest in git ensures that when `models/v2/metrics.json` reports 85% accuracy, anyone can verify it was evaluated on the exact same test set as `v1`.

---

## 5. Artifact Versioning Alongside Code

**Source:** DMLS Ch. 10 — Infrastructure and Tooling; AIE Ch. 7 — Engineering Fundamentals

> "Model artifacts should be traceable to the code and config that produced them. Version models, not just code."

### Where

- `models/v1/` — versioned directory per model generation
- Files per version: `model.tflite`, `spec.json`, `metrics.json`, `config.json`, `confusion_matrix.png`, `CHANGELOG.md`
- `models/**/model.h5` — gitignored (Keras checkpoint, too large for git)

### How

Each training run targets a version directory (`models/vN/`). The pipeline saves:

| File | Purpose | Versioned in git? |
|------|---------|-------------------|
| `model.tflite` | Deployable artifact | Yes |
| `spec.json` | Integration contract | Yes |
| `metrics.json` | Evaluation results | Yes |
| `config.json` | Config snapshot | Yes |
| `confusion_matrix.png` | Visual evaluation | Yes |
| `CHANGELOG.md` | Human-readable history | Yes |
| `model.h5` | Keras checkpoint | No (gitignored) |

```makefile
# Makefile
VERSION ?= v1
train:
	$(PYTHON) -m src.train --version $(VERSION)
```

### Why (project context)

VisioSoil chose JSON-based local tracking over MLflow or W&B deliberately. The project has one model, one pipeline, one developer. An experiment tracking server would add infrastructure overhead disproportionate to the value. But traceability is non-negotiable: when `assets/models/soil_classifier.tflite` is deployed to the app, it must be possible to answer "what config, what data split, and what accuracy produced this?" by inspecting `models/vN/`.

The decision to gitignore `.h5` but version `.tflite` reflects a practical trade-off: `.h5` files are 3-10MB (Keras full checkpoint with optimizer state), while `.tflite` files are 0.5-2MB (quantized, inference-only). Git handles the latter well; for the former, the pipeline can regenerate from code + config + data.

---

## 6. Interface Contract Between Pipeline and Serving

**Source:** AIE Ch. 9 — AI Engineering Architecture

> "The ML pipeline and the serving layer should communicate through a well-defined interface, not implicit assumptions."

### Where

- `src/export.py` — `_build_spec()` generates `spec.json`
- `models/v1/spec.json` — the contract file
- `scripts/deploy_to_app.sh` — copies both `.tflite` and `spec.json` to Flutter assets

### How

`spec.json` defines every assumption the Flutter app needs to run inference:

```json
{
  "version": "v1",
  "input": {
    "shape": [1, 224, 224, 3],
    "dtype": "float32",
    "normalization": {
      "method": "imagenet",
      "mean": [0.485, 0.456, 0.406],
      "std": [0.229, 0.224, 0.225]
    }
  },
  "output": {
    "shape": [1, 5],
    "dtype": "float32",
    "type": "probabilities"
  },
  "classes": ["Arenosa", "Media", "Siltosa", "Muito Argilosa", "Argilosa"]
}
```

The deploy script copies both files together — you cannot deploy a model without its spec:

```bash
# scripts/deploy_to_app.sh
cp "$TFLITE_SRC" "${ASSETS_DIR}/soil_classifier.tflite"
cp "$SPEC_SRC" "${ASSETS_DIR}/spec.json"
```

### Why (project context)

The current `InferenceService` (Dart) hardcodes 12 USDA texture class labels and no normalization. When TASK-001 integrates the real model, it needs to know: input size, normalization method, output interpretation, and class labels. Without `spec.json`, any change to the Python pipeline (e.g., adding a 6th class, switching normalization) would require manually updating the Dart code — a source of silent bugs. With the contract, the `InferenceService` can read `spec.json` at startup and adapt automatically.

This decoupling means the ML team can retrain and ship `v2` without touching any Flutter code, as long as the spec schema is respected.

---

## 7. Testing ML Systems in Layers

**Source:** DMLS Ch. 10 — Testing and Monitoring; AIE Ch. 8 — Dataset Engineering

> "ML systems need tests at every layer: data validation, model behavior, and infrastructure correctness. Unit tests alone are insufficient."

### Where

- `tests/test_config.py` — config layer (9 tests)
- `tests/test_preprocess.py` — data layer (8 tests)
- `tests/test_model_output.py` — model layer (7 tests)
- `tests/test_tflite_inference.py` — infrastructure/export layer (7 tests)

### How

Each test file targets a different concern:

**Config layer** — Does the system reject invalid inputs before training starts?
```python
# tests/test_config.py
def test_splits_sum_too_large(valid_config):
    valid_config["data"]["val_split"] = 0.5
    valid_config["data"]["test_split"] = 0.5
    with pytest.raises(ValueError, match="val_split.*test_split"):
        load_config(path)
```

**Data layer** — Do preprocessed images have the correct shape, dtype, and value range?
```python
# tests/test_preprocess.py
def test_normalize_output_range(sample_image):
    normalized = normalize_imagenet(sample_image, mean, std)
    values = normalized.numpy()
    assert values.min() >= -3.0
    assert values.max() <= 3.0
```

**Model layer** — Does the model produce valid probability distributions?
```python
# tests/test_model_output.py
def test_output_probabilities_sum(squeezenet_model):
    output = squeezenet_model.predict(dummy, verbose=0)
    sums = np.sum(output, axis=1)
    np.testing.assert_allclose(sums, 1.0, atol=1e-5)
```

**Infrastructure layer** — Does the TFLite export preserve model behavior?
```python
# tests/test_tflite_inference.py
def test_tflite_keras_parity(model_and_tflite):
    # Keras and TFLite outputs should match within tolerance
    np.testing.assert_allclose(keras_out, tflite_out, atol=1e-4)
```

### Why (project context)

VisioSoil's inference runs entirely on-device. There is no server to catch errors, no fallback API, no human in the loop. If preprocessing produces wrong value ranges, the model outputs garbage silently. If TFLite conversion breaks parity with Keras, the app shows confident but wrong predictions. Layered tests catch these failures before they reach the user's phone.

The `test_tflite_keras_parity` test is particularly important: TFLite quantization can introduce numerical drift. The test verifies that the exported model produces the same output as the Keras original within a tight tolerance, catching conversion bugs before deployment.

---

## Principles Consciously Not Applied

These principles from Chip Huyen's works were evaluated and deliberately deferred:

| Principle | Source | Why not applied |
|-----------|--------|-----------------|
| Feature store | DMLS Ch. 7 | Single dataset, no feature sharing across models |
| Online evaluation / A/B testing | DMLS Ch. 9 | App is offline-first, no server to run experiments |
| Continual learning | DMLS Ch. 9 | No production model or user feedback loop yet |
| Data distribution monitoring | DMLS Ch. 8 | No production inference to monitor |
| Model compression (pruning/distillation) | DMLS Ch. 7 | SqueezeNet is already small; optimize only if latency is measured as a problem |
| Experiment tracking server (MLflow/W&B) | DMLS Ch. 10, AIE Ch. 7 | Overhead disproportional for single-model, single-developer project; JSON local is sufficient |

These are not rejected — they are deferred until the project scale justifies them. The architecture (versioned `models/vN/`, `spec.json` contract, `config.yaml` as source of truth) is designed to accommodate these additions without structural changes.
