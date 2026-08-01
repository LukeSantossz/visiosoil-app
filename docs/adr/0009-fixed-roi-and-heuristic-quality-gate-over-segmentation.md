# Target isolation is a fixed ROI plus a heuristic quality gate, not segmentation: the capture protocol is enforced rather than compensated for

VisioSoil isolates the soil sample with a fixed central region of interest,
guided by a viewfinder overlay, combined with model-free heuristic quality
checks computed over that region. No segmentation model, no detector, and no
background subtraction is introduced. The same acceptance criteria govern what
enters the dataset and what the app accepts at capture time.

## Status

Accepted, with one claim narrowed on 2026-08-01. Recorded during the 2026-07-30
ML architecture study (`docs/architecture/soil-classification.md`, §16).
SPEC 0030 implements the acceptance criteria in both languages with a
conformance test; wiring the gate into the capture flow is a follow-up spec,
deliberately separated because `capture_screen.dart` is shared with the UI/UX
terminal.

### Narrowed: the criteria do not close the subpopulation gap

This ADR decided to **close the collection-versus-deployment gap by enforcing
one capture protocol on both sides**. That reasoning assumed the dataset and the
app photograph the same subject under the same protocol, differing only in how
well the photograph is taken — a difference acceptance criteria can police.

The assumption is false. The dataset is photographed **on a bench, after
standard preparation**: air-dried and sieved (confirmed by the project owner,
2026-08-01, recorded in SPEC 0033). The app photographs soil in place. Sieving
removes the coarse fraction that distinguishes Arenosa, and air-drying changes
colour substantially, so the two are different populations rather than one
population photographed with differing care. No threshold on blur, exposure, or
resolution reaches that difference.

What survives unchanged:

- the fixed centred-square ROI, and the rejection of segmentation and detection;
- the rejection of background subtraction on mechanism;
- one criteria set with two implementations, held together by a golden file.
  These remain worth having: they stop *bad photographs* entering either side.

What no longer holds:

- the claim that applying one criteria set to both sides closes the
  subpopulation gap. It closes the photographic-quality gap only.

The domain gap is now an open programme risk rather than a solved one. Whether
it is measurable at all depends on collecting a paired in-situ photograph of the
same sample before it is removed from the field, which is irreversible per
sample and is an open decision in SPEC 0033. Until that decision is made and the
gap is measured, no claim about field accuracy is supportable from this dataset.

### Decided

- **One set of acceptance criteria, two implementations** — applied at
  collection time the criteria define what enters the dataset; applied in the
  app they define what production is allowed to produce. A Python reference
  implementation audits the dataset, a Dart implementation runs the gate, and a
  conformance test requires both to return the same verdict on the same
  fixtures. Two divergent sets would reopen the domain gap the gate exists to
  close.
- **Enforce the protocol rather than compensate for its absence** —
  `lib/core/features/onboarding/onboarding_screen.dart:24-49` already declares a
  capture protocol (coin for scale, soil filling at least 70% of the frame,
  diffuse natural light, no flash, top-down at roughly 20 cm) that no code
  checks. Narrowing the production distribution to match the collection
  distribution is cheaper and more reliable than training a model invariant to
  every way the protocol can be broken.
- **No fill measurement in phase one** — measuring "soil occupies at least 70%"
  requires separating foreground from background. The fixed ROI defines the
  region without measuring what is inside it. A false block is worse than a
  marginal image entering the dataset, and there is no data with which to
  calibrate a fill threshold.
- **The gate always has an override** — the user can capture anyway; the record
  stores which criteria failed; telemetry counts the block rate per criterion.
  A gate without an escape is a way to stop an agronomist from working.

## Considered Options

- **Classical segmentation (HSV threshold, morphology, GrabCut)** — rejected for
  now: cheap, but brittle against shadow, dry vegetation, and soil whose colour
  overlaps the background. It would need per-scene tuning that the fixed ROI
  makes unnecessary.
- **Lightweight segmentation model (DeepLabv3 or U-Net on a MobileNet backbone)**
  — rejected for now: technically sound and 1–3 MB quantized, but it requires a
  new annotation campaign producing pixel masks, on a dataset that does not yet
  exist. It also adds 20–60 ms and a second artifact to version, convert, and
  verify. Reconsider only if telemetry shows framing is the dominant failure
  mode.
- **Detector then classifier (SSD-MobileNet or a nano YOLO)** — rejected for
  now: same objection, with bounding-box annotation instead of masks, and a
  second model in the inference path. The coin the onboarding already asks for
  would give a real millimetres-per-pixel scale if detected, which is the
  strongest argument for this option and the reason it is deferred rather than
  discarded.
- **Background subtraction** — rejected on mechanism, not on cost. It models a
  background from a temporal sequence or a stable scene. The app takes a single
  photograph of a new scene through `ImagePicker`
  (`lib/core/features/capture/capture_screen.dart:95-100`). There is nothing to
  subtract.
- **No isolation at all (the status quo)** — rejected: it is what produces the
  domain gap, and it gives the user no signal that a capture was unusable.
- **Fixed ROI plus heuristic quality gate (chosen)**.

## Consequences

- The dataset is collected under the rule the app enforces, so the controlled
  dataset stops being a subpopulation distinct from the one seen in production.
- The ROI crop must be applied identically in both places. If the dataset is
  cropped and the app is not, or the two crops differ, this ADR's central claim
  fails silently.
- Quality criteria become part of the model contract: `ClassificationResult`
  carries the `qualityFlags` that failed, so the UI can name what to fix rather
  than refusing without explanation.
- Block rate per criterion becomes a monitored metric with a recalibration
  threshold, because a gate tuned too tight is a product defect that looks like
  a quality improvement in every other metric.
- Segmentation and detection stay available as later increments. Nothing decided
  here forecloses them, and the criteria set is where a fill measurement would
  be added if one is ever justified.
- `docs/design/ux-2026/06-capture-experience.md` §3 reaches the same conclusion
  from the presentation side and states the constraint this ADR must honour: the
  "target not found" and "multiple targets" states have no available signal, and
  neither may be simulated by a colour or saturation heuristic standing in for
  detection. The fixed ROI does not simulate them. It is a geometric convention
  applied unconditionally, carrying no claim about what is inside it, and it
  leaves that document's `TargetSignal` without a producer in phase one, which
  is the correct state.
