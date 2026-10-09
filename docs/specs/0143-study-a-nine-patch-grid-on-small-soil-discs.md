# SPEC: feat(ml): study a nine-patch grid on small soil discs

## Problem

The released 160 px descriptor model refuses all 24 real photographs whose A4 sheet the reader detects, because their 46.5–51.4 mm soil discs cannot hold nine patches, and the only tested lower-patch alternatives lost too much classification quality.

## Design Decision

Run a pre-registered, research-only comparison of a 128 px descriptor candidate against the released 160 px descriptor procedure. At the unchanged canonical scale and half-patch stride, a centred nine-patch grid of 128 px patches needs a 46.78 mm interior disc; use the 47.2 mm disc observed in the session to simulate the candidate's training and held-out inference on the labelled dish archive. Select the candidate's regularisation strength inside each training fold, using the existing repeated grouped folds, and compare its held-out photograph macro-F1 against the baseline arm's full-grid predictions on those exact folds. The study records either a passing or a failing result; neither result changes the app or releases a model under this spec.

The decision rule is fixed before the run: the candidate passes the archive study only when its median photograph macro-F1 over the five repeats is no more than 0.02 below the released arm's median on the same folds. Top-class agreement, group accuracy, per-class scores, and the range across repeats are reported as diagnostics, not used to select a model after seeing the result. A pass permits a separate integration spec and field-photo validation; it does not establish accuracy on the unlabelled A4 photographs.

## Alternatives Considered

- **Lower the nine-patch floor for the existing 160 px model.** Rejected by SPEC 0141's completed study: five and four patches lost 0.047 and 0.059 photograph macro-F1, respectively, beyond its 0.02 margin.
- **Train 128 px patches on the whole 90 mm dish and use only nine at inference.** Rejected for this first experiment because the candidate would still be trained and tested on different spatial sampling procedures. Training and held-out scoring on the same centred nine-patch footprint isolates whether the smaller physical patch carries enough signal.
- **Reduce the stride or enlarge the photographed pixels without changing physical patch size.** Rejected because either operation counts overlapping or interpolated measurements as new soil evidence; it does not solve the physical coverage problem.

## Scope

- Includes:
  - A study command under `ml/src/` and its tests under `ml/tests/`, using the existing descriptor extraction, patch cutter, nested probe selection, fold manifest, and metrics implementation.
  - A 128 px candidate over the unchanged 0.12920342774728033 mm/px canonical scale, 0.5 stride fraction, nine-patch floor, four classes, and `v1` archive. The reader's 2 mm soil inset is already reflected in the measured interior disc and stays unchanged.
  - The same five repeats of five grouped outer folds and seed 42 as the released arm, with candidate selection on each outer fold's training side only.
  - A committed English study report under `docs/ml/` with the pre-registered rule, exact command and versions, paired results, diagnostics, decision, and limits. Local fold artifacts and photographs remain ignored.
- Does NOT include:
  - Any change to `ml/config.yaml`, `assets/models/spec.json`, Dart inference, capture UI, the A4 reader, the soil inset, or the released 160 px model.
  - Shipping the candidate model, lowering the nine-patch floor, or claiming accuracy on the unlabelled A4 photographs.
  - Treating the seven photographs without a detected, complete sheet as classifiable by this patch-size experiment.
  - New labels, changes to the archived dataset, or regeneration of the committed fold manifest.

## Acceptance Criteria

- `a_47_2_mm_disc_holds_nine_128_px_patches`: the existing centred geometry holds exactly nine 128 px patches for a 47.2 mm disc at the released canonical scale and stride; it refuses a 46.5 mm disc, and the released 160 px geometry refuses both.
- `the_candidate_changes_only_patch_size_and_disc_footprint`: study configuration and simulated measurements leave the source configuration and each photograph's scale and centre unchanged; every candidate photograph is described from its own nine central patches, without reading its label into the features.
- `selection_never_reads_outer_test_groups`: each candidate fold chooses regularisation using only its outer training groups, fits its final standardiser and regression on that training side, and scores the matching held-out groups.
- `the_comparison_pairs_the_released_folds`: the study refuses missing or incompatible baseline artifacts, reproduces their recorded photograph macro-F1 from stored predictions, and pairs candidate and baseline predictions by repeat, fold, and photograph rather than by list order.
- `the_verdict_uses_the_registered_margin`: a candidate exactly 0.02 below the baseline median passes, one farther below fails, and no diagnostic metric can override the verdict.
- `the_study_records_either_outcome_without_deploying`: the command records the candidate and baseline medians, repeat ranges, per-class and group diagnostics, top-class agreement, seed, exact runtime versions, and pass/fail decision; it never writes a candidate contract or changes app files. Unit tests run without the private archive; the full study refuses missing archive or fold artifacts explicitly.

## Reproducibility

```sh
cd ml && python -m pytest tests/test_small_patch_study.py -q
cd ml && python -m src.small_patch_study --version v1
```

Use Python 3.12 and the dependencies in `ml/requirements.txt`. Use the committed `ml/data/splits/splits.json` without regenerating it, the local `ml/data/datasets/v1/` archive, and the released arm's 25 local fold artifacts under `ml/models/v1/descriptors/`. The command must record the exact NumPy and scikit-learn versions it used and the fold manifest's recorded versions; the seed is 42, with the existing repeat derivation. The study output is local and ignored; the results document records the measured numbers and the command that produced them.

## Risks and Assumptions

- **Assumption:** the archive's nine central dish patches can stand in for the soil area of a 47.2 mm field disc when testing whether 128 px patches retain texture information. A field patch's thickness and paper background may differ, so a passing archive result cannot validate field accuracy.
- **Risk:** reducing the physical patch from 20.67 mm to 16.54 mm changes the wavelengths sampled by the spectral descriptors. The candidate needs its own nested selection and fitted weights; changing only `patch_px` in the released contract would be invalid.
- **Risk:** the 46.5 mm photograph remains below the nine-patch geometry threshold, and seven others still lack a usable sheet. Even a successful candidate does not classify all 31 supplied images.
- **Risk:** the archive and released fold artifacts are ignored local data; without them the numerical experiment cannot run. Missing inputs must be reported, not replaced with synthetic results.
- **What would invalidate a deployment decision:** a failing archive comparison, or field validation showing the dish-to-paper shift is unacceptable. Deployment requires its own approved spec in either case.
