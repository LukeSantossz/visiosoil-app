# Target isolation is a fixed ROI plus a heuristic quality gate, not segmentation: the capture protocol is enforced rather than compensated for

VisioSoil isolates the soil sample with a fixed central region of interest,
guided by a viewfinder overlay, combined with model-free heuristic quality
checks computed over that region. No segmentation model, no detector, and no
background subtraction is introduced. The same acceptance criteria govern what
enters the dataset and what the app accepts at capture time.

## Status

Accepted, with one claim narrowed on 2026-08-01, one premise amended on
2026-08-11, and two amendments on 2026-08-25.

### Amended 2026-08-25: the classical route was never what this record rejected

[ADR 0017](0017-scale-is-read-by-a-classical-operator-on-a-known-circle.md)
reads scale from an object of known size — the dish rim in the dataset, the A4
sheet in the application — by contour extraction and a fitted shape.

The "detector then classifier" option below is rejected citing *"bounding-box
annotation instead of masks, and a second model in the inference path"*. That
objection is about a **learned** detector: something to annotate, train,
version, convert and verify. A deterministic operator over an object of known
geometry is none of those. It is the same category as the centred-square crop
this record already permits, and ADR 0014 conceded the point in passing when it
wrote that *"a circle of known diameter [is] detectable without any model"*.

**What this record rejects stays rejected**: no segmentation model, no learned
detector, no second `.tflite` in the inference path. The amendment is narrow —
any later argument citing this record against a classical, parameter-free
operator is citing it wrongly, and must cite this amendment too.

### Amended 2026-08-25: the one-criteria-set thesis is narrowed to photographic quality

This record decides that **one set of acceptance criteria governs both the
dataset and the application**. That cannot hold unqualified once the two sides
read different scale references: applying the application's rule to the dataset
would refuse all 194 archive photographs, none of which contains an A4 sheet.

The set splits, and the split is deliberate:

| Layer | Shared? |
|---|---|
| Photographic quality — blur, exposure, clipping, effective resolution, contrast, colour cast, specular | **Yes.** One definition, two implementations, held together by the committed golden file |
| Scale source — which object carries the reference, and how it is found | **No.** Dish rim on the dataset side, A4 sheet on the application side |

The reasoning below applies to the first row and never applied to the second,
which did not exist when this was written.

Two further consequences land on the criteria themselves, both from
[ADR 0018](0018-model-sees-fixed-size-greyscale-patches-and-their-spread-is-a-quality-signal.md):
the region of interest becomes a grid of patches rather than one centred square,
so `minRoiSidePx` is re-scoped to the disc; and a colour-cast threshold stops
being load-bearing, because the model no longer sees colour. Recorded during the 2026-07-30 ML architecture study
(`docs/architecture/soil-classification.md`, §16). SPEC 0030 implements the
acceptance criteria in both languages with a conformance test; wiring the gate
into the capture flow is a follow-up spec, deliberately separated because
`capture_screen.dart` is shared with the UI/UX terminal.

### Amended 2026-08-11: the target shape is known, so the ROI shape is now an open experiment

The rejection of segmentation below is argued in part from a target of unknown
shape against an unknown background. That premise no longer holds. Under the
capture protocol in ADR 0014 the target is a **circle of known diameter,
centred**, in both conditions: soil in a 90 mm Petri dish on the bench, and the
same soil arranged as a disc of the same size on paper.

A circle inscribed in a square fills π/4 ≈ 78.5 % of it, so about **21.5 % of
every ROI this ADR specifies is guaranteed not to be soil**, and it is exactly
the region that differs between the two conditions.

**The decision below stands**, because the alternatives that follow from the new
premise are not segmentation. A circular mask and a crop to the square inscribed
in the circle are fixed geometric conventions, computed from the frame with no
model, no per-scene tuning, and no run-to-run variation — the same category as
the centred square itself. ADR 0014 turns the choice among the three into arms
of experiment E1, so it is settled by measurement rather than by argument.

What this amendment changes is narrower and immediate: **any later argument
citing this ADR's unknown-target premise must cite this amendment too.** The
premise was true when written and is not true now.

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

The domain gap is now an open programme risk rather than a solved one, and no
claim about field accuracy is supportable from this dataset.

**Corrected 2026-08-11.** This previously said the gap's measurability depended
on a paired in-situ photograph of the same sample taken before it left the
field, treating that as an open, irreversible decision in SPEC 0033. That framing
assumed a collection campaign whose samples had not yet been taken. ADR 0014
establishes that the dataset is the laboratory's **existing archive**, already
air-dried and sieved, so no sample in it can yield a paired field view — the
moment passed before this project began, and no decision now recovers it. The
paired photograph is not a pending choice; it is unavailable for these rows.

Measuring the gap therefore requires a **separate in-situ collection** with its
own samples and its own cost, which is deferred. Nothing about that blocks
photographing the archive.

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

- The dataset is collected under the rule the app enforces, so **the two
  populations stop differing in photographic quality**. Framing, focus,
  exposure, and effective resolution are admitted by one criteria set on both
  sides, and an image the app would refuse cannot enter the dataset.

  **This does not close the population gap, and an earlier version of this
  consequence claimed that it did.** The project owner confirmed on 2026-08-01
  that collection photographs are taken on a bench after standard preparation —
  air-dried and sieved — while deployment is in situ. Sieving removes the coarse
  fraction that most distinguishes Arenosa, and air-drying changes colour. The
  subject itself is therefore different, not merely photographed with differing
  care, and no acceptance criterion over pixels can detect or correct that. The
  original claim assumed both sides photograph the same soil; that assumption is
  false.

  What survives is the decision, not the sweeping claim: enforcing the protocol
  is still right, because it removes the one component of the gap that is
  removable. The residue is a genuine domain gap, it is now the dominant
  unmeasured risk in the programme, and **no field-accuracy claim is supportable
  from a bench-collected dataset**. Closing it needs a separate in-situ
  collection with its own samples, deferred per ADR 0014. It does **not** block
  photographing the archive, and the earlier wording here — that it "blocks the
  start of collection" — is corrected under Status above.
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
