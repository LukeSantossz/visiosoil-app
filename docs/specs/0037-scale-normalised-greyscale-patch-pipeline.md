# SPEC: feat(inference): normalise by a measured scale and classify a greyscale patch grid in both languages

## Problem

The transformation that decides what the model sees does not exist in either
language, and the three decisions taken on 2026-08-25 replace it entirely rather
than adjust it.

Today `ml/src/preprocess.py:48` resizes the whole frame to 224×224 and
normalises; `InferenceService._runInference` does the same with
`img.copyResize`. Neither crops a region of interest, neither bakes EXIF
orientation, neither reads a scale, neither converts to greyscale, and neither
cuts patches. `roi_bounds` (`ml/src/image_quality.py:123`) is computed by the
quality analyzer and consumed by nothing else, so the acceptance criteria
currently police a region no model is ever shown.

Three records now specify a different path.
[ADR 0017](../adr/0017-scale-is-read-by-a-classical-operator-on-a-known-circle.md)
requires a measured millimetres-per-pixel per photograph, read from the dish rim
on the dataset side and the A4 sheet on the application side, with a refusal when
neither is found.
[ADR 0018](../adr/0018-model-sees-fixed-size-greyscale-patches-and-their-spread-is-a-quality-signal.md)
requires patches of a fixed **physical** size, greyscale, a mean over their
distributions, and their disagreement reported as a quality criterion rather than
a confidence.
[ADR 0016](../adr/0016-dataset-is-the-existing-dish-archive-and-siltosa-is-out-of-v1.md)
makes the dataset 194 dish photographs whose scale spans a factor of 2.6, so the
normalisation is not optional tidiness — without it the training set contains the
same soil at 2.6 different apparent sizes with no way to tell them apart.

**Why this is not SPEC 0035.** That specification reads the contract file and
separates the failure causes. It explicitly puts the pixels out of scope, and its
crop is a single centred square with nothing before it. The work here is a
different transformation with a different shape, and folding it into an approved
spec would replace what the Gate approved.

## Design Decisions

The decisions themselves are in ADR 0016, 0017 and 0018. What this spec decides
is how they are realised, and three points are choices rather than transcription.

### One reference reader per side, behind one interface

Both sides answer the same question — how many millimetres does a pixel cover —
and find it in different objects. The interface is the answer plus a failure;
the implementations are a fitted circle and a fitted quadrilateral. Neither
learns anything, neither is a `.tflite`, and ADR 0017 records why that is not
what ADR 0009 rejected.

The application additionally rectifies by the homography the sheet's four
corners give, which corrects tilt as well as distance. The dataset side does not:
a circle recovers scale and tilt only up to an ambiguity, and the archive
photographs are near top-down. **That asymmetry is accepted and recorded, not
corrected**, because correcting it would require the dataset side to detect
something it does not contain.

### The canonical scale is a contract value, set by the floor of the kept data

Resampling is one-directional. Toward a coarser scale it destroys detail a more
distant camera would also not have resolved; toward a finer one it invents grain
structure that was never photographed, and a model trained on interpolated grains
learns the interpolator.

So the canonical millimetres per pixel is the **coarsest photograph retained**,
not the median, and it is published in `spec.json` because a model trained at one
canonical scale cannot be served at another. Measured over the 92 readable
archive JPEGs: p5 is 0.130 mm/px, p50 is 0.100, and the single coarsest is 0.174.
**The value ships as 0.130 mm/px**, which upsamples nothing at or above the fifth
percentile and refuses the tail below it.

