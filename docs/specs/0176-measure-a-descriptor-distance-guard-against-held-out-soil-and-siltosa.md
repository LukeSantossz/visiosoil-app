# SPEC: feat(ml): measure a descriptor-space distance guard against held-out soil and the excluded Siltosa

## Problem

`ClassificationOutcome.rejectedOod` has no producer (ADR 0015), so a Siltosa sample, the class ADR 0016 keeps out of the model, receives one of the four remaining classes with a confident percentage, and nothing measures whether a distance in the contract's descriptor space could tell it, or any input unlike the archive, apart from the soils the model was fitted on.

## Design Decision

This spec measures the guard before anything ships. It answers #194's recast question, in the space the released regression already scores in, and writes no contract.

**The score.** A patch's descriptors are standardised with the scaler `fit_probe` fits on the training side, the same transform the regression reads. For each configured class, the centroid is the mean of its training patches in that space. The variance is shared and diagonal: per feature, the within-class variance pooled over the four classes. A patch's distance is the smallest, over classes, of

    sqrt( mean_j ( (z_j − μ_c,j)² / σ²_j ) )

that is, a diagonal Mahalanobis distance scaled by the feature count, so 1.0 is one pooled standard deviation per feature. A photograph's score is the mean of its patches' distances, as the app aggregates probabilities (`aggregation: mean`). The parameters are four centroids and one variance vector, 5 × 26 floats.

**Held-out soil.** On repeat 0 of the fold manifest, each fold's training side fits the scaler, the centroids and the variance, and its test side is scored. Every splittable archive photograph is scored once, by a fit that never saw its soil sample. Population `B` trains on every side and is never scored (ADR 0021).

**Siltosa.** The six archive photographs of Siltosa, three samples, are featurised as the archive is, from their manifest measurement. Each fold's fit scores them, and a photograph's score is the mean over the five folds. No Siltosa patch is ever on a training side.

