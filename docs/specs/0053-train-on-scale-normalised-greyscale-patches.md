# SPEC: feat(ml): train on scale-normalised greyscale patches instead of a squashed frame

## Problem

Training still resizes the whole photograph to 224 × 224 and normalises it, so
the same soil enters the model at up to 4.83 different apparent sizes with
nothing recording which is which, and the patch pipeline
[ADR 0018](../adr/0018-model-sees-fixed-size-greyscale-patches-and-their-spread-is-a-quality-signal.md)
requires exists in neither language.

## Design Decision

This is the **Python half** of
[SPEC 0037](0037-scale-normalised-greyscale-patch-pipeline.md), which is
gate-approved and specifies both sides. It lands under its own number because
the Dart half depends on [SPEC 0035](0035-spec-json-runtime-contract.md), which
is unimplemented, and because a slice that ships is worth more to the C0 gate
than a spec that waits. SPEC 0037 remains the design; nothing here changes it.

**Every photograph is resampled to one canonical millimetres per pixel before
anything else looks at it**, using the value
[SPEC 0052](0052-read-the-dish-rim-and-recompute-the-canonical-scale.md)
measured, and **a photograph too coarse to reach the canonical without
upsampling is refused by name**. After that step a 90 mm dish is the same number
of pixels across in every photograph in the archive, which is the property that
makes a patch measured in millimetres mean anything.

**The model sees a grid of greyscale patches cut from inside the dish**, at the
input size the architecture publishes, striding by half a patch and inset from
the region boundary by half a patch so no patch can contain glass or bench. The
greyscale comes from the BT.601 luma `ml/src/image_quality.py` already defines
and a committed golden already pins, replicated to three channels so MobileNetV2's
ImageNet weights load unchanged.

**The inset is a patch half-diagonal, not a half-width, and that is a correction
to SPEC 0037's prose rather than a choice.** SPEC 0037 says the grid is "inset
from the region boundary by one patch half-width", and it also requires that
"no patch contains a pixel outside the located region", and ADR 0018 tabulates
9, 21 and 25 patches for discs of 70, 80 and 90 mm. The three cannot all hold: a
square inset by its half-width still puts its corners outside a circle. Only the
half-diagonal satisfies the criterion, and only the half-diagonal reproduces the
table — computed at the canonical 0.1292 mm/px and an input of 160 px:

| Disc | After resampling | Half-diagonal inset | Half-width inset | ADR 0018 |
|---|---|---|---|---|
| 70 mm | 542 px | **9** | 21 | 9 |
| 80 mm | 619 px | **21** | 25 | 21 |
| 90 mm | 697 px | **25** | 37 | 25 |

So the criterion and the table agree with each other and the prose is the odd
one out. The prose is what gets corrected.

**The manifest carries four measured columns, not the one SPEC 0037 names,
and that is a second correction found by implementing it.** SPEC 0037 records
the measurement as a `disc_diameter_px` column. A diameter locates nothing: the
grid is laid out from the region's **centre**, and neither SPEC 0037 nor
ADR 0018 says where that centre comes from on the dataset side. The scale reader
already fits it — `ScaleReading` carries `centre_x_px` and `centre_y_px` — so
the gap is in the record, not in the code. The manifest therefore carries
`mm_per_px`, `disc_diameter_px`, `disc_centre_x_px` and `disc_centre_y_px`, and
the same four are added to the committed measurement record.

**The measurement record, not the manifest, is where a measurement survives.**
The manifest is a build product (ADR 0019) and is rebuilt whenever the version
is; the record under `ml/measurements/` is committed. Recording the scale only
in the manifest would mean paying the seven-minute reader run again after every
re-ingest, for a measurement that did not change. So `measure_scale.py` gains
`--from-record`, which fills the manifest's four columns from the committed
record without opening a photograph, and refuses a record whose manifest digest
is not the one on disk.

