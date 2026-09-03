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
2. **Phase 2 (Fine-tuning):** Top 50 backbone layers unfrozen, LR 1e-4, EarlyStopping on val_accuracy.

**Class balancing:** Computed class weights (`n_samples / (n_classes * n_samples_i)`) to handle imbalanced dataset.

## Classes

The five Embrapa textural groups the delivered archive holds. **Four of them are
the model's classes**, in the order `ml/config.yaml` declares and the model emits;
the fifth is in the manifest and in no fold. The two lists are
`src.manifest.ARCHIVE_CLASSES` and `cfg["classes"]` (SPEC 0046).

**The counts below are measured, as of 2026-08-25.** They replace an earlier
planning estimate of 1,418 images that no run ever confirmed. The images
themselves stay git-ignored by design; what is committed is the manifest. See
[ADR 0016](../docs/adr/0016-dataset-is-the-existing-dish-archive-and-siltosa-is-out-of-v1.md).

The unit that matters is the **sample**, not the image: folds group on it, every
interval and every paired contrast is computed over it, and some samples carry
more than one photograph.

| # | Class | Samples | Images | In the first model |
|---|-------|---------|--------|---|
| 0 | Arenosa | 57 | 68 | yes |
| 1 | Media | 36 | 42 | yes |
| 2 | Siltosa | **3** | 6 | **no** |
| 3 | Muito Argilosa | 39 | 42 | yes |
| 4 | Argilosa | 59 | 63 | yes |
| | **Total** | **194** | **221** | |

**Siltosa is excluded from the first model.** Three sample groups is below the
five the evaluation protocol needs — one in each of the k = 5 folds' test sides —
and a per-class figure computed on one test sample is a coin flip presented as a
measurement. The first model classifies four groups, and since SPEC 0046 both
`config.yaml` and `SoilTextureLabels.ordered` declare those four. Its rows stay
in the manifest: a dataset version is a build product of the archive (ADR 0019),
so a version holding less than what was delivered could not be checked against
it. Fold creation over the real `v1` therefore succeeds at k = 5, and no Siltosa
group reaches any fold.

