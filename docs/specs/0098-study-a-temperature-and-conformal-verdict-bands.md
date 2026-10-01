# SPEC: feat(ml): study a temperature and conformal verdict bands on the cross-validated predictions

## Problem

SPEC 0095 measured the adopted model's distribution before any calibration.
Its expected calibration error is 0.074 and it is underconfident. Two decisions
follow, and neither can be argued without numbers:

- **Should the app apply a temperature?** No temperature has been fitted, so
  nobody knows how much one would correct.
- **How should the verdict bands be set?** ADR 0011's three constants (0.15,
  0.50, 0.65) are labelled provisional. #193 proposes deriving the bands by
  split conformal prediction instead and asks for experiment E15: conformal
  against the constants, measured on the same predictions.

Both questions can be measured now, on the stored cross-validated predictions.
Publishing anything has to wait for the A4-sheet photographs, which SPEC 0095
records.

## Design Decision

**A study, not a release.** It reads the `descriptors` arm's stored
predictions and writes `models/<version>/<arm>/calibration_study.json`, plus a
record at `docs/ml/calibration-study.md`. It changes no contract, no
`spec.json`, no app code and no band constant. The record is evidence for the
decisions above, which stay the Developer's.

**Every fitted quantity is cross-fitted, so nothing is scored on what fitted
it.** Within each repeat, the quantity applied to fold k is fitted on the
out-of-fold predictions of the other k − 1 folds. The folds are disjoint by
sample group, so no photograph of a group is fitted on and then scored. This is
the protocol's own discipline (ADR 0020), applied after the fact.

**The temperature acts on the photograph's distribution:**
p_T(y) ∝ p(y)^(1/T).

- That is temperature scaling with the log-probabilities as logits.
- It needs no patch logits, which `predictions.json` does not keep.
- It acts on exactly the distribution the app shows.
- It preserves the argmax, so accuracy is untouched and only the probabilities
  move.
- It is fitted by negative log-likelihood, with a deterministic golden-section
  search over 1/T on [0.05, 20]. The study reports:
  - the calibration error before and after, over the same 10 bins;
  - the cross-fitted temperatures;
  - the single temperature fitted on every out-of-fold prediction. A release
    would publish that one, but this study does not.

**Conformal prediction sets use the score 1 − p(true class).** At level α, the
threshold is the ⌈(n + 1)(1 − α)⌉-th smallest of the n calibration scores, and
a photograph's set is every class with p ≥ 1 − threshold. The sets come from
the raw distribution: the coverage guarantee does not depend on calibration.
Each set maps onto ADR 0011's verdicts as #193 lays out:

- one class is `conclusive`;
- two classes are `ambiguous`;
- three or more, or none, is `insufficient`.

The study reports, at α of 0.05, 0.10, 0.15 and 0.20:

- the empirical coverage;
- the mean set size;
- the share of each verdict;
- the accuracy of the `conclusive` photographs.

**The incumbent is measured the same way.** ADR 0011's rule is reimplemented in
Python from `ClassificationVerdict.fromDistribution`:

- `conclusive` at a margin ≥ 0.15 with top-1 ≥ 0.50;
- `ambiguous` at a margin < 0.15 with a pair share ≥ 0.65;
- `insufficient` otherwise.

Its verdicts are read as sets: {top-1}, {top-1, top-2}, or all classes. That
gives the incumbent a coverage, a mean set size and the same shares. It is
reported on the raw distribution and on the temperature-scaled one, because
the map requires bands to be calibrated after scaling, and the shift shows what
scaling alone would do to the verdicts users see. Conformal is also run at the
incumbent's own coverage, so the two are compared at matched coverage, which
is the comparison E15 asks for.

**This is not an experiment arm.** It trains nothing and computes no McNemar
contrast, so `evaluation.contrasts` does not apply. It is a calibration analysis
of one arm's stored predictions.

## Alternatives Considered

- **Patch-level temperature on the logits.** Rejected for this study. It needs
  per-patch logits stored per fold, which means re-running the arm with a
  different artifact. It also calibrates a quantity the app does not show: the
  app shows the mean of patch softmaxes.
