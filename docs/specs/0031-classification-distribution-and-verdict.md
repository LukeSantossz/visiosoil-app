# SPEC (full): feat(inference): return the full class distribution and derive a verdict band

## Problem

`InferenceService` computes a probability for every class and returns only the
argmax with its probability (`inference_service.dart:243-250`), so the app cannot
tell a well-separated result from a near-tie or from a result too weak to assert,
and presents all three as the same asserted class.

## Design Decision

Add the full distribution to `InferenceResult` and introduce a
`ClassificationVerdict` value type with four members — `conclusive`,
`ambiguous`, `insufficient`, `notAnalysed` — derived from the margin between the
first two candidates together with either the top-1 share (`conclusive`) or the
share the top two hold between them (`ambiguous`):

- `conclusive` when `margin >= 0.15` and `top1 >= 0.50`
- `ambiguous` when `margin < 0.15` and `top1 + top2 >= 0.65`
- `insufficient` otherwise
- `notAnalysed` when there is no result at all

The pair share, rather than the top-1 alone, is what separates a near-tie worth
showing (`0.44 / 0.39`, pair 0.83, the rest noise) from a distribution that
settled nothing (`0.25 / 0.24`, pair 0.49, three classes still in contention).

Keep this spec **non-visual**. `ConfidenceLevel` and every widget that reads it
stay exactly as they are; the verdict type ships unused by the interface. The
spec for roadmap item 2 migrates the UI and retires `ConfidenceLevel`. This spec
also makes the class label order single-source, because `SoilTextureColors`
currently contradicts `InferenceService` while documenting itself as matching it.

The verdict model is recorded as
[ADR 0011](../adr/0011-classification-verdict-from-margin-and-mass.md); the
design rationale and the presentation rules that follow from it are in
`docs/design/ux-2026/08-results-and-uncertainty.md` §2-§3.

## Alternatives Considered

- **A single absolute threshold on top-1** — rejected. With five classes, chance
  is 0.20. A top-1 of 0.55 with a second at 0.50 and a top-1 of 0.55 with a
  second at 0.12 are different situations with different remedies, and no
  single-axis rule separates them. The margin is the quantity that does.
- **`conclusive: top1 >= 0.70 and margin >= 0.15`; `ambiguous: top1 >= 0.45 and
  margin < 0.15`; `insufficient: top1 < 0.45`** — the rule this spec carried when
  it was first drafted, withdrawn while converting its criteria into tests.
  Rejected for two independent defects. The margin conjunct on `conclusive` is
  dead: if the probabilities sum to 1 and `top1 >= 0.70`, then `top2 <= 0.30`
  and the margin is necessarily at least 0.40, so the conjunct never rejects
  anything — the axis does no work where it was placed. And the 0.45 floor put
  `0.44 / 0.39` into `insufficient`, which is the exact near-tie the design
  exists to surface. Recorded here rather than silently replaced because the
  rule reads as correct and its failure is only visible once the arithmetic of a
  normalised five-class distribution is applied to it.
- **Replace `ConfidenceLevel` and migrate the UI in this spec** — rejected. It
  couples a contract change to a visual redesign, putting two unrelated risks
  behind one gate, and it would hold the contract hostage to copy review. The
  contract is independently valuable: it is what specs 2 and 15 both consume.
- **Persist the distribution here** — rejected. That is a v4 → v5 migration and
  it is roadmap item 15, deliberately sequenced last so the persisted shape is
  decided once. This spec adds no column and no migration.
- **Compute the verdict inside `InferenceService`** — rejected. The bands are
  product policy with thresholds that will be recalibrated against validation
  data that does not exist yet. Keeping the policy in a pure domain type means
  recalibration touches neither the isolate nor the service, and the bands stay
  unit-testable without a model.
- **Return the raw `List<double>` and let callers map indices to labels** —
  rejected. Every call site would re-derive the index-to-label mapping, which is
  exactly how the existing `SoilTextureColors` contradiction arose.
- **Renormalise the distribution so it sums to 1** — rejected. If a model ever
  exports logits rather than probabilities, silently renormalising would hide it
  and make the thresholds meaningless while looking correct. The values are
  passed through verbatim.

## Scope

- Includes:
  - `ClassScore` — a label and its probability.
  - `InferenceResult.distribution` — every class, ordered descending. The
    existing `textureClass` and `confidenceScore` keep their names, types and
    meaning.
  - `_runInference` populates the distribution from the output tensor it already
    reads, passing values through without renormalisation.
  - `ClassificationVerdict` — four members, derived on two axes, with the
    thresholds as named constants marked provisional in the source.
  - A single source for the class label order, with `SoilTextureColors` deriving
    its ordering from it rather than declaring its own.
  - A test asserting the label lists agree, so the contradiction cannot return.
