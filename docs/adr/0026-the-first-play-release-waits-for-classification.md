# ADR 0026: The first Play release waits for classification

## Status

Accepted 2026-09-29, promoted from
[SPEC 0088](../specs/0088-settle-what-the-first-play-release-waits-for-and-its-id.md)
at the Spec Gate. It answers #266, the first decision of the Google Play epic
#265, which the Developer took on 2026-09-29.

## Decision

**VisioSoil's first release on Google Play ships only when a photograph taken
in the app gets a texture class.** That means the A4-sheet reader measures a
scale on the device, and the descriptor path
([ADR 0024](0024-the-descriptor-path-is-the-v1-classifier-computed-in-dart-from-a-contract-of-numbers.md))
runs on what it measured. Until then, no build goes to a Play track beyond
internal testing.

**The listing claims no accuracy figure** until one has been measured on
photographs captured the way the app captures them. The listing may name the
classes the model distinguishes, and say that the result is an estimate with a
confidence.

## Why

**The product the README, the onboarding and the listing describe is soil
texture classification.** A release without it would have to rewrite all three
for a different product: the in-app copy (#281), the capture instructions
(#282) and the store listing (#294). It would also collect ratings on that
other product, and a listing keeps its ratings.

**The only accuracy that exists was measured on something else.** E0's
cross-validated estimate of the released procedure is group accuracy 0.6883
and photograph macro-F1 0.6232 (`docs/ml/e0-verdict.md`). It was measured on
Petri-dish photographs of the laboratory's archive. The app photographs soil on
an A4 sheet (ADR 0017), and nothing has measured what that shift costs. A
number quoted to a user who captures on paper would describe a measurement
nobody took for that user. A caveat beside it would be standing in for that
missing measurement.

## Considered Options

- **Ship a georeferenced field notebook first.** v1 would capture, locate,
  catalog and share samples, and say classification is coming. The UI would
  stop promising a result, and the tips section would stay hidden until a
  record can be classified. Rejected by the Developer on 2026-09-29. It would
  have reached the store sooner and independently of the A4-sheet reader, at
  the cost of the rewrite and the ratings described under Why.
- **Quote E0's accuracy with a caveat.** It is honest about where the number
  came from. Rejected for the reason in the second paragraph of Why.

## Consequences

- **The A4-sheet reader is the Play release's critical path.** It is the next
  item of the implementation map (A6 Dart (2)'s second half). It is blocked on
  test photographs taken on an A4 sheet, and on the decision about how the
  rectified photograph is resampled.
- **The honest-scope issues of #265 change meaning.** #281 and #282 no longer
  remove the promise of a result. They align the copy and the capture
  instructions with the classifier that will ship. The tips surface stays as
  designed, reachable from a classified record.
- **An accuracy measurement on A4-sheet captures becomes worth having**, because
  it is what would let the listing state a number. It needs labelled
  photographs taken the way the app captures, which the closed dataset does
  not hold (ADR 0016). So it is not scheduled here.
- The Minimum Functionality and Misleading Claims risks #266 names are met by
  shipping the feature, rather than by withholding the promise of it.
