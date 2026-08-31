# SPEC: feat(image-quality): define the soil image acceptance criteria with matching Python and Dart implementations


> **Revised 2026-08-25.** Three of the criteria below change meaning under
> [ADR 0018](../adr/0018-model-sees-fixed-size-greyscale-patches-and-their-spread-is-a-quality-signal.md),
> and the revision is recorded here rather than left to a reader to infer.
>
> - **`minRoiSidePx` is re-scoped to the disc, not the analysed region.** The
>   region of interest is now a grid of ~160 px patches, and 160 is far below the
>   512 px floor, so applied literally this criterion would refuse every image.
>   Re-scoped, the value is coincidentally right: 512 px across a 90 mm disc is
>   0.176 mm/px, which is the coarsest photograph in the archive.
> - **Colour cast stops being load-bearing.** This specification argues the
>   criterion matters because soil colour is signal. The model no longer sees
>   colour, so it is a capture-quality signal only and its threshold governs
>   nothing downstream.
> - **An eighth criterion joins the seven: patch dispersion.** Shannon entropy
>   over the class distribution of the patch predictions, computed *after*
>   inference rather than before it, reported as *the regions of this sample
>   disagree — spread it more evenly and retake*. It is advisory and cannot
>   block, like the three uncalibrated criteria already here.
>
> The dispersion is **normalised by the patch count** — entropy divided by its
> maximum for that count — because the count varies with the size of the soil
> region, from nine at the refusal floor to twenty-five for a 90 mm disc, and a
> raw entropy is not comparable across photographs.
>
> The seven metric definitions, the three verdicts, the `unvalidated` rule and
> the golden-file conformance test are unchanged.

## Problem

`lib/core/features/onboarding/onboarding_screen.dart:24-49` declares a capture
protocol — a coin for scale, soil filling at least 70% of the frame, diffuse
natural light with no flash, top-down at roughly 20 cm — that no code anywhere
checks. The dataset is collected under that protocol and the field usage is
free, which is the subpopulation mismatch described in
`docs/architecture/soil-classification.md` §3: a curated sample models its own
subpopulation well and fails on the population it is deployed against.

ADR 0009 decides to narrow that gap by enforcing the protocol rather than
compensating for it, and states the mechanism: **one set of image acceptance
criteria, applied both at collection time (defining what enters the dataset) and
at capture time (defining what production is allowed to produce)**. Two
divergent sets would widen it. Today neither set exists.

**The scope of what this closes, stated so the specification does not overclaim.**
These criteria are shared *admission* criteria over photographic quality. They
make the two sides agree on framing, focus, exposure, and effective resolution.
They do not establish field accuracy and they do not make the collection and
deployment populations one population: collection is bench-prepared, air-dried
and sieved, deployment is in situ, and no measurement over pixels can undo that.
ADR 0009's Consequences carry the full narrowing.

## Design Decisions

Deliver the criteria as a pure, dependency-light library in both languages, with
a committed golden file proving the two implementations agree. No UI, no capture
flow change, no dataset needed. This is the smallest increment that makes
ADR 0009's central claim testable.

### The region of interest

The ROI is the **largest centred square** of the source image, taken after EXIF
orientation is baked. Every metric below is computed over the ROI only.

Two consequences worth stating, because both are corrections rather than new
behaviour. First, the current pipeline resizes a rectangular photo straight to
224×224 on both sides — `tf.image.resize(image, [size, size])`
(`ml/src/preprocess.py:48`) and `img.copyResize(width: 224, height: 224)`
(`lib/core/services/inference_service.dart:207-212`) — which squashes the aspect
ratio. A centred square crop removes that distortion. Second, the crop is the
one geometric definition both the dataset and the app must share; defining it
here is what lets a later spec apply it in both places.

### Alignment with the UX capture design

`docs/design/ux-2026/06-capture-experience.md` §2.2 independently specifies a
capture quality gate with the same three core signals (Laplacian variance,
mean luminance plus clipped fraction, shorter side in pixels), the same stance
that all thresholds ship as hypotheses to be calibrated against the ML
terminal's validation set, and the same asymmetry that a false block costs more
than a flagged bad analysis. This spec adopts that design's verdict model and
failure semantics rather than inventing a parallel one. Three specific
adoptions are marked below.

### The metrics

All seven are model-free arithmetic over the ROI. Luma is ITU-R BT.601,
`Y = 0.299·R + 0.587·G + 0.114·B`, computed on 8-bit channel values as
`double`, in both languages, with no rounding before the metric.

