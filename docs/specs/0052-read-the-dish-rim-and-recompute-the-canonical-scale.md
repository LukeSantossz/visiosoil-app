# SPEC: feat(ml): read the dish rim to measure scale, and recompute the canonical millimetres per pixel over the whole archive

## Problem

The canonical millimetres per pixel that every training and every inference will
normalise to is a constant written into
[SPEC 0037](0037-scale-normalised-greyscale-patch-pipeline.md) from a
measurement taken over 92 of the archive's 221 photographs, by a reader that
exists in neither language and whose result was never committed, so nothing can
check it and nothing can reproduce it.

## Design Decision

A deterministic dish-rim reader lands in Python as `ml/src/scale.py`, is run over
every photograph of dataset version `v1`, and its per-photograph result is
committed as a measurement record beside the summary the canonical value is
derived from.

The reader finds the **outer glass rim** — the circle whose diameter is the
90 mm the project owner confirmed — in three deterministic stages. A circular
Hough vote over Sobel edge orientations at a fixed coarse resolution recovers the
**centre**; because the soil boundary, the inner dish wall and the outer rim are
concentric, all three structures vote for one centre, which is what makes the
centre the robust part of the measurement rather than the fragile part. With the
centre fixed, a radial profile of the luma derivative is taken along 720 rays and
the **outermost** radial position whose median edge strength reaches 35 % of the
profile's peak is the rim. Each ray is then refined independently within ±6 % of
that radius, and the radius is the median over rays.

**The reader reports its own dispersion and refuses rather than guessing.** The
median absolute deviation of the per-ray radii, divided by the radius, is
returned with every reading, together with the fraction of rays that found an
edge. A photograph whose dispersion exceeds the refusal threshold, whose ray
coverage falls below it, or in which no circle is found at all, is **quarantined
by name** and given no scale — which is
[ADR 0017](../adr/0017-scale-is-read-by-a-classical-operator-on-a-known-circle.md)'s
refusal rule applied to the dataset side.

**The canonical scale is defined here in one unambiguous sentence, because the
existing wording is ambiguous.** It is the **95th percentile of the measured
millimetres per pixel** — equivalently the 5th percentile of pixels per
millimetre, which is what SPEC 0037 calls `p5`. Read the other way round, `p50`
in SPEC 0037 is the median and is smaller than `p5`, which only makes sense once
the percentile is understood to run over pixels per millimetre. Nothing in this
decision changes SPEC 0037's rule; it states which of two readings of that rule
is the one the code implements.

## Alternatives Considered

- **Measure the soil disc instead of the glass rim.** Rejected on a measured
  counterexample. The soil boundary is by far the strongest edge in these
  photographs and is trivially found, but its physical diameter is not known: it
  is the dish's inner diameter only when the dish is full, and
  `images/Media/112098-3 (4).JPEG` is visibly under-filled, with bare glass along
  one side. A reference whose physical size depends on how much soil was poured
  is not a reference. The inner wall would also carry an unknown systematic
  offset from the 90 mm the owner confirmed, since that figure is the outer
  diameter.
- **Threshold the soil by colour and take the equivalent radius of the largest
  connected region.** Implemented and rejected on measurement. It is the cheapest
  operator that could work, and it fails on two real conditions in this archive:
  a warm off-white bench surface has the same red-minus-blue sign as soil, so the
  region leaks into the background, and an under-filled dish reads small. On a
  sample of 24 photographs it produced two readings wrong by a factor of nearly
  two while reporting nothing unusual, which is the failure mode ADR 0017 exists
  to prevent.
- **Add OpenCV and call `HoughCircles`.** Rejected. It is the same algorithm this
  spec implements in about eighty lines of NumPy, and it would add a large binary
  dependency to `ml/requirements.txt` for one function, in a pipeline whose
  environment pins are load-bearing for reproducibility
  ([SPEC 0051](0051-a-training-run-has-somewhere-to-happen.md)). The existing
  `ml/src/image_quality.py` establishes the project's pattern: classical image
  operators are written against NumPy and pinned by a committed golden.
- **Take the strongest circular response rather than the outermost.** Rejected on
  measurement. The strongest edge is the soil-to-glass boundary in every
  population, so a strongest-response rule measures the inner circle and inherits
  the fill dependence rejected above.
- **Leave SPEC 0037's 0.130 mm/px alone and recompute later, inside item A6.**
  Rejected. A6 builds the patch grid whose size is derived from the canonical
  value; deriving geometry from a constant measured over 42 % of the data, and
  then discovering the constant moved, would invalidate the geometry and every
  fixture asserted against it. The canonical is cheap to establish now and
  expensive to revise later.
- **Commit nothing and report the numbers in the pull request.** Rejected. The
  canonical is a contract value that a model is trained at and served at; the
  measurement behind it has to be diffable by a later run, which is the whole
  reason issue #212 asks for an artifact rather than a comment. The 2026-08-25
  measurement was reported in a comment and is the reason this work exists.
