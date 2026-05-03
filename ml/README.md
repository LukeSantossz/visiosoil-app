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

### 1. Create virtual environment

```bash
cd ml
python -m venv .venv
```

### 2. Activate the virtual environment

**Windows (PowerShell):**

```powershell
.venv\Scripts\activate
```

**macOS / Linux:**

```bash
source .venv/bin/activate
```

### 3. Install dependencies

```bash
pip install --upgrade pip
pip install -r requirements.txt
```

Key dependencies: `tensorflow==2.21.0`, `tf-keras==2.21.0`, `keras==3.14.0`. See `requirements.txt` for the full list.

## Dataset

Place images in `data/raw/<ClassName>/` following the folder structure above. Supported formats: `.jpg`, `.jpeg`, `.png`, `.bmp`, `.webp`.

The pipeline creates stratified train/val/test splits automatically and saves the manifest to `data/splits/splits.json` (versioned in git for reproducibility).

## Training

```bash
python -m src.train --version v1
```

Saves the Keras checkpoint (`model.h5`), config snapshot (`config.json`), and training history (`history.json`) to `models/v1/`.

## Evaluation

```bash
python -m src.evaluate --version v1
```

Generates `models/v1/metrics.json` with accuracy, F1 scores, per-class metrics, and `models/v1/confusion_matrix.png`.

## Export to TFLite

```bash
python -m src.export --version v1
```

Converts the Keras model to TFLite with dynamic range quantization (configurable) and generates `models/v1/spec.json` — the integration contract consumed by the Flutter `InferenceService`.

## Full Pipeline

Run all three steps in sequence:

```bash
python -m src.train --version v1
python -m src.evaluate --version v1
python -m src.export --version v1
```

On macOS/Linux, you can also use the helper script:

```bash
bash scripts/train_and_export.sh v1
```

### Configuration

All hyperparameters, class names, preprocessing settings, and augmentation options are defined in `config.yaml` — the single source of truth for the pipeline.

## Deploy to App

Copies `model.tflite` and `spec.json` to the Flutter `assets/models/` directory.

**Windows (PowerShell):**

```powershell
$version = "v1"
Copy-Item "models\$version\model.tflite" "..\assets\models\soil_classifier.tflite"
Copy-Item "models\$version\spec.json" "..\assets\models\spec.json"
```

**macOS / Linux:**

```bash
bash scripts/deploy_to_app.sh v1
```

After deploying, run `flutter build apk --release` to verify the build.

## Tests

```bash
python -m pytest tests/ -v
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
