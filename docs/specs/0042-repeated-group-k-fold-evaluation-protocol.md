# SPEC: refactor(ml): evaluate by repeated stratified group k-fold with nested selection and recorded uncertainty

## Problem

A single 0.15 test fraction over the 77 splittable sample groups leaves about twelve groups to measure every result on, which is too few for any figure to carry a usable interval and too few for E0 to return the verdict it was designed to return (#203).

## Design Decision

The single `train`/`val`/`test` partition that SPEC 0033 fixed before any image existed is replaced by **repeated, stratified, group-aware k-fold cross-validation** with **k = 5 outer folds and R = 5 repeats**, every fold's model selection **nested** inside its own training side, and uncertainty reported from **repeat-level spread plus a parametric reference at the group level** — never from the spread across folds alone. The fold manifest keeps every provenance guarantee `splits.json` carries today (dataset version, manifest digest, seed, train-only groups) and adds the fold index of every group per repeat, so a result can still be shown to belong to the data it claims.

Three consequences are decided here rather than left to the implementer. First, the **unit of every interval and every contrast is the sample group**: photograph-level macro-F1 stays the deployment-faithful primary number, but the paired comparison between two arms is made on group-level predictions (the mean of a group's photograph distributions, argmaxed), because photographs of one sample are not independent and a McNemar count over them would overstate the evidence. Second, **contrasts are pre-registered in configuration** — each experimental arm against the shuffled-label control as the primary family, one named secondary contrast, Holm-corrected — so E0 cannot be read after the fact for whichever comparison happens to clear. Third, the **minimum detectable effect is computed from the observed discordance and recorded in `metrics.json`**, replacing #183's estimated rows with the archive's real numbers, so every reported difference is read against what the data could have shown.

This supersedes the split section of [SPEC 0033](0033-dataset-protocol-manifest-and-splits.md) (its Design Decision "Splits stay class-stratified and group-aware", and the criteria `splits_record_the_dataset_version_and_manifest_hash`, `splits_group_by_sample_id`, `split_composition_is_reported`), each of which survives here in k-fold form. SPEC 0033 is not edited: its other decisions stand, and its archive value is what was approved at the time. The decision is promoted to [ADR 0020](../adr/0020-evaluation-is-repeated-group-k-fold-with-nested-selection.md) because it changes the criterion every past and future number is comparable under.

## Alternatives Considered

- **Keep the single three-way split and report it with an interval** — rejected. Twelve test groups give a 95 % interval of roughly ±28 pp on accuracy (planning estimate), and a paired MDE near 40 pp (#203). An interval that wide is not a measurement; it is a statement that no measurement was made.
- **Leave-one-group-out (k = 77)** — rejected. It costs 77 trainings per arm per repeat, cannot be stratified, and its estimate has higher variance than k-fold's at this N for no gain in bias worth the cost. It remains the right choice for the *descriptor* arms alone, where a training is seconds; the protocol allows k to be raised per arm only if every arm in a pre-registered contrast uses the same folds.
- **k = 10** — rejected. Seven or eight test groups per fold puts Argilosa (16 splittable groups) at one or two per fold, doubles the training cost, and adds nothing to the pooled evaluation set, which is 77 groups at any k.
- **Report the standard error across folds as the uncertainty** — rejected, and the rejection is the reason this spec exists. Fold test sets are disjoint and small, so their spread understates the interval on the pooled figure by a large factor (Varoquaux 2018, *NeuroImage* 180:68–77). Repeats with distinct seeds capture training variance; a Wilson interval on the pooled group count and an exact McNemar reference capture sampling variance; both are recorded, and neither is the fold spread.
- **A cluster bootstrap over pooled predictions as the sole interval** — rejected as the sole interval. Resampling groups of the pooled predictions is a valid reference for sampling variance and may be recorded, but it sees one trained model per fold and therefore nothing of training variance, which at this N is not small.
- **Un-nested selection: choose checkpoints, encoders or thresholds on the outer folds** — rejected. It is the optimistic bias Vabalas et al. (2019, *PLOS ONE* 14:e0224365) measure as dominant at small N, and nesting the *choice of features or encoder* matters more than nesting hyper-parameters, which is exactly the choice E0 makes.
- **Let group B into the test sides to recover 102 groups** — rejected, at the Developer's direction on 2026-09-01. SPEC 0040 D6 holds the transported population to training because it is 68 % Argilosa and 0 % Muito Argilosa; a test set containing it measures the compression signature as much as the soil.
- **Keep a single-split code path beside the k-fold one** — rejected, on SPEC 0034's precedent: a second path that no end-to-end test exercises drifts, and two ways to produce a number is one way to produce a number nobody can attribute.

## Scope

- Includes:
  - `ml/src/dataset.py` — replace `create_splits` / `create_splits_for_config` / `load_splits` / `validate_splits_against_config` with a fold generator, a fold-manifest loader and a validator; the `min_groups = 3` floor becomes "at least k splittable groups per class".
  - `ml/src/stats.py` (new) — Wilson interval, exact McNemar test on group-level discordance, McNemar minimum detectable effect at 80 % power from observed discordance, Holm correction, group-level aggregation of photograph distributions.
  - `ml/src/crossval.py` (new) — the orchestrator: for each repeat and outer fold, run nested selection on the training side, refit, predict the test side, and pool; write `metrics.json`.
  - `ml/src/train.py` — becomes a per-fold trainer taking `--repeat` and `--fold`; the single-split path is removed; the shuffled-label control is a flag that permutes `texture_class` at group level within the fold's training side only.
  - `ml/src/evaluate.py` — reads pooled predictions and writes per-fold, per-repeat pooled, repeat spread, Wilson interval, per-contrast McNemar and MDE, per-class metrics flagged `not_headline`.
  - `ml/config.yaml` — `evaluation:` block: `k`, `repeats`, `inner_k`, `contrasts` (pre-registered pairs and the named secondary), `alpha`, `power`; `data.val_split` and `data.test_split` are removed.
  - `ml/scripts/validate_dataset.py` — prints per-repeat, per-fold composition by class and `source_group`.
  - `ml/data/splits/splits.json` — keeps its path and name; gains `schema_version: 2`, `k`, `repeats`, `seeds`, and `folds` (repeat → group → fold index); a version-1 file is refused with a message naming the regeneration command.
  - `ml/tests/` — one test per criterion below; `test_manifest_splits.py` and `test_dataset.py` updated where they assert the single split, with each change recorded.
  - `docs/architecture/ml-implementation-map.md` — the C0/E0 rows cite this protocol; #183's MDE table is replaced by a pointer to `metrics.json`.
- Does NOT include:
  - E0 itself, its arms, or its decision rule (SPEC 0044).
  - Any change under `lib/`.
  - The patch pipeline (SPEC 0037), the scale recomputation (A0), or the population-predictability probe (A0b).
  - A site-held-out split (no site column is populated).
  - Calibration, conformal bands or verdict thresholds (#187, #193) — they consume this protocol's inner folds and are specified later.
  - Editing SPEC 0033's body.

## Acceptance Criteria

- folds_are_stratified_and_group_aware: over the real `v1` manifest, every repeat assigns each splittable group exactly one fold index, and each fold's class proportions are within one group of the pooled proportions.
- every_group_is_tested_exactly_once_per_repeat: the union of test sides over the k folds of one repeat is the set of splittable groups, with no group in two test sides.
- train_only_groups_never_reach_a_test_side: every group `train_only_sample_ids` names is in the training side of every fold of every repeat and in no test side, asserted over the real manifest (25 groups).
- class_below_k_groups_is_refused: a manifest where one class has fewer than k splittable groups is refused, naming the class, its count and k.
- fold_manifest_records_provenance_and_fold_index: `splits.json` carries `schema_version`, `dataset_version`, `manifest_digest`, `classes`, `k`, `repeats`, the derived seed per repeat, `train_only_samples`, and the fold index of every group per repeat.
- result_from_another_manifest_is_refused: loading a fold manifest whose `manifest_digest` differs from the current dataset manifest fails, naming both digests.
- stale_schema_is_refused: a version-1 `splits.json` (single `train`/`val`/`test`) fails to load with a message naming the regeneration command; it is not silently reinterpreted.
- repeats_use_distinct_derived_seeds: repeat r uses a seed derived deterministically from `data.seed` and r, the derivation is recorded, and two repeats never share fold assignments.
- selection_is_nested: an audit of the group ids read during checkpoint, hyper-parameter, encoder or threshold selection for outer fold i is written beside the fold's artifacts, and a test asserts its intersection with fold i's test groups is empty, for every fold and repeat.
- refit_uses_the_whole_training_side: after inner selection, the model evaluated on fold i's test side was fitted on all of fold i's training groups (splittable training groups plus train-only groups), with the chosen setting recorded.
- shuffled_control_permutes_labels_at_group_level: with the control flag set, `texture_class` is permuted across groups (not photographs) within the training side of each fold, the test side is untouched, and the permutation seed is recorded.
- photograph_level_macro_f1_is_the_primary_number: `metrics.json` names photograph-level macro-F1 pooled over the k test sides as `primary`, per repeat.
- group_level_prediction_is_mean_of_photograph_distributions: a group's prediction is the argmax of the mean of its photographs' class distributions, and group-level macro-F1 and accuracy are recorded as `secondary`.
- uncertainty_is_never_fold_spread_alone: `metrics.json` records, per repeat, the Wilson 95 % interval on group-level accuracy over the pooled 77 groups, and, across repeats, the median and range of the primary number; a test asserts both fields exist and that no field named as an interval is computed from per-fold values.
- contrasts_are_pre_registered: every contrast evaluated is listed in `config.yaml` `evaluation.contrasts` before the run, and a contrast absent from that list is refused, naming it.
- paired_contrast_is_mcnemar_on_groups_with_holm: for each registered contrast, the exact McNemar test is computed on group-level correctness over the same folds and repeats, the discordant counts are recorded, and p-values are Holm-corrected within the registered family.
- mde_is_computed_from_observed_discordance: for each registered contrast, the minimum detectable difference in group-level accuracy at α = 0.05 (two-sided) and 80 % power is computed from the observed discordant rate and recorded beside the observed difference.
- per_class_metrics_are_recorded_and_flagged: per-class precision, recall and F1 are written with `"headline": false` and the per-class group count, so no consumer can present them as a result without the flag travelling with them (#197).
- fold_composition_is_reported: `validate_dataset.py` prints, per repeat and fold, the training and test counts by class and by `source_group`.
- single_split_path_is_removed: no code path produces a `train`/`val`/`test` partition; `create_splits` and `data.val_split` / `data.test_split` are gone, and a config still carrying them is refused naming the keys.
- cost_is_recorded: `metrics.json` records the number of trainings the run performed (outer × inner × configurations + refits) and wall-clock per training, so the choice of k and R is auditable against what it cost.
- existing_ml_tests_pass: the tests under `ml/tests/` pass, with every change to an existing assertion recorded and justified in the pull request.
- analyze_clean_tests_green: `flutter analyze` reports no issues, `flutter test` passes, and `cd ml && python -m pytest tests/ -v` passes.

## Reproducibility

- Python 3.12 with the pins in `ml/requirements.txt` (TensorFlow 2.21.0, Keras 3.14.0, scikit-learn within `>=1.3.0,<1.6.0`), in `ml/.venv`; `StratifiedGroupKFold` from scikit-learn is the fold generator, seeded per repeat.
- `data.seed = 42` is the base seed; repeat r uses `seed_r = data.seed + 1000 · r`, recorded in the fold manifest.
- Generate folds: `cd ml && python scripts/validate_dataset.py --version v1` (writes `data/splits/splits.json`, prints composition).
- Run one arm: `cd ml && python -m src.crossval --version v1 --arm <name> [--shuffled-control]`, which writes `models/<version>/<arm>/repeat-<r>/fold-<i>/` and `models/<version>/<arm>/metrics.json`.
- Compute contrasts: `cd ml && python -m src.evaluate --version v1 --contrasts`, reading `evaluation.contrasts` from `ml/config.yaml`.
- Every criterion above is verified against synthetic manifests in temporary directories except the three marked "over the real manifest", which read `ml/data/datasets/v1/manifest.csv` and are skipped, not failed, when the dataset directory is absent (CI has no dataset, per ADR 0019).
- Determinism per SPEC 0032 applies unchanged; `runtime.json` is written per fold.

## Risks and Assumptions

- **Assumes the four-class splittable pool is 77 groups (20 / 20 / 16 / 21)** as SPEC 0040 D6 and #203 measured. If A0's scale recomputation quarantines photographs, the pool shrinks and the recorded MDE grows; the protocol still holds, the numbers move.
- **Assumes k = 5 keeps every class at ≥ 3 groups per test fold.** Argilosa at 16 gives 3–4; it is the binding class, and a further loss of Argilosa groups is what would force k = 4.
- **Repeats are not independent estimates.** Every repeat tests the same 77 groups; the spread across repeats measures training variance, not sampling variance, and the Wilson interval is what carries the latter. Reading the repeat range as a confidence interval would be the same error this spec removes, in a new place.
- **The paired MDE will stay large.** At 77 groups and typical discordance the recorded MDE is expected near 15–20 pp (planning estimate). This spec makes that visible; it cannot make it small. An E0 arm that beats another by less than the recorded MDE has not been shown to beat it, and SPEC 0044's decision rule is written on that basis.
- **Cost.** Each deep-learning arm costs 5 × (inner selection + 1 refit) trainings per repeat, 25 refits per arm across repeats, on CPU. The descriptor arms cost seconds per fold. If CPU time becomes the constraint, R is reduced before k, and the reduction is recorded.
- **Label noise is unverifiable** (ADR 0016) and is inside every fold on both sides. Nothing here separates a label error from a model error; the protocol only stops the model from being tuned on the photographs it is scored on.
- **Invalidated if** a site column is ever populated with more than a handful of sites — a site-held-out protocol would then be the honest default, and this spec would be superseded rather than amended.