~~**It is provisional on #196.**~~ **Recomputed and confirmed, 2026-09-03**, by
[SPEC 0052](0052-read-the-dish-rim-and-recompute-the-canonical-scale.md) (#212),
over all 221 photographs of `v1` with a committed reader and a committed record.
Every photograph read; none was quarantined. The canonical comes out at
**0.1292 mm/px**, six parts in a thousand from the 0.130 above, so the value
ships as measured and the geometry below stands: the patch side moves by that
same fraction, to 20.7 mm at 160 px, and the patch counts step in whole squares
and do not move at all.

The paragraph this replaces read that the value was provisional because the
distribution had been measured over the 92 readable JPEGs while the 129 HEIC
files, 58 % of the set, could not be opened. That is why the recomputation was
required and it is what SPEC 0052 did. Two of its numbers move with it: the
archive's scale spread is **4.83×**, not the 2.6× measured without the HEIC
session, and the eleven photographs coarser than the canonical — the tail this
value refuses rather than upsamples — are all in the transported population,
which SPEC 0040 D6 already holds to training, so the splittable pool does not
shrink.

Setting it at the median instead would have discarded half the archive, in a
dataset where one class already holds three samples.

### Greyscale is computed by the luma already shared between the languages

`ml/src/image_quality.py` and `lib/core/services/image_quality/` both apply
ITU-R BT.601 at 0.299 / 0.587 / 0.114, and a committed golden file already proves
they agree. The model path calls the same function rather than introducing a
second definition, so there is exactly one place where the two languages could
diverge on colour and it is already pinned by a test.

The tensor keeps three channels with the grey value replicated, so MobileNetV2's
ImageNet weights load unchanged.

## Alternatives Considered

- **Extend SPEC 0035 rather than write this** — rejected. SPEC 0035 is
  Gate-approved with the pixels out of scope; adding a scale reader, a rectifier,
  a patch grid and an aggregation would replace what was approved rather than
  implement it. The two specs land in order, and SPEC 0035's schema is revised to
  carry this one's values.
- **A shared cross-language resampling kernel**, so both sides produce identical
  pixels — rejected, for the reason `ml-implementation-map.md` already gave
  against it: disproportionate for a difference nothing has measured. What is
  asserted instead is the geometry and the order, plus the committed table of
  dimensions both languages check against.
- **Patch size in pixels rather than millimetres** — rejected in ADR 0018. It
  makes the scale reference buy nothing.
- **Refusing every photograph below the canonical scale** rather than choosing
  the canonical at p5 — rejected. It is the same trade seen from the other side
  and it discards more of a small archive for a marginally finer patch.
- **Computing the quality criteria per patch** — rejected. They are properties
  of the photograph, not of a crop of it, and `minRoiSidePx` re-scoped to the
  patch would refuse every image. The criteria run on the disc; only the new
  dispersion criterion is computed across patches, and it is computed after
  inference.

## Scope

- Includes: a scale reader per side and the normalisation to a canonical
  millimetres-per-pixel; greyscale conversion; locating the soil region; the
  overlapping patch grid and its inset; batching the patches through the
  interpreter; the mean aggregation and the normalised dispersion metric; the
  `disc_diameter_px` manifest column; widening `_ARCHITECTURE_IMAGE_SIZE`; the
  shared geometry fixture table.
- Does NOT include: reading `spec.json` or separating the failure causes, which
  is SPEC 0035 and lands first; the verdict bands and the result surface, which
  the UI/UX terminal owns; converting the archive's HEIC files and building the
  dataset version, which is
  [SPEC 0040](0040-ingest-the-delivered-archive-as-dataset-version-v1.md); the
  out-of-distribution score (#194); any change to `ml/src/export.py`, which work
  item B3 owns; calibrating the dispersion threshold, which ships advisory
  because no validation set exists to calibrate it against.

The paragraphs below are the same two lists with their reasoning, kept because
each boundary above was drawn for a stated reason rather than by convenience.

**In scope, Python:** a scale reader over the dish rim; a normalisation to the
canonical scale; greyscale conversion via the shared luma; a patch grid over the
disc; the change from a one-tensor-per-path mapping to a flat-map in
`ml/src/dataset.py`; widening `_ARCHITECTURE_IMAGE_SIZE` in `ml/src/config.py`
to MobileNetV2's published set; a `disc_diameter_px` column in
`ml/src/manifest.py`.

**In scope, Dart:** a scale reader over the A4 sheet and the homography
rectification; **locating the soil region on the sheet**; the same
normalisation, greyscale and patch grid; batching the patches through the
interpreter; the mean aggregation; the dispersion metric.

**Locating the soil, and why the two sides differ here.** On the dataset side
the region is the dish, and the same circle fit that recovers the scale gives
it. On the application side there is no dish: the user arranges soil as a disc
of no fixed diameter on a white sheet, so the region has to be found from the
image. It is dark soil on white paper after rectification — the largest
connected region below a luminance threshold, with its bounding disc taken as
the region. That is arithmetic over pixels with no learned model, the same
category as the circle fit, and it is stated here because an earlier draft of
this specification wrote "a patch grid over the disc" without saying what
defines the disc when no dish is present.

The consequence for framing: **the patch grid covers the found region, not a
fixed fraction of the frame**, so a user who spreads a smaller disc gets fewer
patches rather than patches of background.

**The grid is inset from the region boundary by one patch half-width.** Without
the inset, edge patches straddle the boundary and carry glass rim, bench or
paper into a tensor that is supposed to be soil — which would reintroduce, at
the edges only, exactly the background difference the patch decision otherwise
removes. This was missing from the first draft of this specification and is the
correction that makes the next paragraph true.

**Patches make the dish-versus-paper background difference nearly disappear, and
that is worth stating because the earlier records assume otherwise.** A patch cut
from inside the soil region is soil and nothing else: no rim, no bench, no sheet.
The container affects where the region is and what the scale is, not what the
tensor contains. So the background gap that #192 exists to close is, after the
inset, confined to whatever the region-finder gets wrong at the boundary.

**The grid strides by half a patch**, so patches overlap by 50 %. The reason is
arithmetic: squares do not tile a circle to its boundary, so a non-overlapping
grid on a 90 mm disc holds a 3×3 arrangement — nine patches, not the fifteen an
area estimate suggests — and the count jumps between 1, 4 and 9 as the disc
grows. Overlapping gives a count that varies smoothly and enough points for the
dispersion measure at the small end, and it costs nothing that ADR 0018 has not
already conceded, since these patches were never independent.

| Soil region | Non-overlapping | At half-patch stride |
|---|---|---|
| 70 mm | 4 | **9** |
| 80 mm | 4 | 21 |
| 90 mm | 9 | **25** |

**Minimum nine patches**, which at half-patch stride means a soil region of
roughly 70 mm across. Below that the region is refused, in the same shape as a
missing sheet. The floor is on the dispersion measure rather than on the
classification: a mean over four patches is usable, an entropy over four is too
coarse to raise a warning with. The dataset's 90 mm dishes yield twenty-five, so
the application is permitted less soil than training saw and the counts differ —
which is why the dispersion is normalised.

**The dispersion is normalised by the patch count.** With a variable count
between nine and twenty-five, raw Shannon entropy is not comparable across
photographs — the same disagreement over nine patches and over twenty-five
produces different numbers. The reported value is the entropy divided by its maximum for
that count, so one threshold governs every photograph.

**In scope, shared:** the committed fixture table both languages assert their
geometry against, in the shape `test/fixtures/image_quality/` already uses.

**Out of scope.** Reading `spec.json` and the twelve failure causes — SPEC 0035,
which lands first and which this spec's values are added to. The verdict bands
and the result surface — the UI/UX terminal, whose roadmap items 1 and 2 own
them. Converting the 129 HEIC archive files — implementation work that precedes
training and touches no code under `lib/` or `ml/src/`. The out-of-distribution
score (#194). Any change to `ml/src/export.py`, which work item B3 owns.

**Explicitly not done here, and not an oversight:** the dispersion threshold
ships uncalibrated and advisory, like the seven criteria in SPEC 0030. No
validation set exists to calibrate it against, and blocking on an uncalibrated
criterion refuses legitimate work.

## Acceptance Criteria

**Scale**

- A dish-rim reader returns millimetres per pixel for an archive photograph, and
  a distinguishable failure when no circle is found.
- An A4 reader returns millimetres per pixel and a homography for a photograph
  containing the sheet, and a distinguishable failure otherwise.
- A photograph whose reference is not found produces the ADR 0015 failure cause
  and **never a default scale**. A test asserts that no code path substitutes
  one.
- The measured scale of every archive photograph is recorded in the manifest as
  `disc_diameter_px`, the validator refuses a missing or non-positive value, and
  it reports the spread per dataset version.
- A photograph whose rim cannot be fitted is **quarantined and reported by name**,
  in the same shape as an admission refusal — never dropped silently. A test
  asserts the report, because silently losing photographs is how a dataset shrinks
  without anyone noticing which ones went.
- The canonical scale is recomputed after #196 converts the HEIC files, and the
  recomputation is recorded even when the value does not move. **Done**, by
  [SPEC 0052](0052-read-the-dish-rim-and-recompute-the-canonical-scale.md): the
  record is `ml/measurements/dish-scale-v1.json` and the value is confirmed.

**Normalisation**

- Both languages resample to the canonical millimetres per pixel declared in
  `spec.json`, and **refuse to upsample**. A test asserts the refusal.
- A committed table of image dimensions, canonical scales and resulting patch
  geometry is asserted by both languages, so the two cannot diverge silently.

**Greyscale**

- Both languages produce greyscale through the existing BT.601 luma, and a test
  asserts the model path and the quality-analyzer path call the same definition.
- The input tensor carries three identical channels.

**Patches**

- The soil region is located by the circle fit on the dataset side and by the
  dark-region fit on the application side, and a region holding **fewer than nine
  patches** is refused rather than padded with background. A test asserts the
  refusal at the boundary.
- The grid is inset from the region boundary by one patch half-width, and a test
  asserts that no patch contains a pixel outside the located region.
- The patch side in millimetres is `input_size × canonical_mm_per_px`, the grid
  strides by half that, and it covers the located region. A test asserts the
  counts in the table above against the geometry rather than against constants. At 160 px and 0.130 mm/px that is a 20.8 mm patch and
  twenty-five patches at half-patch stride; the test asserts the arithmetic
  against the geometry, not against the constants.
- `ml/src/config.py` accepts MobileNetV2's published input sizes — 96, 128, 160,
  192, 224 — and rejects any other, with the message naming why an unpublished
  size is refused.
- `ml/src/dataset.py` yields one tensor per patch and the split stays grouped on
  `sample_id`. A test asserts that patches of one photograph never span two
  splits.

**Aggregation and dispersion**

- The reported distribution is the mean over patch distributions, and it is not
  renormalised.
- The dispersion is Shannon entropy over the class distribution of the patch
  predictions, **divided by the maximum entropy for that patch count**, so one
  threshold governs a variable count. It is reported as an image-quality
  criterion and is **never** folded into the confidence. A test asserts that a high-dispersion result and a
  low-confidence result are distinguishable at the boundary of the service.
- The dispersion criterion is advisory and cannot block.

**Evaluation**

- Per-class figures are computed over **samples**, never over patches or
  photographs. A test asserts the unit against a fixture where the three counts
  differ.

## Reproducibility

The patch grid is deterministic given the image, the measured scale and the
canonical scale — there is no sampling and no seed. Augmentation over patches
keeps the seeding already established by SPEC 0032. Two runs of one configuration
produce identical metrics, which is the property E0 needs and which this spec
must not break.

The committed geometry table is regenerated by a script under `ml/scripts/`, in
the shape `generate_image_quality_golden.py` already uses, so a change to the
geometry is a visible diff rather than a silent drift.

## Risks and Assumptions

- ~~**Assumption: the archive dishes are 90 mm.**~~ **Confirmed by the project
  owner, 2026-08-25.** Every millimetre figure in this spec and in ADR 0016 is
  therefore a measurement rather than a projection: 0.130 mm/px canonical,
  20.8 mm patches, ~15 patches per disc.
- **Risk: the A4 sheet may be hard to find in the field.** A pale sheet on a pale
  surface has no edge to fit. The refusal path is the mitigation and it is
  honest; if the refusal rate proves high, the fallback is the printed fiducial
  marker ADR 0017 records as rejected on a product constraint rather than on
  merit.
- **Risk: up to twenty-five forward passes per photograph on a CPU-only
  device**, roughly 3,850 MFLOPs. The per-pass cost has never been measured — the
  15 s in `inference_service.dart` is a timeout, not an expectation — so the
  end-to-end figure is unknown. It is the first thing the release measurement
  should report, and the lever it would move is the **stride**: widening it toward
  a non-overlapping grid cuts the count roughly threefold, at the price of a
  coarser dispersion measure.
- **Risk, recorded not closed: at 0.13 mm/px, silt and clay particles are not
  resolvable.** Whatever separates the finer classes must come from aggregate and
  surface appearance. This spec builds the pipeline that lets E0 answer whether
  such a signal exists; it does not assume one does.
- **Risk: the dataset side does not correct tilt and the application side does.**
  The archive photographs are near top-down so the residual is expected to be
  small, and it is unmeasured.
