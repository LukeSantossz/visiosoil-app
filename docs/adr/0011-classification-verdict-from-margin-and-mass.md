# Classification uncertainty is a four-state verdict derived from the margin and the mass, not a confidence percentage

VisioSoil reports a texture reading as one of four verdicts — `conclusive`,
`ambiguous`, `insufficient`, `notAnalysed` — computed from the whole probability
distribution rather than from the top-1 score alone. The app **abstains** when no
class can be asserted, and names **two candidates** when two classes hold the mass
between them. A percentage is never the statement; it is secondary detail beneath
a verdict.

## Status

Accepted. Promoted at the Spec Gate for
[`docs/specs/0031-classification-distribution-and-verdict.md`](../specs/0031-classification-distribution-and-verdict.md),
whose Design Decision it records. Design rationale and the presentation rules
that follow from it are in
[`docs/design/ux-2026/08-results-and-uncertainty.md`](../design/ux-2026/08-results-and-uncertainty.md).

### Decided

- **Four states, not a graded score.** `conclusive`, `ambiguous`,
  `insufficient` and `notAnalysed`. `notAnalysed` is a distinct member rather
  than the bottom of the scale: "no attempt was made" and "the attempt settled
  nothing" have different remedies, and the current `ConfidenceLevel.fromScore(null)
  => low` conflates them.
- **Two quantities decide it** — the margin `top1 - top2`, and either the top-1
  share or the share the top two hold together:
  - `conclusive` when `margin >= 0.15` and `top1 >= 0.50`
  - `ambiguous` when `margin < 0.15` and `top1 + top2 >= 0.65`
  - `insufficient` otherwise
- **The pair share is what separates ambiguous from insufficient.** At
  `0.44 / 0.39` the top two hold 0.83 and the remainder is noise: the model
  narrowed the answer to two textures, which is information worth showing. At
  `0.25 / 0.24` the top two hold 0.49 with three classes still in contention: the
  model narrowed nothing. Their top-1 scores are close; their meanings are not.
- **The app abstains.** Below the bar, no class name and no soil-scale colour
  appear at all. A greyed-out or low-confidence class name is still an assertion.
- **The distribution is never renormalised.** Values pass through as the model
  produced them, so a model that ever exports logits rather than probabilities
  fails visibly instead of yielding meaningless verdicts that look correct.
- **The policy is a pure domain type, not part of the inference service.** The
  thresholds are product policy awaiting calibration; keeping them out of the
  service and the isolate means recalibration touches neither, and the bands stay
  unit-testable with no model artifact present.
- **The thresholds are provisional.** No validation metrics are published yet.
  The *structure* — two quantities, four states — is what this record decides;
  the constants are labelled placeholders.

## Considered Options

- **A single absolute threshold on the top-1 score (the status quo shape)** —
  rejected. With five classes chance is 0.20, and one number cannot distinguish
  `0.55` with a second at `0.50` from `0.55` with a second at `0.12`. The current
  `ConfidenceLevel` does exactly this, which is why a 25 % argmax and a 94 % argmax
  differ only by a badge tint.
- **`conclusive: top1 >= 0.70 and margin >= 0.15`; `ambiguous: top1 >= 0.45 and
  margin < 0.15`; `insufficient: top1 < 0.45`** — the first form of this rule,
  withdrawn while its acceptance criteria were being converted into tests.
  Rejected for two independent defects, recorded because the rule reads as
  correct and its failure is visible only once the arithmetic of a normalised
  five-class distribution is applied. First, the margin conjunct on `conclusive`
  is dead: `top1 >= 0.70` forces `top2 <= 0.30`, so the margin is necessarily at
  least 0.40 and the test never rejects anything. Second, the 0.45 floor placed
  `0.44 / 0.39` into `insufficient` — the exact near-tie the design exists to
  surface.
- **Shannon entropy of the distribution as the uncertainty measure** — rejected.
  It is a sound scalar and a poor product primitive: it has no interpretation a
  field user can be told, its threshold has no intuitive meaning, and above all it
  does not say *which* classes are competing. The ambiguous state needs the two
  contenders by name, and entropy discards exactly that.
- **Always show the top two, whatever the verdict** — rejected. On a clear
  reading the second class is noise, and displaying it manufactures doubt where
  the model has none. The second candidate appears when it is a candidate.
- **Keep reporting only the percentage and improve the copy around it** —
  rejected. It leaves the structural dishonesty intact: a plurality among five
  classes would still be presented as a reading, with better wording.
- **Compute the verdict inside `InferenceService`** — rejected. It would put
  product policy behind the model boundary, make recalibration a change to the
  inference path, and require a model artifact to test a rule that is pure
  arithmetic.

## Consequences

- `InferenceResult` carries the full distribution. The existing `textureClass`
  and `confidenceScore` keep their names, types and meaning, so no current
  consumer changes.
- **The interface must be able to say nothing.** Every result surface needs a
  state with no class, no percentage and no soil-scale colour — a shape the
  current screens have no provision for.
- **`insufficient` is not styled as an error.** Nothing failed; the model does
  not know. Reserving `error` for genuine failures is a direct consequence of
  treating abstention as a valid outcome rather than a fault.
- **`notAnalysed` is not yet an honest signal, and the decision is to ship it
  anyway with the limit written down.** It is derived from
  `InferenceService.classify` returning `null`, and `null` today means six
  different things: a missing model asset, an isolate spawn failure, a timeout,
  a decode failure, a class-count mismatch, and an inference error. Only the
  first is genuinely "not analysed"; the rest are failures, and a failure
  presented as an absence hides the retry the user should be offered.

  This decision does not fix that, because fixing it changes the return type of
  `classify` and belongs with the vision workstream's `spec.json` runtime
  contract (item A4), which has to touch that signature regardless. The
  consequence accepted here is narrow and explicit: **no result surface may
  offer retry on `notAnalysed` until A4 lands**, since it cannot know whether
  anything is retryable. Offering it would produce a button that silently does
  nothing when the model was never in the build.
- The verdict is derived, not stored. Until the distribution is persisted
  (roadmap item 15), a record reopened from history renders from its top-1 alone
  and an ambiguous reading reappears as a plain low-confidence one. This is a
  known, bounded gap, and the reason persisting the distribution is on the plan
  rather than optional.
- Thresholds become a calibration obligation on the ML terminal. Shipping them
  uncalibrated is acceptable only because they are labelled as such and are
  named constants; leaving them uncalibrated indefinitely is not.
- Nothing here forecloses a richer uncertainty model later — per-class
  calibration curves, temperature scaling, or a learned abstention head. The
  verdict is computed from the distribution at one place, which is where any of
  those would be substituted.