**129 of the 221 files are HEIC**, which neither `tf.io.decode_image` nor the
Dart `image` package can read. Conversion precedes everything (#196).

The photographs are soil in a 90 mm Petri dish, top-down, on a pale background.
The laboratory number is carried in the filename — `100262,1 (1).JPEG` is
photograph 1 of sample `100262,1` — so the manifest is derived from a directory
scan rather than authored.

## Setup

**Python 3.12.** Not `python`, whatever that resolves to: `tensorflow==2.21.0`
has no wheel for every interpreter, and on a machine whose default is newer the
install succeeds partially and `src.train` cannot be imported at all. Check with
`python --version` first; if it is not 3.12, name the interpreter explicitly.

### 1. Create virtual environment

**Windows.** `python3.12` is usually not on `PATH`; the launcher is:

```powershell
cd ml
py -3.12 -m venv .venv
```

`py -0` lists the interpreters it knows about. If 3.12 is installed outside the
launcher's registry — pyenv-win, a `uv`-managed interpreter, a plain
directory install — give its path instead:

```powershell
& "$env:USERPROFILE/.local/bin/python3.12.exe" -m venv .venv
```

**macOS / Linux:**

```bash
cd ml
python3.12 -m venv .venv
```

Whichever route, step 4 is what confirms it worked; the interpreter's name is
not the check.

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

### 4. Confirm the environment is the pinned one

```bash
python -m pytest tests/test_requirements.py -q
```

**It must pass, not skip.** That check reports the installed versions against
`requirements.txt` and skips loudly when they diverge, so a skip means the
environment is not the one any recorded result was produced under. With the
pinned stack the whole suite runs with nothing gated out:

```
434 passed, 0 skipped
```

On an interpreter without TensorFlow the suite still runs — the protocol, the
loader, the pooling and the reporting are all importable without it — and
reports 16 skips instead.

### Which environment a result comes from

**A published result comes from CI.** `.github/workflows/train.yml` is dispatched
by hand and runs one job per fold, each naming the same runner image and the
same `requirements.txt`, so two results are comparable because they were
produced in one declared environment rather than because two laptops agreed.
One arm is 25 folds; an arm does not fit a single job's six-hour ceiling and a
fold does.

**A local run is for iteration.** It produces the same numbers — the run is
seeded, `enable_op_determinism` is on, and each fold's `runtime.json` records
the library versions and the device — but it is named by a machine nobody else
has. Nothing prevents publishing one; the record asks you not to, and
`runtime.json` is what lets a reader tell afterwards.

**Regenerate the fold manifest under the pinned stack** before any run, if it
was drawn elsewhere. `StratifiedGroupKFold` partitions differently across
scikit-learn versions, so a manifest drawn outside the pins is one CI cannot
reproduce. `load_folds` warns when the versions it was drawn under differ from
the ones reading it; the warning names both.

## Dataset

New collection follows the manifest-backed protocol in
[`docs/ml/collection-protocol.md`](../docs/ml/collection-protocol.md): an
immutable `data/datasets/vN/` directory whose `manifest.csv` is the authoritative
record, admitted by the quality criteria and checked by two tools that need no
TensorFlow installed.

```bash
python scripts/admit_images.py --version v1      # report; add --write to apply
python scripts/validate_dataset.py --version v1  # report only, folds discarded
python scripts/validate_dataset.py --version v1 --splits-dir data/splits  # write them
python scripts/measure_scale.py --version v1     # the dish rim, per photograph
python scripts/measure_scale.py --version v1 --from-record measurements/dish-scale-v1.json
```

`measure_scale.py` reads the 90 mm dish rim of every photograph and writes
`measurements/dish-scale-v1.json` — millimetres per pixel per photograph with its
capture population, the distribution overall and per population, every photograph
that received no scale, and the dataset version and manifest digest it was taken
over. The canonical scale the pipeline normalises to is the 95th percentile of
those readings, and it is a contract value: a model trained at one canonical
scale cannot be served at another (ADR 0017). That is why this record is
committed while the dataset version it describes is not — see
[SPEC 0052](../docs/specs/0052-read-the-dish-rim-and-recompute-the-canonical-scale.md),
which measured it at **0.1292 mm/px** over all 221 photographs of `v1` with no
photograph refused.

The same run writes four columns back into the manifest — `mm_per_px`,
`disc_diameter_px`, `disc_centre_x_px` and `disc_centre_y_px` — because the patch
grid of [SPEC 0053](../docs/specs/0053-train-on-scale-normalised-greyscale-patches.md)
is laid out from the dish centre and a diameter alone locates nothing. Reading
the archive takes about seven minutes and the manifest is a build product
(ADR 0019), so after a re-ingest use `--from-record`: it fills those columns from
the committed record without opening a photograph, and refuses a record whose
manifest digest is not the one on disk.

The older folder-scan layout — images in `data/raw/<ClassName>/`, supported
formats `.jpg`, `.jpeg`, `.png`, `.bmp`, `.webp` — is still readable by the fold
generator, but the training entry point requires the manifest: the protocol
groups by the declared `sample_id`, and a filename pattern that happens to fit is
the worst case because nothing reports that it was used.

`validate_dataset.py --splits-dir data/splits` writes the **fold manifest** to
`data/splits/splits.json`: the fold index of every sample group per repeat, the
seeds those folds were drawn from, the scikit-learn and NumPy versions they were
drawn under, the train-only groups, and the dataset version and `manifest.csv`
digest that make a result attributable to the data it claims.

The versions are recorded because the seed alone does not reproduce a partition:
`StratifiedGroupKFold` is a greedy balancing heuristic and scikit-learn 1.5.2 and
1.8.0 partition the same groups differently under the same seed. Loading a
manifest generated under another stack **warns** rather than refusing — the
stored assignment is read, never recomputed, so it is still the partition the
result was computed on; regenerating it is what would move the folds.

For the same reason the assignment is **rebalanced deterministically** after the
generator runs: `StratifiedGroupKFold` balances approximately and can leave a
class out of a fold's test side entirely, which makes that fold's macro-F1
undefined for the class and silently so. The repair moves whole groups from the
fold holding most of a class to the fold holding fewest until no two differ by
more than one, so every class with at least k groups reaches every fold under any
library version.
It is `schema_version: 2`; a version-1 file — one `train`/`val`/`test` partition —
is refused by name rather than reinterpreted.

`data/splits/` is gitignored, so `splits.json` is **not** versioned in git today
and the seed plus the recorded digest are what make a fold reproducible.

## Evaluation protocol

Every number comes from **repeated stratified group k-fold cross-validation** —
k = 5 outer folds, R = 5 repeats — with every selection nested inside the fold's
own training side
([ADR 0020](../docs/adr/0020-evaluation-is-repeated-group-k-fold-with-nested-selection.md),
[SPEC 0042](../docs/specs/0042-repeated-group-k-fold-evaluation-protocol.md)).
There is no `train`/`val`/`test` partition, and a result reported from one is not
a VisioSoil result.

- The **sample group** is the unit of every interval and every paired contrast.
  A group's prediction is the argmax of the mean of its photographs'
  distributions; photograph-level macro-F1 stays the primary number.
- **Uncertainty is never the spread across folds.** The Wilson interval on the
  pooled group count carries sampling variance and the spread across repeats
  carries training variance.
- **Contrasts are pre-registered** in `config.yaml` under
  `evaluation.contrasts`, Holm-corrected within the family, and an unregistered
  contrast is refused by name.
- The **minimum detectable effect** is computed from the observed discordance
  and recorded beside every difference.

## Training

```bash
python -m src.crossval --version v1 --arm cnn                     # every fold
python -m src.crossval --version v1 --shuffled-control            # the control
python -m src.train --version v1 --repeat 0 --fold 0              # one fold
```

`src.crossval` runs every repeat and outer fold and writes
`models/v1/<arm>/metrics.json`. Each fold writes its own directory —
`models/v1/<arm>/repeat-<r>/fold-<i>/` — holding `model.keras`, the config
snapshot, `runtime.json`, `predictions.json`, `cost.json`, and
`selection_audit.json`, which records every sample group read while selecting a
setting for that fold so the nesting can be checked rather than assumed.

Inside a fold the recipe is unchanged:
- **Phase 1:** Head-only training (backbone frozen) for the first N epochs
  (configured by `model.unfreeze_at_epoch`).
- **Phase 2:** Fine-tuning with top backbone layers unfrozen and a lower
  learning rate.

The epoch count is chosen on `evaluation.inner_k` inner folds of the outer
fold's training side, and the model that is scored is refitted on the whole
training side with that choice.

## Evaluation

```bash
python -m src.evaluate --version v1 --arm cnn        # recompute metrics.json
python -m src.evaluate --version v1 --contrasts      # the registered family
```

`metrics.json` carries the primary number per repeat, the Wilson interval on
each repeat's pooled group accuracy, the median and range across repeats,
per-class figures flagged `"headline": false`, and what the run cost in
trainings and wall-clock seconds. `--contrasts` writes `models/v1/contrasts.json`
with each registered contrast's discordant counts, exact McNemar p-value, its
Holm-corrected value and its minimum detectable effect.

## Export to TFLite

```bash
python -m src.export --version v1
```

Converts the Keras model to TFLite (no quantization by default) and generates `models/v1/spec.json` — the integration contract the Flutter `InferenceService` is specified to consume. It does not read it yet: `SPEC 0035` is the change that makes the contract a runtime source, and until it lands the Dart side declares the same values in source.

`src.export` reads `models/v1/model.keras`. Cross-validation produces one model
per fold per repeat under `models/v1/<arm>/repeat-<r>/fold-<i>/`, and **which of
them ships is a release decision this protocol does not make**: the folds exist
to measure, not to nominate. Promoting a model to `models/v1/model.keras` is the
step that precedes an export.

## Full Pipeline

Run all three steps in sequence:

```bash
python -m src.crossval --version v1 --arm cnn
python -m src.evaluate --version v1 --arm cnn
python -m src.export --version v1
```

On macOS/Linux, you can also use the helper script:

```bash
bash scripts/train_and_export.sh v1
```

### Configuration

All hyperparameters, class names, preprocessing settings, and augmentation options are defined in `config.yaml` — the single source of truth for the pipeline.

Key configuration sections:
- `preprocessing.normalization`: `"mobilenet_v2"` — the only accepted value, and the only preprocessing contract the pipeline implements. The model bakes the [0,1] to [-1,1] conversion into its graph, `spec.json` declares `divide_255` to match, and `preprocessing.bake_into_model` must be `true` (SPEC 0034).
- `model.unfreeze_at_epoch`: Epoch at which fine-tuning begins (backbone unfreezing).
- `model.unfreeze_layers`: Number of top backbone layers to unfreeze.
- `training.class_weights`: `"balanced"` for automatic class weight computation.
- `training.fine_tune_learning_rate`: LR used during Phase 2.

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

## Versioning

Models are stored in `models/vN/` directories. Increment the version number for each new training run to preserve history.

Previous versions (v1 SqueezeNet, v2 MobileNetV2 with label ordering bug) were cleaned as part of pipeline corrections. New training starts from `v1` with the corrected pipeline.

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

`spec.json` describes the model contract. **The Flutter `InferenceService` does
not read it today** — it hardcodes the same values, which is issue #79 and what
`docs/specs/0035-spec-json-runtime-contract.md` specifies away. The contract is:
- **Input:** Divide pixel values by 255 → produces [0, 1] range.
- **Model internal:** Rescaling layer converts [0, 1] → [-1, 1] (no Flutter code change needed).
- **Output:** 5-class softmax probabilities.

## Artifacts per Version

```
models/v1/
├── model.tflite         # Deployable TFLite model
├── model.keras          # Keras checkpoint (gitignored)
├── best_model.keras     # Best checkpoint from Phase 2 (gitignored)
├── spec.json            # Input/output contract for InferenceService
├── metrics.json         # Accuracy, F1, per-class metrics
├── config.json          # Snapshot of config.yaml used for training
├── history.json         # Training history (loss, accuracy per epoch)
└── confusion_matrix.png # Visual confusion matrix
```
