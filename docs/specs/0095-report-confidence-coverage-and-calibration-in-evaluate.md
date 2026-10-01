# SPEC: feat(ml): report confidence, coverage and calibration in evaluate

## Problem

The app shows each photograph's class distribution and a confidence banner, but
nothing in `ml/` measures how far that distribution can be trusted.
`ml/src/evaluate.py` reports macro-F1, accuracy, intervals and contrasts. It
does not report the top-1 probability's spread, the margin between the first two
classes, the accuracy left when uncertain photographs are refused, or the
calibration error (#188). C2 cannot calibrate what nothing measures. ADR 0016
also puts the cost-weighted confusion matrix here, and it is still not computed.

## Design Decision

**A new module, `ml/src/calibration.py`, computes the figures from stored
predictions, and `arm_metrics` writes them into `metrics.json`.** They are pure
functions over labels and distributions, with no model and no TensorFlow, which
is `evaluate.py`'s own rule.

**The level is the photograph**, because the app shows one photograph's
distribution, never a group's. As with the primary number, each repeat pools its
k test sides, and each figure is computed per repeat. The expected calibration
error is also summarised across repeats as a median and a range. Every figure
names the photographs and groups it rests on. **No interval is attached.**
Photographs of one sample are not independent, so an interval on a photograph
count would overstate the evidence, and these figures describe a run rather than
estimate a population.

What each repeat gains, under `confidence`:

- **`top1`**: the 10th, 50th and 90th percentiles of the top-1 probability.
- **`margin`**: the same percentiles of the top-1 probability less the top-2.
- **`calibration`**: the expected calibration error over 10 equal-width bins of
  the top-1 probability on [0, 1], weighted by bin count. The bin count is
  recorded, because the error is sensitive to it. The reliability curve comes
  with it: per bin, the count, the mean top-1 probability and the accuracy. An
  empty bin records its count as 0 and the other two as null, never as 0.
- **`sweep`**: the coverage and the accuracy among covered photographs at each
  threshold on the top-1 probability (0.25 to 0.95 in steps of 0.05) and on the
  margin (0.00 to 0.90). A photograph is covered when its figure reaches the
  threshold. The sweep is reported overall and per predicted class, since
  per-class bands would be keyed by the top-1 class (#243). The per-class records
  carry `headline: false`, as `per_class` does. A threshold that covers nothing
  reports its accuracy as null.

**The cost-weighted confusion matrix is reported by severity tier, not by
weight.** ADR 0016 approved an ordering of the confusions: most serious,
serious, moderate, mild. It gave no numbers, and inventing weights would encode a
claim about management cost that nobody made. So the photograph and group
confusions are counted per tier, pooled over repeats, as the confusion matrix
already is. The tier table lives in `calibration.py`, keyed by ADR 0016's class
names, and is symmetric. When an arm's classes are not those four, the block is
null and records why.

## Alternatives Considered

- **Calibration at the group level.** Rejected as the reported level. A group's
  distribution is a mean the app never shows, and averaging photographs already
  pulls probabilities toward the middle, which would flatter the calibration of
  what users actually see.
- **Fitting a temperature here.** Rejected for this spec. It is C2's next step,
  and it changes `spec.json`, which makes it a contract change with its own
  spec. Reporting first means the fit can be judged against a measured baseline.
- **Numeric cost weights, such as 4, 3, 2 and 1.** Rejected. ADR 0016 recorded
  an ordering, and turning it into a ratio would be a new claim, which is the
  Developer's to make.
- **Adaptive (equal-mass) bins for the expected calibration error.** Rejected as
  the default. Equal-width bins are the convention the reliability diagram reads
  against, and the bin count is recorded either way.

## Scope

- Includes:
  - `ml/src/calibration.py`: percentiles, margins, the expected calibration
    error with its reliability curve, the two sweeps, and the severity counts.
  - `ml/src/evaluate.py`: `arm_metrics` writes `confidence` into each repeat's
    record, the error's summary across repeats, and `severity`. The printed
    summary names the error.
  - `ml/tests/test_calibration.py`: each computation against a hand-checked
    fixture. `ml/tests/test_crossval.py`: `arm_metrics` carries the new blocks.
  - One run of the `descriptors` arm on `v1`, on this machine. The figures for
    the adopted model's uncalibrated distribution are recorded in the map's C2
    section.
- Does NOT include:
  - Temperature scaling, the verdict bands, conformal prediction (#193), or any
    `spec.json` change. Those are C2's next specs.
  - Reading bands in Dart (#243) or any app code.
  - The out-of-distribution score (#194) and the patch dispersion metric.
    `predictions.json` stores photograph distributions, not patch ones.
  - Numeric cost weights.

## Acceptance Criteria

- `test_percentiles_match_a_hand_checked_fixture`: the top-1 and margin
  percentiles of a fixed set of distributions equal hand-computed values.
- `test_the_calibration_error_matches_a_hand_computed_value`: the error, and the
  reliability curve's counts, means and accuracies, equal hand-computed values,
  with the bin count recorded.
- `test_an_empty_bin_reports_no_mean_and_no_accuracy`: null, not 0.
- `test_the_sweep_reports_coverage_and_accuracy_at_coverage`: overall and per
  predicted class, on the top-1 probability and on the margin.
- `test_a_threshold_covering_nothing_reports_no_accuracy`: null, not 0.
- `test_confusions_are_counted_by_severity`: each off-diagonal pair falls in
  ADR 0016's tier in both directions, and the tiers and the diagonal account for
  every photograph.
- `test_severity_is_absent_for_another_class_list`: null, with the reason.
- `test_arm_metrics_reports_confidence_per_repeat`: `arm_metrics` carries the
  blocks per repeat, the error's median and range, and `severity`, with the
  photograph and group counts they rest on.
- The `descriptors` run on `v1` is recorded in the map's C2 section:
  - the median error and its range across repeats;
  - the top-1 and margin medians;
  - the accuracy at a top-1 threshold of 0.50, with its coverage.

  The record states whether the run's primary number matches E0's 0.6232.

## Reproducibility

```sh
cd ml
python -m pytest tests/test_calibration.py tests/test_crossval.py -q
python -m pytest tests/ -q
python -m src.crossval --version v1 --arm descriptors
```

## Risks and Assumptions

- **Assumption: the stored distributions are the ones the app would show.**
  The `descriptors` arm scores a photograph as the mean of its patch
  distributions, which is what `DescriptorContract.distribution` computes.
- **Risk: small bins.** About 150 scored photographs a repeat over 10 bins
  leave some bins with a handful of photographs. The counts are recorded beside
  every bin so that the curve is not over-read.
- **Risk: dish photographs, not sheet ones.** The figures describe the archive's
  dish photographs. The app classifies photographs of the A4 sheet, so its
  calibration there is owed to the same real-photograph validation as the
  reader (ADR 0026).