**Adoption 1 — the blur metric is computed on a downscaled copy**, following
`06-capture-experience.md` §2.2, at a fixed 512 px on the ROI side. The UX
document's stated reason is cost; there is a second and stronger one. Laplacian
variance is resolution-dependent, so the same scene photographed at 12 MP and at
5 MP yields different scores, and a threshold calibrated on one device would be
wrong on another. Downscaling to a fixed size makes the score comparable across
devices, which is what makes it thresholdable at all. A source ROI already below
512 px is used as-is and the report records that no downscale occurred.

**Correction, found while implementing this spec.** This section first said
"bilinear interpolation" and delegated the resize to each language's image
library. Both halves of that were wrong.

- **It is not reproducible across languages.** `image`'s `Interpolation.linear`
  point-samples four neighbours; Pillow's `BILINEAR` scales its filter support
  with the downscale factor, so it averages over a wider window. They are
  different algorithms, and no tolerance near `1e-9` would ever hold between
  them. The conformance golden would have failed on a decision made in prose.
- **It would break the resolution-independence criterion below.** Point-sampled
  bilinear ignores most source pixels when shrinking by more than 2×, so a
  high-frequency pattern aliases differently at 2048 px and at 1024 px, and the
  two `blurScore` values would not land within 5% of each other. An area filter
  is not a refinement here; it is what makes the metric mean anything.

The downscale is therefore defined arithmetically and implemented by hand in
both languages, using no library resize:

> Let `S` be the ROI side in pixels, `T = 512`, and `f = S / T`. Output pixel
> `(i, j)` covers the source region `x ∈ [j·f, (j+1)·f)`, `y ∈ [i·f, (i+1)·f)`.
> Its value is the sum, over every source pixel overlapping that region, of the
> pixel value times its overlapping area, divided by `f²`. Source pixels are
> visited row-major, ascending index. When `S <= T` no downscale is applied.

The downscale runs on the **luma plane**, not on the three channels. Luma and an
area average are both linear, so the two orders are equivalent, and fixing one of
them removes a needless source of divergence.

| Metric | Plain description | Definition |
|---|---|---|
| `blurScore` | The photo is out of focus | Variance of the 3×3 Laplacian (kernel `[[0,1,0],[1,-4,1],[0,1,0]]`) of the luma plane of the 512 px downscaled ROI, evaluated on interior pixels only — no padding, no border extension |
| `meanLuminance` | Too dark or too bright overall | Arithmetic mean of luma over the ROI, in `[0, 255]` |
| `clippedFraction` | Detail burnt out or crushed to black | Fraction of ROI pixels with luma `<= 2.0` or `>= 253.0` |
| `contrastScore` | Flat and washed out | Population standard deviation of luma over the ROI |
| `colorCastScore` | The whole photo is tinted | Maximum pairwise absolute difference between the three channel means, divided by 255 |
| `specularFraction` | Flash or a hotspot burning the surface | Fraction of ROI pixels with luma `>= 250.0` and HSV saturation `<= 0.10` |
| `roiSidePx` | Too few pixels to work with | Side length of the ROI square, in pixels |

**Adoption 2 — three verdicts, not two.** Following `06-capture-experience.md`
§2.2: `ok` proceeds silently; `advisory` proceeds and attaches the flags to the
result and to the saved record; `blocking` names the defect and offers a retake
with "registrar assim mesmo" as the secondary action. A two-state
accepted/rejected model cannot express the marginal image that should be
analysed *and* flagged, which is the common case in a field.

**Four of the seven criteria may produce `blocking` in phase one** — blur,
exposure, clipping, and effective resolution — matching the three signals the UX
design blocks on, where its "exposure" covers this spec's separate exposure and
clipping criteria. The remaining three — contrast, colour cast, and specular —
are `advisory` only until they are calibrated against real images. Blocking on
an uncalibrated criterion is how a gate starts refusing legitimate work.

**Corrected while implementing.** This paragraph first read "only three
criteria... and the other four (contrast, colour cast, specular, and the
ROI-side report)", which placed `roiSidePx` on both sides at once: blocking as
"effective resolution" and advisory as "the ROI-side report". The acceptance
criterion `roi_side_is_reported` below requires it to reject, and the seven
criteria map one-to-one onto the seven metrics, so the split is four blocking
and three advisory. The miscount came from collapsing exposure and clipping into
one criterion in the prose while the metric table lists them separately.

