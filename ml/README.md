# VisioSoil ML Pipeline

Reproducible TensorFlow/Keras pipeline for training, evaluating, and exporting the soil texture classifier used in the VisioSoil mobile app.

## Classes

| # | Class | Folder |
|---|-------|--------|
| 0 | Arenosa | `data/raw/Arenosa/` |
| 1 | Media | `data/raw/Media/` |
| 2 | Siltosa | `data/raw/Siltosa/` |
| 3 | Muito Argilosa | `data/raw/Muito_Argilosa/` |
| 4 | Argilosa | `data/raw/Argilosa/` |

## Setup

```bash
cd ml
make setup
```

This creates a `.venv/` virtual environment and installs dependencies from `requirements.txt`.

## Dataset

Place images in `data/raw/<ClassName>/` following the folder structure above. Supported formats: `.jpg`, `.jpeg`, `.png`, `.bmp`, `.webp`.

The pipeline creates stratified train/val/test splits automatically and saves the manifest to `data/splits/splits.json` (versioned in git for reproducibility).

## Training

```bash
make train VERSION=v1
```

Or run the full pipeline (train + evaluate + export):

```bash
make pipeline VERSION=v1
```

### Configuration

All hyperparameters, class names, preprocessing settings, and augmentation options are defined in `config.yaml` — the single source of truth for the pipeline.

## Evaluation

```bash
make evaluate VERSION=v1
```

Generates `models/v1/metrics.json` with accuracy, F1 scores, per-class metrics, and `models/v1/confusion_matrix.png`.

## Export to TFLite

```bash
make export VERSION=v1
```

Converts the Keras model to TFLite with dynamic range quantization (configurable) and generates `models/v1/spec.json` — the integration contract consumed by the Flutter `InferenceService`.

## Deploy to App

```bash
make deploy VERSION=v1
```

Copies `model.tflite` and `spec.json` to `assets/models/` in the Flutter project root.

## Tests

```bash
make test
```

Tests cover:
- Config loading and validation
- Preprocessing (shape, dtype, value range)
- Model output (shape, probability sum, non-negative)
- TFLite export (loads, runs, Keras parity, spec.json contract)

## Architecture

- **Model:** SqueezeNet 1.1 (custom Keras implementation, ~750K params). MobileNetV2 available as fallback via `config.yaml`.
- **Preprocessing:** ImageNet normalization `(pixel/255 - mean) / std` per channel.
- **Augmentation:** Random flip, rotation, brightness, zoom (Keras layers).
- **Quantization:** Dynamic range (default), float16, or none.
- **Versioning:** Each version produces artifacts in `models/vN/` with metrics, config snapshot, and changelog.

## Artifacts per Version

```
models/v1/
├── model.tflite       # Deployable TFLite model (versioned)
├── model.h5           # Keras checkpoint (gitignored)
├── spec.json          # Input/output contract for InferenceService
├── metrics.json       # Accuracy, F1, per-class metrics
├── config.json        # Snapshot of config.yaml used for training
├── confusion_matrix.png
└── CHANGELOG.md
```