**One consequence found by implementing it, recorded rather than acted on.**
Under the corrected inset the count reaches nine at a disc of **58.5 mm**, not at
the "roughly 70 mm" ADR 0018 states. Both are consistent — 70 mm sits inside the
same step, so its tabulated 9 is right — but the floor that record gives is
conservative by 11 mm. Whether the application refuses at 70 mm for margin or at
58.5 mm because that is where the evidence runs out is **the application's
decision and is not taken here**, since the dataset side never meets a disc other
than 90 mm. The step table is pinned by a test so the choice is made against a
measurement:

| Disc | 50 mm | 58.5 mm | 70 mm | 71 mm | 80 mm | 88 mm | 90 mm |
|---|---|---|---|---|---|---|---|
| Patches | 5 | **9** | 9 | 13 | 21 | 25 | 25 |

**A photograph is still the unit of a prediction.** The model scores patches;
`train.py` averages a photograph's patch distributions back into one photograph
distribution before writing `predictions.json`, so `evaluate.py`, the fold
manifest, the contrasts and every number
[SPEC 0042](0042-repeated-group-k-fold-evaluation-protocol.md) defines keep the
meaning they have today. Patches are how the model reads a photograph, not a new
unit of evidence — they are not independent, and counting them as samples would
inflate every interval by a factor of five.

**`config.yaml` carries the canonical unrounded, and that is a third thing
implementing it settled.** The file is written to be read and every other value
in it is a round number, so the canonical was first written as 0.1292. That is
finer than the percentile it stands for, and the photograph whose reading *is*
the percentile then reads as coarser than the scale derived from it: twelve
photographs leave training where the measurement says eleven, and the twelfth is
the one that defined the value. Rounding up to 0.1293 also refuses exactly
eleven, but it puts a second number into records that all quote 0.1292. So the
config carries 0.12920342774728033, the acceptance criterion below is bit
equality rather than a tolerance, and a test measures the cost of the rounding
that was rejected rather than restating the argument.

**The canonical value lives in `config.yaml` and is asserted against the
measurement record**, in the shape `test/standards/class_list_test.dart` already
uses for the class list. Training reads the config; the record is the evidence;
a test refuses the two to drift. Publishing it into `spec.json` is B3's, and is
not done here.

## Alternatives Considered

- **Resample to the median scale rather than the canonical.** Rejected in
  ADR 0017 and re-rejected here on the measurement: the median is 0.0526 mm/px
  and 105 of 221 photographs are coarser than it, so half the archive would be
  upsampled — a model trained on interpolated grain learns the interpolator.
- **Skip the resample and cut patches in pixels.** Rejected in ADR 0018. It is
  the cheapest option and it makes the scale reference buy nothing: a patch of
  160 px covers 5.5 mm of soil in the finest photograph and 21 mm in the
  coarsest, so the same soil presents as two different soils.
- **Keep the whole-frame resize and add the scale as an input feature.**
  Rejected. It asks the model to learn the correction that arithmetic already
  performs exactly, on 105 sample groups, and it leaves the train/serve skew in
  place because the application would have to supply the same feature.
- **Treat each patch as an independent sample in the metrics.** Rejected, and it
  is the tempting one because it multiplies the apparent sample size by
  twenty-five. Patches of one photograph share lighting, preparation and soil;
  they are repeated measurements of one spatial statistic, and ADR 0018 says so.
  Counting them as samples would shrink every reported interval by a factor of
  five without a single new sample existing.
- **Aggregate patches inside the model, as a pooling layer.** Rejected for this
  slice. It is the cleaner shape and it changes what gets exported to TFLite,
  which is B3's surface and ADR 0012's release path; doing it here would couple
  two independent changes.
- **Let a photograph that cannot be resampled train anyway, at its own scale.**
  Rejected. It reintroduces exactly the mixture this spec removes, in the eleven
  photographs least like the rest.

## Scope