- **Write the per-photograph table under the dataset version.** Rejected as a
  direct contradiction of
  [ADR 0019](../adr/0019-a-dataset-version-is-a-build-product-and-nothing-under-it-is-versioned.md),
  which makes everything under `ml/data/datasets/` a build product and
  git-ignores it. The record lives in `ml/measurements/`, which is not a dataset
  version, and names the dataset version and manifest digest it was taken over so
  a reader can tell whether it still applies.

## Scope

- Includes:
  - `ml/src/scale.py` (new) — the dish-rim reader, its reading and refusal types,
    and the percentile that defines the canonical value.
  - `ml/scripts/measure_scale.py` (new) — runs the reader over a dataset version
    and writes the measurement record.
  - `ml/measurements/dish-scale-v1.json` (new, committed) — every photograph's
    millimetres per pixel with its capture population, plus the summary, the
    dataset version and the manifest digest.
  - `ml/tests/test_scale.py` (new) — one test per acceptance criterion, over
    synthetic fixtures that need no dataset, plus dataset-gated assertions on the
    committed record.
  - `docs/specs/0037-scale-normalised-greyscale-patch-pipeline.md` — the
    recomputation is recorded against the criterion that asked for it, and the
    canonical value is confirmed rather than amended.
  - `docs/architecture/ml-implementation-map.md` and
    `docs/architecture/ml-handoff.md` — B2's scale half is done, and the number
    the other terminals plan against is now measured over the whole archive.
- Does NOT include:
  - The normalisation itself — resampling any image to the canonical scale is
    SPEC 0037, work item A6.
  - The patch grid, the greyscale conversion, the aggregation and the dispersion
    metric. All SPEC 0037.
  - The `disc_diameter_px` manifest column, the validator rule that refuses a
    missing or non-positive value, and any change to the manifest schema. SPEC
    0037 names them and A6 lands them; adding a column here would migrate the
    manifest twice.
  - The Dart side. The application reads an A4 sheet by a different operator, and
    ADR 0017 records why the two sides do not share one reader.
  - `spec.json`. Publishing the canonical value into the contract is SPEC 0035
    and work item B3.
  - Regenerating the fold manifest. This spec reports whether the pool moved; it
    does not rebuild anything.
  - Quarantining any photograph from the dataset version, or removing any row
    from the manifest. The record names what a later normalisation will refuse;
    it does not act on it.

## Acceptance Criteria

- reads_the_rim_of_a_synthetic_dish_within_one_percent: given a rendered dish of
  known radius on a plain background, the reader returns a radius within 1 % of
  the rendered one.
- measures_the_outer_circle_not_the_inner_one: given a rendered dish whose inner
  filled disc is materially smaller than its outer rim, the reader returns the
  outer radius, not the inner one.
- refuses_when_no_circle_is_present: given an image with no circular structure,
  the reader returns a refusal naming `no_circle_found` and no scale.
- refuses_when_the_rim_is_inconsistent: given a rendered shape whose boundary
  departs from a circle beyond the dispersion threshold, the reader returns a
  refusal naming `inconsistent_rim` and no scale.
- never_substitutes_a_default_scale: no code path returns a millimetres-per-pixel
  value alongside a refusal, and a refusal carries `None` rather than a number. A
  test asserts this over every refusal cause.
- reports_dispersion_and_ray_coverage_with_every_reading: a successful reading
  carries the per-ray radius dispersion and the fraction of rays that found an
  edge, so a later reader can judge the measurement without re-running it.
- is_deterministic_across_runs: reading one image twice returns bit-identical
  values. There is no sampling and no seed.
- the_record_names_the_dataset_version_and_the_manifest_digest: the committed
  measurement record carries both, so a record taken over different data is
  recognisable as such.
- the_record_holds_one_row_per_photograph: the committed record holds exactly as
  many photograph entries as the manifest holds rows, each keyed by the
  manifest's image path and carrying its capture population.
- the_canonical_is_the_ninety_fifth_percentile_of_the_readings: the canonical
  value stored in the record equals the 95th percentile of the millimetres per
  pixel of the retained readings, recomputed from the record's own rows.
- the_summary_reports_each_population_separately: the record reports minimum,
  5th, 50th and 95th percentiles and maximum both overall and per capture
  population, so a later disagreement is attributable to a population.
- quarantine_is_reported_by_name_and_per_population: the record names every
  photograph that received no scale, with its cause and its population, and the
  counts per population are stated even when they are zero.
- the_measurement_reproduces_from_the_recorded_command: re-running the recorded
  command over the same dataset version reproduces the record byte for byte.

## Reproducibility

```sh
cd ml
.venv/Scripts/python -m pytest tests/test_scale.py -q
.venv/Scripts/python scripts/measure_scale.py --version v1
git diff --exit-code measurements/dish-scale-v1.json   # unchanged: the run reproduces
```

Python 3.12.13, `numpy==1.26.4`, `pillow==10.4.0`, the pinned stack of
`ml/requirements.txt`. The reader uses no random number generator, no seed and no
threading; the working resolutions are fixed constants and Pillow's bilinear
resize is deterministic.

