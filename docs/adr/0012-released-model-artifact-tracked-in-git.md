# The released model artifact and its `spec.json` are tracked in git; experiment outputs are not

VisioSoil commits the released TensorFlow Lite artifact and its contract file to
the repository at `assets/models/soil_classifier.tflite` and
`assets/models/spec.json`. Both paths are to be removed from `.gitignore`.
Everything under `ml/models/` — checkpoints, per-experiment exports, evaluation
dumps — stays ignored. No release-download step, no Git LFS, and no artifact
registry is introduced.

**Not yet implemented, deliberately.** `.gitignore:83-84` still excludes both
paths as this is written. The removal is not done here because there is nothing
to un-ignore: no `.tflite` and no `spec.json` exist anywhere in the tree, so the
change would be a diff with no observable effect, landing far from the work that
gives it meaning. It lands with the specification that first produces one of the
two files — the `spec.json` runtime contract, item A4 — so the rule and the file
it admits arrive in the same change and the same review. Until then this
document records a decision taken, not a state reached.

## Status

Accepted. Recorded during the 2026-07-30 ML architecture study
(`docs/architecture/soil-classification.md`, §24 question 6), which listed this
as an open question blocking #79 and #116. Nothing depends on it yet, because no
artifact exists; the decision is made now so that the work which does depend on
it can be specified rather than waiting on a model.

### Decided

- **The artifact is part of the application, not an input to it.** A clone of
  this repository at any commit builds an APK whose behaviour is fully
  determined by that commit. That property is what makes a regression
  bisectable, and it is lost the moment the model arrives from somewhere else.
- **`spec.json` is a contract, and contracts belong in version control.** It
  carries the label list, the input size, the normalization, and — after
  calibration — the per-class band constants that the UI reads. #79 and #116
  exist precisely because those values are currently duplicated in source
  instead of being read from one file. Replacing six hardcoded copies with one
  untracked file would not fix the problem, it would relocate it.
- **Only released versions are committed.** `ml/models/vN/` remains the
  experiment workspace and remains ignored. Promotion is an explicit act:
  `ml/scripts/deploy_to_app.sh` copies one export into `assets/models/`, and the
  commit that does so is the release record.
- **The commit message names the dataset version and the metrics.** A binary
  diff is unreadable, so the provenance has to live in the message and in
  `spec.json`, not in the blob.

## Considered Options

- **GitHub Release plus a CI download step** — rejected. It keeps the git
  history free of binaries, and that is its only advantage. It costs a network
  fetch in every build, a credential path for private repositories, a failure
  mode where a clone cannot build offline, and a second place where "which model
  is this" has to be answered. The field requirement is offline operation; a
  build pipeline that requires the network to produce an offline app is a poor
  trade.
- **Git LFS** — rejected. LFS solves the problem of large binaries changing
  often. A retrained soil classifier is expected a handful of times per year at
  most, so the problem LFS solves does not exist here, while its costs —
  a required client-side extension, a bandwidth quota, and clones that silently
  produce pointer files when the extension is missing — are immediate.
- **A model registry (MLflow, Weights & Biases artifacts)** — rejected for this
  phase. Registries earn their operational cost when many models are compared by
  many people. Here the experiment log is a directory and a markdown table, and
  ADR 0008's reasoning about second runtimes applies unchanged to second
  infrastructures.
- **Track it in git (chosen).**

## Consequences

- `.gitignore` loses its `assets/models/*.tflite` and `assets/models/spec.json`
  entries. `assets/models/.gitkeep` becomes redundant once a real artifact
  lands, but is kept until then.
- Repository size grows by the artifact size on each release. A MobileNetV2-class
  classifier lands somewhere between roughly 3 MB fully int8-quantized and
  roughly 14 MB in float32; the quantization rung is chosen by experiment E8, so
  the exact figure is not knowable yet. At a few releases per year this is
  tolerable. **Revisit this ADR if the artifact exceeds 25 MB or if releases
  become more frequent than monthly** — those are the conditions under which the
  rejected Release-plus-CI option becomes the better trade.
- `InferenceService` gains a real failure distinction it cannot make today:
  "model absent" stops being the normal state of the repository, so
  `_modelUnavailable` becomes a genuine anomaly worth reporting rather than the
  default.
- CI needs no new secret, no new network call, and no new step. The existing
  `flutter build apk --release` job keeps working unchanged.
- Because the artifact is bundled and versioned with the app, over-the-air model
  updates are out of scope: a new model ships as a new app release. That is a
  consequence, not a limitation to be worked around — a model swapped
  independently of the code that pre-processes for it is a train/serve skew
  waiting to happen, which is the same class of defect already found on EXIF
  orientation.
