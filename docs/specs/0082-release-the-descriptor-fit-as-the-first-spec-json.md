# SPEC: feat(ml): release the descriptor fit as the first spec.json

## Problem

The descriptor contract has a schema and a writer (SPEC 0079), but nothing fits
the adopted pipeline on the whole of `v1` and writes it out. `export.py` and
`deploy_to_app.sh` still describe the TFLite path that failed the E0 gate, so
the app has no `spec.json` to read and the wiring has nothing to wire. This is
B3 in the implementation map.

## Design Decision

**One release fit, chosen the way E0 chose, written through the one writer.**
`ml/src/release.py` does four things:

1. It loads the tracked fold manifest, which is `ml/data/splits/splits.json` for
   `v1`.
2. It selects the regularisation strength `C` from `arms.probe.C_GRID`. The
   criterion is E0's own: mean photograph-level accuracy, with ties going to the
   smallest `C`.
3. It refits `fit_probe` on every photograph the manifest holds, at that `C`.
4. It writes the result with `contract.descriptor_contract`.

The features are the E0 arm's `descriptor_features`, so the release reads its
photographs through the same `_photograph_patches` cut that produced every fold
artefact.

**Selection runs over the manifest's own partition: every fold of every
repeat.** In E0, `C` was chosen on grouped inner folds of each outer training
side, with population `B` always on the training side. A release has no outer
test side, so one level of nesting collapses, and the whole pool is the
training side. The manifest's outer partition is already a grouped, stratified
k-fold of that pool with `B` held to training (ADR 0021). Reusing it keeps the
partition the gate was scored on, instead of drawing a second one that would
need its own seed and its own justification. Averaging over all 25 folds rather
than the 5 of one repeat removes most of the partition noise for the price of
125 cheap fits. A train-only group is never scored, for the reason it never is
in E0: it is not what the app will see.

**What the selection accuracy is not.** It is the maximum over five settings of
a score computed on the same folds, so it flatters the release. It is recorded
as the reason `C` was chosen, never as a performance figure. **The release's
headline metrics are E0's cross-validated estimate of this procedure** on `v1`:
group accuracy 0.6883 and photograph macro-F1 0.6232 (`docs/ml/e0-verdict.md`).

**The release lands in two places.**

- **`ml/models/<version>/release/`**, git-ignored as all of `ml/models/` is. It
  holds `spec.json` and `selection.json`: the grid, the mean accuracy per `C`,
  the chosen `C`, the number of scored folds, the manifest digest, the dataset
  version, the model version, and the photograph and group counts.
- **`assets/models/spec.json`**, tracked. `deploy_to_app.sh` promotes it, and
  the commit that adds it is the release record. ADR 0012 decided that the file
  is un-ignored in the change that first produces one. This is that change, so
  the `.gitignore` entry goes here and not in the wiring, as SPEC 0079's scope
  had put it. The `.tflite` entry stays: ADR 0024 means v1 has no network, so
  there is nothing to track.

The release commit's subject names the dataset version and the headline
metrics, as ADR 0012 requires. It has no body, as this repository's commits
never do.

**The model version is given, the dataset version is read.** `--model-version`
is required, and the first release is `1.0.0`. The dataset version comes from
the fold manifest's `dataset_version` and is never typed, so the contract cannot
name a dataset it was not fitted on.

**`deploy_to_app.sh` promotes `spec.json` alone.** It stops requiring a
`.tflite` and copies `models/<version>/release/spec.json` to
`assets/models/spec.json`. It refuses when the source is missing, as it does
today.

## Alternatives Considered

- **A fresh grouped split at `inner_k`, as each E0 fold drew one.** Rejected. It
  introduces a partition nothing was scored on, with a seed to derive and
  defend, and it is noisier than 25 folds.
- **The `C` most E0 folds chose.** Rejected. It is a vote over artefacts that
  live on another machine, and a vote is not the rule E0 selected by. The
  selection record still makes the two comparable.
- **A fixed `C`.** Rejected. No record chose one.
- **Leaving `spec.json` untracked until the wiring reads it**, as SPEC 0079's
  scope assumed. Rejected. ADR 0012 ties the un-ignoring to the first file, and
  a release that exists only in an ignored directory is a release nobody can
  build from.
