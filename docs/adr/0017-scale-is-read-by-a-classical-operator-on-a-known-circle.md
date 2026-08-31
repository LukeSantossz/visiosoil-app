# Scale is read from an object of known size by a classical operator: the dish rim in the dataset, the A4 sheet in the application, and a photograph without one is refused

VisioSoil establishes millimetres per pixel per photograph rather than assuming
it. The dataset reads the Petri dish rim; the application reads the edges of the
A4 sheet the sample is presented on. Both are objects of known size found by
deterministic geometry — contour extraction and a fitted circle or quadrilateral
— with no learned model, no annotation and no second artifact. A photograph in
which the reference cannot be found is **refused**, never analysed at a guessed
scale.

## Status

Accepted 2026-08-25. Amends
[ADR 0009](0009-fixed-roi-and-heuristic-quality-gate-over-segmentation.md) on
one point and narrows its central thesis on another. Resolves the open input
registered as question 6 in `docs/architecture/ml-implementation-map.md` §7,
and the issue that tracked it (#184).

## Context

Textural class is a statement about **particle size**, and particle size in an
image is meaningless without a known scale: coarse grains photographed far away
and fine grains photographed close produce the same pixels. Scale is not a
nuisance variable on this task. It is a precondition for the signal to exist.

ADR 0014 recorded this as the programme's dominant risk on the premise that the
dataset's scale was constant and the application's was not. The audit behind
[ADR 0016](0016-dataset-is-the-existing-dish-archive-and-siltosa-is-out-of-v1.md)
showed the dataset's scale spans a factor of 2.6, so **neither side has a
constant scale**. That makes the problem larger and, unexpectedly, easier: a
quantity that has to be measured on one side may as well be measured on both,
and the same mechanism serves both.

### The amendment to ADR 0009

ADR 0009 rejected "detector then classifier" citing "bounding-box annotation
instead of masks, and a second model in the inference path". That objection is
about **learned** detection: a model to train, annotate, version, convert and
verify.

Finding a circle of known diameter, or a white quadrilateral of known
dimensions, is none of those things. It is a deterministic operator over pixels
with no parameters to learn and nothing to annotate — the same category as the
centred-square crop ADR 0009 already permits, and the same category ADR 0014
conceded when it wrote that *"a circle of known diameter [is] detectable without
any model"*.

**The stated objection does not reach the classical route, and this record says
so explicitly** so that no later argument cites ADR 0009 against it. What ADR
0009 rejected stays rejected: no segmentation model, no learned detector, no
second `.tflite` in the inference path.

### The narrowing of ADR 0009's central thesis

ADR 0009 decided that **one set of acceptance criteria governs both the dataset
and the application**, and that two sets would let the populations drift.

That thesis cannot survive unqualified here, because the two sides now read
different objects. Applying the application's rule to the dataset would refuse
all 194 archive photographs, none of which contains an A4 sheet.

The criteria set therefore splits in two, and the split is the point rather than
a compromise:

| Layer | Scope | Shared? |
|---|---|---|
| Photographic quality — blur, exposure, clipping, effective resolution, contrast, colour cast, specular | properties of the photograph | **Yes**, one definition, two implementations, held together by the committed golden |
| Scale source — which object carries the reference and how it is found | properties of the arrangement | **No.** Dish rim on the dataset side, A4 sheet on the application side |

ADR 0009's reasoning holds for the first row and never applied to the second,
which did not exist when it was written.

## Decided

- **Both sides measure; neither assumes.** Every photograph carries a measured
  millimetres per pixel. The dataset records it in the manifest as
  `disc_diameter_px`; the application computes it at capture time.

- **Both sides normalise to one canonical scale**, so a patch cut on one side
  covers the same physical area as a patch cut on the other. The canonical value
  is set by the **coarsest photograph retained**, never by the median, because
  resampling toward a coarser scale destroys detail a more distant camera would
  also not have resolved, while resampling toward a finer one invents grain
  structure that was never photographed. The direction is one-way and the
  canonical scale is the floor of the kept distribution.

- **The application's reference is the A4 sheet, and the sheet is otherwise
  bare.** No printed marker, no coin, no physical mould. A4 is 210 × 297 mm, so
  four detected corners give both millimetres per pixel and the homography that
  corrects tilt — more than a circle recovers. The project owner's constraint
  was a clean sheet with nothing on it, and the sheet satisfies it by being the
  reference itself.

- **No reference found is a refusal, with a named cause.** It joins the failure
  taxonomy of [ADR 0015](0015-classification-reports-a-named-failure-cause.md)
  rather than degrading to a default. The two ways this happens are a pale sheet
  on a pale surface, where no edge exists to find, and a sheet cropped by the
  framing. Both are actionable and the message says which.

  A guessed scale is worse than no scale: it rescales the input silently and the
  classification is then confidently wrong, with nothing on screen indicating
  that the number rests on an assumption. This is the same reasoning ADR 0015
  used to refuse a silent fallback for a missing contract.

- **The scale is read before the crop.** Both the region of interest and the
  patches are defined in millimetres (ADR 0018), so the reference has to be
  resolved on the full frame first. SPEC 0035 currently specifies a centred-square
  crop with nothing before it, and gains this step.

## Considered Options

- **A printed fiducial marker on the sheet** — the strongest option on
  reliability: self-identifying, sub-pixel corners, full pose recovery. Rejected
  by the project owner's requirement that the sheet carry nothing but itself.
  Recorded because it is the cheapest lever if the sheet's corners prove hard to
  find in practice, and because it is strictly better than the coin on every
  axis.
- **A coin of known denomination** — rejected on three grounds, any one
  sufficient. Brazilian coins span 20 to 27 mm, a 35 % spread, so a perfect
  detector still has no per-image ground truth without a denomination column
  nobody has. It is a smooth metal disc, so inside the analysed region it lowers
  the blur score and raises the specular fraction, making the quality gate
  penalise compliance. And the collection protocol places it outside the centred
  square, which the crop then removes.
- **A physical mould or spacer fixing the disc diameter or the working
  distance** — rejected. It is reliable and it puts an object in the user's
  pocket that nothing can verify they used. A photograph taken without it is
  indistinguishable from one taken with it.
- **The phone estimating its own distance** from a depth sensor or lens
  metadata — rejected for the first release. It costs the user nothing, which is
  its whole appeal, and its accuracy varies by device in a way that would have to
  be measured device by device before any of it could be trusted. Reconsider if
  sheet detection proves unreliable in the field.
- **Scale-invariant training, discarding absolute particle size** — rejected as
  the primary answer and retained as an experiment arm. It is honest and it
  throws away the quantity the task is defined on. With scale measurable on both
  sides at no user cost, deliberately destroying it needs a measurement, which is
  what the scale-ladder arm exists for.
- **Assume a typical working distance** — rejected outright. It fails silently,
  which is the failure mode this whole record exists to prevent.

## Consequences

- **`InferenceService` gains two operators before preprocessing**: find the
  sheet, and rectify by the homography its corners give. Neither is a model.
  Both belong to the new pipeline spec rather than to SPEC 0035, whose scope is
  the contract file and the failure taxonomy.
- **`spec.json` gains the canonical millimetres per pixel**, because a model
  trained at one canonical scale cannot be served at another. It is a contract
  value in the same sense as the input size.
- **A new failure cause** joins ADR 0015's taxonomy, in the middle column: the
  user can retake the photograph, and the message names whether the sheet was
  absent or cropped.
- **The dataset side needs no new capture.** The dish rim is already in every
  archive photograph; measuring it is a script over files that exist.
- **Tilt correction arrives for free on the application side and not on the
  dataset side.** Four corners of a rectangle recover pose; a circle recovers
  scale and, from its eccentricity, tilt only up to an ambiguity. The archive
  photographs are close to top-down, so the asymmetry is accepted and recorded
  rather than corrected.
- **The one-way resampling rule constrains any future collection**: a rig should
  be set to the finest millimetres per pixel it can achieve, because every unit
  of resolution given away at capture is range no later normalisation recovers.
- ADR 0009's rejection of segmentation and of learned detection is untouched.
  Its one-criteria-set thesis is narrowed to photographic quality, and its
  "detector deferred" line is discharged: the deferral applied to a learned
  detector, and this is not one.