Measured on this machine over dataset version `v1`, manifest digest
`231ce9684f741d702d16c80e72f6f65f906d2d9bf9f4ce584097b2827da0de85`:
**221 photographs read, 0 refusals, 175 seconds**.

The per-ray dispersion, which is what a wrong fit would inflate, stays far below
the refusal threshold on every photograph: median 0.0113, 95th percentile 0.0223,
maximum 0.0287. Ray coverage is at least 0.851 and is 0.982 at the 5th
percentile.

**Millimetres per pixel, overall and per capture population:**

| Population | n | min | p5 | p50 | p95 | max | spread |
|---|---|---|---|---|---|---|---|
| A — JPEG export, 1536 × 2048, EXIF kept | 44 | 0.0718 | 0.0740 | 0.0866 | 0.0984 | 0.1100 | 1.53× |
| B — transported JPEG, ~1600 × 900, EXIF lost | 48 | 0.1159 | 0.1179 | 0.1257 | 0.1552 | 0.1667 | 1.44× |
| C — native HEIC session, 3024 × 4032 | 129 | 0.0357 | 0.0376 | 0.0451 | 0.0583 | 0.0647 | 1.82× |
| **All** | **221** | **0.0357** | **0.0380** | **0.0546** | **0.1298** | **0.1667** | **4.67×** |

**The canonical is 0.1298 mm/px, and SPEC 0037's 0.130 mm/px is confirmed rather
than amended.** Adding the 129 finest photographs to a percentile computed
without them moved it by 0.0002 mm/px, and the reason is arithmetic rather than
luck: the coarse tail is entirely population B, and the 11th coarsest of 221 sits
almost exactly where the 5th coarsest of 92 sat. The patch geometry SPEC 0037
derives from the canonical — a 20.8 mm patch at 160 px, twenty-five patches on a
90 mm disc — therefore stands unchanged.

**The archive's scale spread is 4.67×, not the 2.6× ADR 0016 recorded.** That
record measured the 92 readable JPEGs; the HEIC session is finer than every one
of them, so the range could only widen once it was included.

**Eleven photographs are coarser than the canonical and a later normalisation
will refuse them rather than upsample.** All eleven are population B. They belong
to seven sample groups, five of which lose every photograph — and **all seven are
already train-only** under SPEC 0040 D6, because population B lost its EXIF and
its scale provenance with it. The splittable pool therefore stays at 77 groups,
the fold manifest does not need regenerating, and the minimum detectable effect
SPEC 0042 records does not move. This is the condition SPEC 0042's assumption
names, measured and found not to bind.

**Two independent corroborations, because a scale reader that is wrong in a
consistent way looks right.** First, populations A and C are the same dish
photographed by the same iPhone 11 and exported at long-side ratio 1.97; their
median millimetres per pixel differ by a factor of 1.92, which is that ratio
recovered from the pixels rather than from the file header. Second, over the same
92 photographs the 2026-08-25 measurement covered, this reader gives a range of
0.0718 to 0.1667 mm/px against that measurement's 0.0670 to 0.1745 — the two
agree on the extremes to within 5 to 7 %. Their medians differ more, 0.1173
against 0.100, and the reason is that the A-plus-B distribution is bimodal with
44 and 48 members: its median falls in the gap between two populations, where a
few photographs move it a long way. The median of a bimodal sample is not a
statistic worth reconciling, and the canonical is a tail percentile rather than a
median.

## Risks and Assumptions

- **Assumption: the archive dishes are 90 mm across the outer rim.** Confirmed by
  the project owner on 2026-08-25 and already load-bearing in ADR 0018 and
  SPEC 0037. Every absolute millimetre figure in this project rests on it. If the
  figure is the inner diameter instead, every reading here is systematically
  about 4 % coarse — which cancels within the dataset, because one dish
  photographed throughout means one constant factor, and does **not** cancel
  against the application, which reads an A4 sheet and gets an absolute scale.
- **Assumption: the outermost strong radial edge is the dish rim.** It holds on
  every photograph of this archive, where the dish sits on a plain surface with
  nothing else around it. It would not hold on a cluttered background, and the
  dispersion refusal is the guard rather than the fix.
- **Risk: the refusal thresholds are set above a measured maximum, not
  calibrated.** Nothing in this archive comes close to them, so they are
  untested against a real failure and their only calibration is that they admit
  every photograph that a human reading the images agrees is a dish. That is
  stated rather than hidden, and it is the same position SPEC 0030's uncalibrated
  criteria ship in.
- **Risk: the committed record can drift from the dataset it describes.** It
  names the manifest digest so drift is detectable, but nothing recomputes it
  automatically, and a dataset version `v2` would need its own record and its own
  canonical.
- **Risk: a reading can be confidently wrong on a photograph where a second
  circular structure is more prominent than the rim.** The dispersion measure
  catches a fit that is not circular; it does not catch a fit that is circular and
  is the wrong circle. The corroborations above are what stand in for a ground
  truth this project does not have.
- **What would invalidate this spec:** a dish of a different diameter appearing in
  the archive, a decision to normalise toward the median rather than the coarsest
  retained photograph, or a re-ingestion that changes the manifest digest.