- **Fitting on all predictions and reporting the error on the same ones.**
  Rejected. The error would flatter the temperature by exactly the overfit the
  cross-fitting removes.
- **Adaptive prediction sets (APS) instead of 1 − p(true).** Deferred. With four
  classes, the simpler score already maps onto ADR 0011's set sizes. APS adds
  randomisation, which a verdict users read should not have.
- **Publishing the temperature now.** Rejected (SPEC 0095). Raising the
  displayed confidence on dish photographs risks overconfidence on sheet ones.

## Scope

- Includes:
  - `ml/src/calibration.py`: the temperature fit and its application, the
    conformal threshold and sets, and the ADR 0011 rule as sets.
  - `ml/src/calibration_study.py`: the cross-fitted study over an arm's stored
    predictions, written to `calibration_study.json`, with a
    `python -m src.calibration_study --version v1 --arm descriptors` entry point.
  - `ml/tests/test_calibration.py` and `ml/tests/test_calibration_study.py`:
    hand-checked fixtures, and the cross-fitting proven by construction.
  - The run on `v1`, recorded in `docs/ml/calibration-study.md`, with a pointer
    from the map's C2 section.
- Does NOT include:
  - Any `spec.json` field, any app change, or any change to ADR 0011's
    constants. Adopting either result is a later decision, after the A4-sheet
    photographs, with an ADR 0011 amendment if the bands change.
  - The out-of-distribution score (#194) and the dispersion metric.

## Acceptance Criteria

- `test_the_temperature_minimises_the_negative_log_likelihood`: on a fixture
  with a known optimum, the fit lands within 1e-6 of it. A temperature of 1
  leaves a distribution unchanged.
- `test_a_temperature_keeps_the_argmax`.
- `test_the_conformal_threshold_is_the_finite_sample_quantile`: on hand-counted
  scores, the threshold is the ⌈(n + 1)(1 − α)⌉-th smallest. It is infinite, so
  every class is in the set, when that rank exceeds n.
- `test_conformal_sets_map_onto_the_verdicts`: sets of one, two, three and zero
  classes give the expected verdicts.
- `test_the_adr_0011_rule_matches_the_dart_constants`: each boundary case of
  `fromDistribution` gives the same verdict and set.
- `test_nothing_is_scored_on_what_fitted_it`: in the study, the predictions
  that fit fold k's temperature and threshold never include fold k's
  photographs.
- `test_the_study_reports_every_level_and_both_distributions`: the JSON carries
  each α, the matched-coverage run, and the incumbent on both the raw and the
  scaled distribution, each with the photograph and group counts it rests on.
- The `v1` run is recorded in `docs/ml/calibration-study.md`:
  - the calibration error before and after the temperature;
  - the temperatures;
  - the conformal table;
  - the incumbent beside conformal at matched coverage.

## Reproducibility

```sh
cd ml
python -m pytest tests/test_calibration.py tests/test_calibration_study.py -q
python -m pytest tests/ -q
python -m src.calibration_study --version v1 --arm descriptors
```

The study needs the `descriptors` arm's predictions, which
`python -m src.crossval --version v1 --arm descriptors` writes.

## Risks and Assumptions

- **Assumption: exchangeability, approximately.** Calibration scores come from
  the other folds' models, not the scored fold's (cross-conformal). Photographs
  of one sample share a fold, so they are never split across calibration and
  scoring. The marginal coverage guarantee is approximate under both, and the
  study reports the empirical coverage rather than assuming it.
- **Risk: small calibration sets.** About 134 photographs calibrate each fold.
  At α = 0.05 that is a rank near the top, so the threshold is coarse. The
  counts are reported beside it.
- **Dish photographs, not sheet ones.** Every number describes the archive. The
  procedure is what carries over to the sheet photographs, and the numbers do
  not (ADR 0026).
- **Merge order:** stacked on #309 (SPEC 0095), whose `calibration.py` it
  extends. It merges after #309, #308 (0096) and #310 (0097), and before 0099.