The report always lists **every** failing criterion with its measured value and
its margin, rather than short-circuiting on the first, because the UI must be
able to tell the user everything that needs fixing in one retake.

**Adoption 3 — a failure of the analyzer is `unvalidated`, not `blocking`.**
Following `06-capture-experience.md` §2.3: if analysis throws, the report
carries the `unvalidated` verdict and the caller proceeds with an advisory
noting the check did not run. A crashed checker must never block a valid sample.
This is a verdict, not an exception, so the caller cannot forget to handle it.

### Thresholds are provisional and configurable

The default thresholds shipped here are engineering starting points, not
calibrated values, and are marked as such in the source. Calibrating them
requires real images, which do not exist yet
(`docs/architecture/soil-classification.md` §4). `ImageQualityCriteria` is a
value object with named defaults so a later phase can recalibrate without
touching the analyzer, and so the audit and the gate can be pinned to the same
criteria version.

Every metric is reported numerically alongside the verdict. A rejected capture
therefore records *how far* it missed, which is the data recalibration needs.

### Cross-language conformance by golden file

A committed golden file, not a cross-language test harness. `ml/` and `lib/`
have separate CI jobs and CI does not run `ml/tests/` today (#28); requiring one
job to invoke the other language would couple them.

- Fixtures are **PNG**, committed under `test/fixtures/image_quality/`. PNG
  because it is lossless: a JPEG decoded by `image` in Dart and by Pillow in
  Python can differ by a quantization step, which would make a conformance
  failure indistinguishable from a decoder difference.
- `ml/scripts/generate_image_quality_golden.py` writes
  `test/fixtures/image_quality/golden.json`: for each fixture, every metric and
  the verdict under the default criteria.
- The Python test asserts its implementation reproduces the committed golden.
  The Dart test asserts the same. The golden is reviewed as part of the diff, so
  a silent drift on either side fails the other side's suite.
- Metric agreement tolerance is `1e-9` relative. Fixtures are chosen so no
  metric lands within `1e-6` of a threshold, so the verdict comparison is not
  sensitive to floating-point noise.
- **This is metric-level conformance, not decoder conformance, and the
  difference is worth naming.** Both sides are compared on the numbers they
  derive, so the golden proves the two implementations compute the same metrics
  and reach the same verdict on the same files. It does not prove `image` in
  Dart and Pillow in Python produce identical pixel buffers. Every metric here
  reduces an image to a scalar — a variance, a mean, a fraction — and reductions
  absorb small per-pixel differences, so a decoder divergence could in principle
  hide under a metric that agrees.

  PNG fixtures make this unlikely rather than impossible: PNG decoding is
  lossless and specified, so the two decoders should agree exactly, which is
  precisely why the format was chosen over JPEG above.

  The scope is stated rather than widened. Adding a pixel-level comparison for
  one fixture would make the assumption directly checkable, and it is the right
  escalation **if a metric ever disagrees in a way the arithmetic cannot
  explain** — that is the symptom a decoder divergence would produce. It is not
  adopted as a criterion now, because doing so would put a requirement in this
  specification that the implementation does not meet, which is the same defect
  in the opposite direction. What this specification claims is what its golden
  proves: identical metrics and identical verdicts over the committed fixtures.

### File layout

Dart, under `lib/core/services/image_quality/`:

- `image_quality_criteria.dart` — the thresholds, with provisional defaults
- `image_quality_report.dart` — metrics, verdict, and the list of failed criteria
- `image_quality_analyzer.dart` — `analyze(img.Image source, {ImageQualityCriteria criteria})`

Python, `ml/src/image_quality.py` — the same seven metrics, the same criteria
defaults, the same ROI rule, returning a dataclass.

No new dependency in either language: Dart uses `image ^4.3.0`
(`pubspec.yaml:51`), Python uses NumPy and Pillow, both already in
`ml/requirements.txt`.

## Alternatives Considered

- **A single implementation invoked from both sides (Dart FFI, or Python
  shelling out to Dart):** rejected — it couples the ML pipeline's runtime to
  the Flutter toolchain and would make the dataset audit unrunnable on a machine
  without Flutter installed.
- **Cross-language conformance by running Python from the Dart test:** rejected
  — it makes the Flutter test suite depend on a Python environment, which CI
  does not provide for the `test` job and which would fail on any contributor
  machine without `ml/.venv`.
- **JPEG fixtures:** rejected — decoder differences between `image` and Pillow
  would surface as conformance failures with no defect behind them.
- **Calibrated thresholds now:** rejected — there are no real images to
  calibrate against. Shipping invented numbers as if they were measured is worse
  than shipping them labelled as provisional. This matches
  `06-capture-experience.md` §2.2, which ships its thresholds as hypotheses for
  the same reason.
- **A two-state accepted/rejected verdict:** rejected — it cannot express the
  marginal image that should be analysed and flagged, and it would diverge from
  the UX capture design for no gain.
- **Blocking on all seven criteria from day one:** rejected — four of them have
  no calibration path yet, and a gate that blocks on an uncalibrated criterion
  refuses legitimate field work while every other metric reports an improvement.
- **Ship the gate wired into the capture screen in this spec:** rejected —
  `capture_screen.dart` is a surface the UI/UX terminal also works on, and the
  library is independently valuable and independently testable. The wiring is a
  follow-up spec, coordinated across terminals.
- **Include the target-fill (≥70%) criterion:** rejected — measuring it requires
  foreground separation, which ADR 0009 defers. The fixed ROI defines the region
  without measuring what fills it.

## Scope

- Includes:
  - `lib/core/services/image_quality/` — criteria, report, analyzer.
  - `ml/src/image_quality.py` — the reference implementation.
  - `ml/scripts/generate_image_quality_golden.py` — golden generator.
  - `test/fixtures/image_quality/` — PNG fixtures and `golden.json`.
  - `test/services/image_quality_analyzer_test.dart` — unit tests plus the
    golden conformance assertion.
  - `ml/tests/test_image_quality.py` — the same, on the Python side.
- Does NOT include:
  - Any change to `capture_screen.dart`, the capture UI, a viewfinder overlay,
    a retake flow, or the override path.
  - Any change to `inference_service.dart` or to `ml/src/preprocess.py`, so the
    existing squashing resize stays as it is until a follow-up applies the ROI
    in both places together.
  - The dataset audit CLI, the manifest format, and any dataset work.
  - Threshold calibration against real images.
  - Telemetry, block-rate reporting, and persistence of quality flags on
    `SoilRecord`.
  - The target-fill criterion and any segmentation or detection.

## Acceptance Criteria

- roi_is_largest_centred_square: for a 400×300 source the ROI is the 300×300
  region at x-offset 50, y-offset 0; for a 300×400 source it is the 300×300
  region at x-offset 0, y-offset 50; for a square source the ROI is the whole
  image.
- roi_side_is_reported: `roiSidePx` equals `min(width, height)` and a source
  whose shorter side is below `minRoiSidePx` is rejected with that criterion
  listed.
- blur_is_resolution_independent: the same synthetic pattern rendered at 2048 px
  and at 1024 px on the ROI side yields `blurScore` values within 5% of each
  other, proving the fixed 512 px downscale is applied before the Laplacian.
- blur_separates_sharp_from_blurred: a synthetic high-frequency checkerboard
  scores a higher `blurScore` than the same image after a Gaussian blur, and
  the blurred one is blocking under the default threshold while the sharp one
  is not.
- exposure_bounds_are_two_sided: a near-black fixture and a near-white fixture
  are both blocking, each listing the exposure criterion, while a mid-grey
  fixture passes that criterion.
- clipping_is_detected: a fixture with 20% of pixels at value 255 reports
  `clippedFraction` of 0.20 and is blocking.
- low_contrast_is_advisory: a low-contrast but sharp fixture — a checkerboard
  about mid-grey whose amplitude is small enough to fail `minContrastScore` and
  whose edges are still sharp enough to clear `minBlurScore` — reports a
  `contrastScore` below the threshold and yields the advisory verdict, not
  blocking. The amplitude is chosen by the fixture generator against the
  measured metrics rather than pinned here, because the blur response after the
  512 px downscale depends on the cell size as well as the amplitude.
  **Corrected while implementing.** This criterion first named a uniform fill,
  which cannot satisfy it: zero contrast means a zero Laplacian everywhere, so a
  uniform fill necessarily fails blur as well and is blocking. The criterion was
  unsatisfiable as written. A uniform fill is still committed as a fixture,
  because it is the flat-fill decode check the Risks section relies on, and it
  is expected to be blocking on blur.
- bright_clipping_and_specular_overlap_by_construction: `clippedFraction`
  counts luma `>= 253.0`, and `specularFraction` counts luma `>= 250.0` with
  saturation `<= 0.10`. Luma `>= 253` forces every channel high enough that
  saturation cannot exceed `0.0686`, so **a bright-clipped pixel is always also
  specular**. A fixture isolating clipping therefore clips at the dark bound
  (luma `<= 2.0`), which no specular pixel can satisfy. Recorded because it
  constrains `golden_covers_every_criterion` below, not because either
  definition is wrong.
- colour_cast_is_advisory: a fixture whose red channel mean exceeds the others
  by 60 reports `colorCastScore` of `60/255` and yields advisory.
- specular_is_advisory: a fixture with a bright low-saturation patch covering
  15% of the ROI reports `specularFraction` of 0.15 and yields advisory.
- blocking_outranks_advisory: a fixture failing blur and colour cast together
  yields the blocking verdict while still listing both criteria.
- all_failing_criteria_are_reported: a fixture failing exposure, contrast and
  blur simultaneously lists all three with their measured values and margins,
  rather than only the first.
- ok_report_lists_no_failures: a fixture inside every bound returns the `ok`
  verdict with an empty failure list.
- analyzer_failure_is_unvalidated: a source that makes the analyzer throw — an
  image with a zero-length side — returns the `unvalidated` verdict rather than
  propagating the exception or returning blocking.
- criteria_are_injectable: passing a custom `ImageQualityCriteria` changes the
  verdict for a fixture that sits between the custom and the default threshold,
  proving the analyzer reads the passed criteria and not a constant.
- dart_matches_golden: for every fixture, the Dart analyzer reproduces every
  metric in `golden.json` within `1e-9` relative tolerance and reproduces the
  verdict exactly.
- python_matches_golden: the same assertion on the Python side.
- golden_covers_every_criterion: each of the seven criteria is the sole failing
  criterion for at least one fixture, so the golden cannot pass while a
  criterion is silently unimplemented.
- orientation_is_baked_before_cropping: a fixture rotated by an EXIF
  orientation tag yields the same metrics as the already-rotated pixels with no
  tag. Asserted independently in each language, since PNG fixtures carry no EXIF
  and this path is therefore outside the cross-language golden.
- analyze_clean_tests_green: `flutter analyze` reports no issues; `flutter test`
  passes; `python -m pytest ml/tests/ -v` passes.

## Reproducibility

- Toolchain: Flutter 3.44.1 / Dart 3.12.1 (pinned per `.github/workflows/ci.yml`).
- Python: the pins in `ml/requirements.txt` (NumPy `>=1.24,<2.0`, Pillow
  `>=10.0,<11.0`).
- Fixtures are generated deterministically, with no randomness. Where a fixture
  needs noise, it is produced by a fixed formula rather than a random draw, so
  no seed is required and the bytes are reproducible on any platform.
- Regenerate the golden:
  `cd ml && python scripts/generate_image_quality_golden.py`
- Verify: `flutter analyze && flutter test`, then
  `cd ml && python -m pytest tests/ -v`.
- A golden regenerated with no source change must produce a byte-identical
  `golden.json`; a non-empty diff means an implementation changed and the diff
  is the evidence.

## Risks and Assumptions

- Assumption: the default thresholds are provisional and will be recalibrated
  against real images in a later phase. They are labelled as such in the source,
  and every metric is reported numerically so a rejected capture records how far
  it missed. What would invalidate this spec: discovering that a criterion
  cannot be calibrated to separate usable from unusable soil photographs at all,
  in which case that criterion is dropped rather than tuned.
- Assumption: `1e-9` relative agreement between Dart `double` and NumPy
  `float64` is achievable for these metrics, since both are IEEE-754 binary64
  and the operations are sums, means, and a fixed convolution. If accumulation
  order proves to matter at that tolerance, the fix is to fix the order in the
  spec — sum row-major, ascending index — rather than to loosen the tolerance,
  because a loosened tolerance hides exactly the divergence this file exists to
  prevent.
- Assumption: PNG decoding is byte-identical between `image` 4.8.0 and Pillow.
  Verified by the golden itself; a mismatch on a uniform-fill fixture would
  indicate a decode difference rather than a metric difference, which is why one
  fixture is a flat fill with a known exact mean.
- Risk: seven criteria applied together reject more than the sum of their parts,
  producing a gate that blocks usable captures. Mitigated at this layer by
  reporting all failures with their margins, and at the next layer by ADR 0009's
  mandatory override path. Block rate per criterion becomes a monitored metric
  once telemetry exists.
- Risk: this library is written before any consumer exists, so its interface is
  designed against two speculative call sites. Mitigated by keeping it a pure
  function of pixels and criteria, with no I/O, no isolate, and no state — the
  shape hardest to get wrong and cheapest to change.