- **Regenerating the committed `spec.json` in a test.** Rejected. Its numbers
  pass through the FFT and `log` inside the descriptors, which drift in the last
  digits across CPUs (SPEC 0080), and the fit itself takes minutes over real
  photographs. The committed file is the record. The tests prove the procedure
  on synthetic features, and they prove that the committed file is a valid
  contract.

## Scope

- Includes:
  - `ml/src/release.py`:
    - `release_fit`, which selects, refits and writes the contract, and takes a
      featuriser so it can be tested without photographs;
    - a CLI, `python -m src.release --version v1 --model-version 1.0.0`, which
      writes `models/<version>/release/`.
  - `ml/tests/test_release.py`.
  - `ml/scripts/deploy_to_app.sh`, which now promotes `spec.json` alone.
  - `.gitignore`, which loses its `assets/models/spec.json` entry.
  - `assets/models/spec.json`: the first release, `1.0.0` on `v1`, committed in
    its own release commit.
  - A Dart test that the committed release parses as a contract.
  - The map's B3 entry.
  - The two lines of `docs/agents/project.md` that say no `spec.json` is
    tracked, one under Current Limitations and one under Known Technical Debt,
    and the agent files regenerated from it with `mf agents sync`.
- Does NOT include:
  - Reading the contract in `InferenceService`, labels from the contract,
    deleting `SoilTextureLabels`, `contractMissing`, or removing the TFLite path
    and `export.py`. That is the wiring.
  - Calibration and the verdict bands. That is C2.
  - Any change to `C_GRID`, `fit_probe`, `descriptor_features`, the descriptors
    or the fold manifest.
  - A new performance estimate. E0's stands, and nothing here re-runs it.

## Acceptance Criteria

Python:

- `release_selects_c_over_every_manifest_fold`: the mean photograph accuracy
  per `C` is taken over every fold of every repeat, and the chosen `C` is the
  best, ties going to the smallest.
- `train_only_groups_are_never_scored`: no photograph of a train-only group
  appears on a scored side.
- `the_refit_holds_every_photograph`: the refit sees every photograph of the
  manifest exactly once, train-only groups included.
- `the_release_contract_reproduces_the_refit`: SPEC 0079's arithmetic over the
  written contract equals the refit's `predict_proba`, within the tolerance.
- `the_release_records_its_provenance`: `selection.json` carries the grid, the
  mean accuracy per `C`, the chosen `C`, the scored fold count, the manifest
  digest, the dataset and model versions, and the counts.
- `the_committed_release_is_a_valid_contract`: `assets/models/spec.json` carries
  `src.descriptors`' fixed points, `cfg["classes"]`, the configured geometry,
  `dataset_version` `v1`, and a standardiser and regression of the right shapes.

Dart:

- `the_committed_release_parses`: `parseDescriptorContract` accepts
  `assets/models/spec.json` with no refusal.

## Reproducibility

```sh
cd ml && .venv/Scripts/python.exe -m src.release --version v1 --model-version 1.0.0
bash ml/scripts/deploy_to_app.sh v1
cd ml && .venv/Scripts/python.exe -m pytest tests/test_release.py -q
flutter test test/services/release_contract_test.dart
flutter analyze && flutter test && mf check
```

Python 3.12, scikit-learn 1.5.2, numpy 1.26.4 and Pillow 10.4.0 locally, over
`v1` and the tracked fold manifest (digest `49cc469f…`). Rerunning the release
on the same machine reproduces the same file. On another CPU the numbers can
move in their last digits, for SPEC 0080's reason.

## Risks and Assumptions

- **Risk: the selection folds are the ones E0 was scored on.** This biases the
  selection score, which is why it is never reported as performance. It does
  not bias the release: no estimate is drawn from the release.
- **Risk: the release is fitted on dish photographs and will read paper.** ADR
  0018 argues that the background difference disappears once the grid is inset,
  and that argument is unchanged and unmeasured. The sheet reader and the wiring
  are where it is first tested.
- **Assumption: population `B` belongs in the release fit.** ADR 0021 kept it in
  training and out of every test side. Here, that means it is in the refit and
  never scored.
- **What would invalidate this spec:** C2 finding that calibration needs a
  held-out side the release has consumed. The release would then be refitted
  with that side withheld, and the contract re-released under a new model
  version.