- Includes:
  - `ml/src/patches.py` (new) — resample to canonical, greyscale, grid geometry,
    patch extraction, and the named refusals for too-coarse and too-small.
  - `ml/src/dataset.py` — one tensor per patch, carrying the index of the
    photograph it came from; grouping stays on `sample_id`.
  - `ml/src/train.py` — average a photograph's patch distributions back into one
    photograph distribution before predictions are written.
  - `ml/src/config.py` — accept MobileNetV2's published input sizes, and the new
    `preprocessing.canonical_mm_per_px`, `preprocessing.patch_stride_fraction`
    and `preprocessing.min_patches` keys, validated on load.
  - `ml/config.yaml` — those three values.
  - `ml/src/manifest.py` — the four measured scale columns, optional in the
    schema and checked at the point of use, with a non-positive scale or
    diameter refused by name and the spread reported per dataset version.
  - `ml/scripts/measure_scale.py` — write those columns into the manifest, carry
    the dish centre in the committed record, and fill the manifest from that
    record with `--from-record` rather than re-reading the archive.
  - `ml/scripts/validate_dataset.py` — report the measured spread, an unmeasured
    version, and how many photographs are coarser than the canonical.
  - `test/fixtures/patch_geometry/geometry.json` (new, committed) plus the script
    under `ml/scripts/` that regenerates it — the dimensions, canonical scales
    and resulting patch counts both languages will assert against.
  - `ml/tests/test_patches.py` (new) and additions to the config, dataset and
    manifest suites.
- Does NOT include:
  - **The whole Dart half** — the A4 sheet reader, the homography, finding the
    soil region on paper, batching patches through the interpreter, the mean
    aggregation and the dispersion metric. It depends on SPEC 0035 and lands
    with it. Until then the application's inference path is unchanged and does
    not match training, which is a train/serve skew that this spec **opens** and
    SPEC 0035 closes. It is stated here rather than discovered later.
  - The dispersion criterion, on either side. It is computed after inference,
    which is the Dart half.
  - Publishing anything into `spec.json`. That is B3.
  - Any change to the evaluation protocol, the fold manifest schema, the
    contrasts, or `ml/src/evaluate.py`. The photograph stays the unit and those
    files do not move.
  - Re-ingesting the archive or creating a dataset version `v2`.
  - The anti-aliasing defect #180 beyond what the resample itself fixes.

## Acceptance Criteria

- resamples_a_photograph_to_the_canonical_scale: an image whose measured scale is
  finer than the canonical is returned at the canonical scale, with its dish
  diameter in pixels equal to `90 / canonical` within one pixel.
- refuses_to_upsample_a_coarse_photograph: an image whose measured scale is
  coarser than the canonical is refused by name and produces no patches. A test
  asserts that no code path resamples it upward.
- refuses_a_region_too_small_for_nine_patches: a region below the floor is
  refused rather than padded with background, and the refusal names the count it
  could produce.
- patches_are_greyscale_through_the_shared_luma: the patch pipeline and the
  quality analyzer call one luma definition, asserted by a test, and the tensor
  carries three identical channels.
- every_patch_lies_inside_the_located_region: no patch contains a pixel outside
  the dish region, at the boundary case where the grid is widest. A test asserts
  it against the geometry rather than against a constant. The inset is a patch
  half-diagonal; a half-width inset fails this criterion by the corners.
- the_patch_counts_reproduce_the_adr_0018_table: 9, 21 and 25 patches for discs
  of 70, 80 and 90 mm at the canonical scale and a 160 px input, computed from
  the geometry rather than asserted as constants.
- patch_geometry_is_derived_not_hardcoded: patch side in millimetres is
  `input_size × canonical`, the stride is half of it, and the counts in the
  committed table follow from that arithmetic. A test recomputes them.
- the_committed_geometry_table_matches_the_generator: re-running the generator
  script reproduces `geometry.json` byte for byte.
- the_config_canonical_matches_the_measurement_record: `config.yaml`'s
  `canonical_mm_per_px` equals the canonical in
  `ml/measurements/dish-scale-v1.json` exactly, with no tolerance, and a test
  refuses a drift.
- rounding_the_canonical_would_refuse_a_twelfth_photograph: a test measures what
  rounding the constant for readability would cost — eleven photographs leave
  training at the measured value and twelve at the rounded one — so the
  unrounded constant is justified by a number rather than by an argument.
- config_accepts_the_published_input_sizes: 96, 128, 160, 192 and 224 are
  accepted for `mobilenetv2` and any other size is refused with a message saying
  why an unpublished size is not allowed.
- the_dataset_yields_one_tensor_per_patch: a split of N photographs each yielding
  P patches produces N × P tensors, each labelled with its photograph's class.