- Does NOT include:
  - Any change to a widget, screen, or user-facing string. No UI consumes
    `ClassificationVerdict` in this spec.
  - Retiring or modifying `ConfidenceLevel`, or changing any of its call sites.
  - Any database column, migration, or persistence of the distribution.
  - Threshold calibration against validation data.
  - Any change to `ml/`, to model export, or to preprocessing.
  - The image quality gate and its wiring (SPEC 0030 and roadmap item 6).

## Acceptance Criteria

- distribution_contains_every_class: a run over a five-class output returns a
  distribution of length five, one entry per label.
- distribution_ordered_descending: entries are sorted by probability, highest
  first, and the first entry's label and probability equal `textureClass` and
  `confidenceScore`.
- distribution_is_not_renormalised: given an output tensor whose values sum to
  0.5, the returned probabilities are those values unchanged.
- top1_fields_unchanged: for an output whose argmax is index 3, `textureClass`
  and `confidenceScore` hold the same values they hold before this change.
- incompatible_model_still_rejected: an output tensor whose class count differs
  from the label list returns null, as it does today, and produces no
  distribution.
- verdict_conclusive_on_clear_leader: `0.94 · 0.03 · 0.01 · 0.01 · 0.01` is
  `conclusive`, and so is `0.60 · 0.20 · 0.10 · 0.06 · 0.04`.
- verdict_ambiguous_on_narrow_margin: `0.44 · 0.39 · 0.09 · 0.05 · 0.03` is
  `ambiguous` — margin 0.05, pair 0.83.
- verdict_ambiguous_when_pair_holds_the_mass: `0.48 · 0.44 · 0.04 · 0.02 · 0.02`
  is `ambiguous`, not `insufficient`, despite a top-1 below 0.50.
- verdict_insufficient_when_nothing_leads: `0.25 · 0.24 · 0.22 · 0.15 · 0.14` is
  `insufficient` — margin 0.01, pair 0.49.
- verdict_insufficient_when_leader_lacks_majority: `0.48 · 0.20 · 0.14 · 0.10 ·
  0.08` is `insufficient` — a wide margin does not rescue a leader holding less
  than half with no rival.
- verdict_not_analysed_for_absent_result: a null result yields `notAnalysed`.
- not_analysed_is_distinct_from_insufficient: `notAnalysed` and `insufficient`
  are different members, and no input produces one where the other is meant.
- verdict_is_pure: the same distribution always yields the same verdict, with no
  model, isolate, or asset required to evaluate it.
- label_order_single_source: `SoilTextureColors` and the inference label list
  return the same labels in the same order, asserted directly.
- existing_tests_unmodified: the current 62 test files pass without edits, and no
  file under `lib/core/features/` is modified.
- analyze_clean_tests_green: `flutter analyze` reports no issues; `flutter test`
  passes.

## Reproducibility

- Toolchain: Flutter 3.44.1 / Dart 3.12.1, pinned per `.github/workflows/ci.yml`.
- No model artifact is required. Every criterion above is verified against
  synthetic output tensors through the existing injectable
  `InferenceIsolateEntry` seam, or against `ClassificationVerdict` directly,
  which is a pure function of a distribution.
- Verify: `flutter analyze && flutter test`.
- No randomness, so no seed.

## Risks and Assumptions

- Assumption: the thresholds shipped here are provisional engineering starting
  points, not calibrated values, and are labelled as such in the source. What
  would invalidate them: per-class validation metrics from the ML terminal
  showing the bands do not separate usable from unusable readings. The
  thresholds are named constants precisely so recalibration is a one-line change
  with no structural consequence.
- Assumption: the model outputs probabilities that sum to approximately 1, per
  `ml/README.md` (`Dense(5, softmax)`). If a future model exports logits, the
  thresholds become meaningless. This spec does not detect that condition; it
  refuses to mask it by renormalising, so the failure would be visible rather
  than silent. Detecting it is out of scope and belongs with calibration.
- Assumption: `SoilTextureColors.all` has no consumers today, verified by
  search, so correcting its order breaks nothing. `forClass` is keyed by name
  and is unaffected by ordering.
- Risk: shipping a domain type that no interface reads leaves dead code until
  roadmap item 2 lands. Accepted deliberately — the alternative couples the
  contract to a visual redesign — and bounded by item 2 being the next spec in
  the sequence.
