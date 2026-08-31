# Classification uncertainty is a four-state verdict derived from the margin and the mass, not a confidence percentage

VisioSoil reports a texture reading as one of four verdicts — `conclusive`,
`ambiguous`, `insufficient`, `notAnalysed` — computed from the whole probability
distribution rather than from the top-1 score alone. The app **abstains** when no
class can be asserted, and names **two candidates** when two classes hold the mass
between them. A percentage is never the statement; it is secondary detail beneath
a verdict.

## Status

Accepted, with the presentation rule amended on 2026-08-25.

### Amended 2026-08-25: the app never shows nothing

This record decides that **the app abstains** — below the bar, no class name, no
percentage, no soil-scale colour. The project owner reversed that on 2026-08-25:
a result surface always names the leading class and its percentage.

**The computation is untouched and `ClassificationVerdict` stays.** What changes
is what the interface does with `insufficient`, which is now a banner rather
than a blank. Three things ship with it, and the third and fourth are the
project owner's own wording:

- the leading class and its share are always shown;
- when the verdict is not `conclusive`, the surface carries a **weak-evidence
  warning** naming what is wrong — with four classes, chance is 0.25, so a
  leading share near it is a near-guess presented in the same shape as a
  reading;
- **every result states that it comes from an AI and can be wrong**;
- **when the share is low, the copy tells the user to retake with better light
  or to consult a specialist**, so the screen offers a next step rather than a
  bare number.

The reason recorded here for abstaining — that a greyed-out class name is still
an assertion — is not withdrawn. It is outweighed by the countervailing cost the
owner weighed: a field user who receives no answer at all has nothing to act on,
and an unlabelled blank teaches nothing about why.

**The verdict is computed on an aggregate now.**
[ADR 0018](0018-model-sees-fixed-size-greyscale-patches-and-their-spread-is-a-quality-signal.md)
classifies an overlapping grid of patches per photograph — twenty-five for a
90 mm disc, nine at the refusal floor — and averages them. The shape
of the distribution reaching this record's two quantities is unchanged; what
produced it is not. The **disagreement between those patches is deliberately not
folded into this verdict** — it is an image-quality criterion, because it
measures how evenly the sample was spread rather than how sure the model is, and
the two have different remedies.

### The original status

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