**The threshold** is the 0.99 quantile of the held-out soil scores, so the guard refuses about one unseen archive soil photograph in a hundred. It is fixed before the run because refusing a genuine soil is the expensive error (#194).

**The report** gives the threshold, the held-out soil refusal rate overall and per class, the score of each Siltosa photograph and how many the threshold refuses, and the AUROC of Siltosa against held-out soil. It writes `models/<version>/ood_study/report.json` and prints a table. With `--field <export>`, SPEC 0174's export is scored by the fit on the whole archive. The report then also gives the field refusal rate at the threshold, overall and per class, because a guard that refuses the field's soils would refuse the photographs the app exists for.

**The rule is fixed before the run.** The guard is worth wiring into the app, by a separate spec, when:

1. at the threshold it refuses at least 4 of the 6 Siltosa photographs; and
2. the AUROC of Siltosa against held-out soil is at least 0.80.

A third condition stays open until a field export is scored: the field refusal rate at the threshold must be at most 0.10. The wiring spec cannot be approved before it is measured.

Run with `python -m src.ood_study --version v1 [--field <export>]`. The archive is on this machine, so the run is part of this spec, and its numbers are recorded in `docs/ml/descriptor-distance-guard.md`.

## Alternatives Considered

- **Write the score into `spec.json` and produce `rejectedOod` now.** Rejected for this spec. `rejectedOod` is an outcome, not a cause, so the chip, the saved record and the pt-BR copy all change with it, and a contract `spec_version` 3 is owed. All of that is worth paying only if the measurement says the guard separates. It is the next spec if rule 1 and rule 2 hold.
- **The full 26 × 26 covariance.** Deferred. With some 200 photographs it is estimable, but the diagonal is #194's default, and the full form is its fallback should the diagonal measure badly.
- **Calibrate the threshold on a public set of non-soil photographs**, as #194's 2026-08-25 decision proposed. Deferred. That decision gave the public set the operating point, but a quantile of held-out soil fixes the operating point from soil alone, which is the error that matters. A public set would then only report how much non-soil is caught. That is worth knowing, but it needs a licence check and a download, and it does not decide whether the guard catches the one input ADR 0016 names. A photograph of something other than soil would also have to pass the A4-sheet reader before the guard ever saw it.
- **kNN distance to stored training patches.** Rejected, as #194 rejects it: the artifact grows with the dataset.

## Scope

- Includes:
  - `ml/src/ood.py`: fitting the centroids and the pooled diagonal variance on a training side's standardised patches, and scoring patches and photographs.
  - `ml/src/ood_study.py`: the held-out loop on repeat 0, the Siltosa scoring, the optional field export, the threshold, the AUROC, the rule, the report and the CLI. A `--version` other than the configuration's is refused, as `field_study` refuses it.
  - Reading the archive rows of the classes the configuration excludes, featurised with `arms.descriptors.descriptor_features`, the featuriser the release fits with.
  - Tests in `ml/tests/` on synthetic patches and a synthetic archive (`tests/support.py`).
  - Running the study on `v1`, and `docs/ml/descriptor-distance-guard.md` recording its numbers and which rules hold.
  - A `ml/README.md` section on running it.
- Does NOT include:
  - Any change to `assets/models/spec.json`, `ml/src/contract.py`, `release.py` or `ml/config.yaml`.
  - Any app change: `rejectedOod` keeps having no producer after this spec.
  - A public non-soil set.
  - A claim about field-fresh material. The score is blind to what is soil-like (#194), and the field refusal rate is a cost, not a detection.

## Acceptance Criteria

- `the_centroids_and_variance_come_from_the_training_side`: fitted on two synthetic classes, the centroids are the class means of the standardised rows, and the variance is the pooled within-class variance per feature.
- `a_patch_scores_against_its_nearest_class`: a row at a class centroid scores 0, and a row one pooled standard deviation from the nearest centroid on every feature scores 1.0.
- `a_photograph_scores_the_mean_of_its_patches`: a photograph's score is the mean of its patch distances.
- `held_out_soil_is_scored_by_a_fit_that_never_saw_it`: on a synthetic archive, every splittable photograph is scored once, by a fold whose training side holds no photograph of its group, and no train-only group is scored.
- `siltosa_never_trains`: no excluded-class row reaches a training side, and each excluded photograph's score is the mean over the folds.
- `the_threshold_is_the_held_out_quantile`: the threshold is the 0.99 quantile of the held-out soil scores.
- `the_rule_is_applied_as_written`: 4 of 6 refused with AUROC 0.80 passes; 3 of 6, or AUROC 0.79, fails; without a field export the field condition is reported open, not passed.
- `the_version_is_the_configurations`: a `--version` other than `data.dataset_version` fails before the archive is read.
- `the_study_runs_end_to_end`: on a synthetic archive with an excluded class and a synthetic field export, the CLI writes a report with the threshold, the soil and Siltosa refusals, the AUROC, the field refusal and the rule.

## Reproducibility

```sh
cd ml && python -m pytest tests/ -q
cd ml && python -m src.ood_study --version v1
```

Python 3.12 and the pins in `ml/requirements.txt`. The study is deterministic for a given archive and fold manifest: there is no random draw in it.

## Risks and Assumptions

- Risk: six photographs from three samples make the Siltosa figures coarse, since one photograph is a sixth of rule 1. The rule is set on photographs because three samples would be coarser still, and the report names each sample.
- Risk: Siltosa may sit between Media and Argilosa in descriptor space, since silt is between sand and clay in grain size. If so, the guard does not catch it, and that is a result to record, not a failure of the study.
- Assumption: the held-out quantile from repeat 0 stands for the refusal rate on unseen archive soil. A different repeat would give a slightly different threshold, and the report gives the count of photographs behind the quantile.
- What would invalidate this spec: a Siltosa row on a training side, or a threshold chosen after the Siltosa scores were seen.