- patches_of_one_photograph_never_span_two_folds: grouping is unchanged, on
  `sample_id`, and a test asserts no patch of a photograph appears on both sides
  of a fold.
- a_prediction_is_written_per_photograph_not_per_patch: `predictions.json` holds
  one row per photograph, its distribution the mean over that photograph's
  patches, so the file's shape is unchanged.
- the_manifest_carries_the_measured_disc_geometry: the four scale columns are
  written by `measure_scale.py`, a non-positive scale or diameter is refused by
  name, a version that reaches the patch grid unmeasured is reported by name
  with the command that fixes it, and the validator reports the spread per
  dataset version.
- the_record_carries_the_centre_of_every_dish: the committed measurement record
  holds `disc_centre_x_px` and `disc_centre_y_px` for every photograph that got
  a scale, so a rebuilt manifest can be refilled without reading an image.
- the_manifest_is_filled_from_the_record_without_reading_an_image:
  `--from-record` writes the four columns from the committed record, opens no
  photograph, and refuses a record whose manifest digest is not the one on
  disk.

## Reproducibility

```sh
cd ml
.venv/Scripts/python -m pytest tests/ -q
.venv/Scripts/python scripts/generate_patch_geometry.py
git diff --exit-code ../test/fixtures/patch_geometry/geometry.json
```

Python 3.12.13 and the pinned stack of `ml/requirements.txt`. The patch grid is
deterministic given the image, its measured scale and the canonical scale: there
is no sampling and no seed, and augmentation keeps the seeding SPEC 0032
established. Two runs of one configuration still produce identical metrics,
which is the property E0 needs and which this spec must not break.

At the canonical 0.1292 mm/px and an input of 160 px, a patch is **20.7 mm** and
a 90 mm dish is **697 px** across after resampling, which yields **25 patches**
at half-patch stride — the count ADR 0018 tabulates. Because every archive
photograph is resampled to the same scale and every archive dish is 90 mm, the
patch count is **constant across the archive**, so the class balance the loss
sees is the photograph balance it sees today and `compute_class_weights` needs no
change. A variable count is an application condition, not a training one.

## Risks and Assumptions

- **This spec opens a train/serve skew and does not close it.** After it,
  training sees canonical-scale greyscale patches and `InferenceService` still
  resizes the whole frame to 224 and keeps colour. That is worse than the
  present mismatch, not better, and it is deliberate: the Dart half needs
  SPEC 0035. **No model may be released between this spec and that one**, which
  is not a new constraint — ADR 0012's release path runs through B3, which is
  also unimplemented — but it is now load-bearing and is stated so nobody reads a
  green training run as a shippable model.
- **Eleven photographs leave training**, the ones coarser than the canonical.
  All eleven are in the transported population, which SPEC 0040 D6 already holds
  to training only, so the splittable pool stays at 77 groups and SPEC 0042's
  minimum detectable effect does not move. The fold manifest is git-ignored and
  is regenerated; the numbers in it do not change.
- **Assumption: the dish region is the circle the scale reader already fitted.**
  It is, on the dataset side, and that is why the region needs no second
  operator here. The application has no dish and must find the region itself,
  which is the Dart half's problem and is specified in SPEC 0037.
- **Risk: twenty-five forward passes per photograph is twenty-five times the
  training cost per epoch.** A fold measured 15.5 minutes at one tensor per
  photograph (SPEC 0051); this makes each epoch see 25 × as many tensors, and the
  arm's 6.5 hours is the figure at risk. The lever is the stride — widening it
  toward a non-overlapping grid cuts the count roughly threefold — and the cost
  is measured before the arms are dispatched rather than assumed.
- **Risk: a patch is 20.7 mm of soil and the label is the whole sample's.** If
  texture varies across the dish, some patches carry a label that does not
  describe them. That is label noise the mean aggregation partly absorbs and
  nothing measures, and it is the same risk ADR 0018 accepted when it chose
  patches.
- **What would invalidate this spec:** a change to the canonical scale, a
  decision to aggregate inside the model rather than after it, or a measurement
  showing the patch cost puts an arm beyond what CI will run.
