# VisioSoil ML Pipeline

Reproducible TensorFlow/Keras pipeline for training, evaluating, and exporting the soil texture classifier used in the VisioSoil mobile app.

## Architecture

**Model:** MobileNetV2 (transfer learning from ImageNet) with custom classification head.

```
Input [1, 224, 224, 3] float32 in [0, 1]
  → Rescaling(2.0, offset=-1.0)       # Converts [0,1] → [-1,1] (baked into model)
  → MobileNetV2 backbone (ImageNet weights, no top)
  → GlobalAveragePooling2D
  → BatchNormalization
  → Dense(256, relu)
  → Dropout(0.5)
  → Dense(5, softmax)
Output [1, 5] float32 probabilities
```

**Training:** 2-phase transfer learning:
1. **Phase 1 (Head-only):** Backbone frozen, trains classification head with LR 1e-3.
2. **Phase 2 (Fine-tuning):** Top 50 backbone layers unfrozen, LR 1e-5, EarlyStopping on val_accuracy.

**Class balancing:** Computed class weights (`n_samples / (n_classes * n_samples_i)`) to handle imbalanced dataset.

## Classes

| # | Class | Folder | Images |
|---|-------|--------|--------|
| 0 | Arenosa | `data/raw/Arenosa/` | 340 |
| 1 | Media | `data/raw/Media/` | 262 |
| 2 | Siltosa | `data/raw/Siltosa/` | 30 |
| 3 | Muito Argilosa | `data/raw/Muito_Argilosa/` | 220 |
| 4 | Argilosa | `data/raw/Argilosa/` | 566 |

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
python -m src.train --version v2
```

Saves the Keras checkpoint (`model.keras`), config snapshot (`config.json`), training history (`history.json`), and best model checkpoint (`best_model.keras`) to `models/v2/`.

The training runs in two phases:
- **Phase 1:** Head-only training (backbone frozen) for the first N epochs (configured by `model.unfreeze_at_epoch`).
- **Phase 2:** Fine-tuning with top backbone layers unfrozen and lower learning rate until EarlyStopping triggers.

## Evaluation

```bash
python -m src.evaluate --version v2
```

Generates `models/v2/metrics.json` with accuracy, F1 scores, per-class metrics, and `models/v2/confusion_matrix.png`.

## Export to TFLite

```bash
python -m src.export --version v2
```

Converts the Keras model to TFLite (no quantization by default) and generates `models/v2/spec.json` — the integration contract consumed by the Flutter `InferenceService`.

## Full Pipeline

Run all three steps in sequence:

```bash
python -m src.train --version v2
python -m src.evaluate --version v2
python -m src.export --version v2
```

On macOS/Linux, you can also use the helper script:

```bash
bash scripts/train_and_export.sh v2
```

### Configuration

All hyperparameters, class names, preprocessing settings, and augmentation options are defined in `config.yaml` — the single source of truth for the pipeline.

Key configuration sections:
- `preprocessing.normalization`: `"mobilenet_v2"` — model handles [-1,1] conversion internally.
- `model.unfreeze_at_epoch`: Epoch at which fine-tuning begins (backbone unfreezing).
- `model.unfreeze_layers`: Number of top backbone layers to unfreeze.
- `training.class_weights`: `"balanced"` for automatic class weight computation.
- `training.fine_tune_learning_rate`: LR used during Phase 2.

## Deploy to App

Copies `model.tflite` and `spec.json` to the Flutter `assets/models/` directory.

**Windows (PowerShell):**

```powershell
$version = "v2"
Copy-Item "models\$version\model.tflite" "..\assets\models\soil_classifier.tflite"
Copy-Item "models\$version\spec.json" "..\assets\models\spec.json"
```

**macOS / Linux:**

```bash
bash scripts/deploy_to_app.sh v2
```

After deploying, run `flutter build apk --release` to verify the build.

## Tests

```bash
python -m pytest tests/ -v
```

Tests cover:
- Config loading and validation (including new fields)
- Preprocessing (mobilenet_v2 normalization, augmentation layers)
- Model output (shape, probability sum, Rescaling layer, unfreeze)
- TFLite export (loads, runs, Keras parity, spec.json contract)

## Integration with Flutter App

The Flutter `InferenceService` reads `spec.json` to understand the model contract:
- **Input:** Divide pixel values by 255 → produces [0, 1] range.
- **Model internal:** Rescaling layer converts [0, 1] → [-1, 1] (no Flutter code change needed).
- **Output:** 5-class softmax probabilities.

## Artifacts per Version

```
models/v2/
├── model.tflite         # Deployable TFLite model
├── model.keras          # Keras checkpoint (gitignored)
├── best_model.keras     # Best checkpoint from Phase 2 (gitignored)
├── spec.json            # Input/output contract for InferenceService
├── metrics.json         # Accuracy, F1, per-class metrics
├── config.json          # Snapshot of config.yaml used for training
├── history.json         # Training history (loss, accuracy per epoch)
└── confusion_matrix.png # Visual confusion matrix
```
