# SPEC: feat(inference): measure the soil on the a4 sheet and classify with it

## Problem

SPEC 0091 finds the A4 sheet and rectifies it, but nothing yet finds the soil
on the sheet or hands a measurement to `classify`, so the service still ships
`measurementUnavailable` and every photograph is still refused, which is the
last step between the app and its first classification (ADR 0026).

## Design Decision

**`a4SheetMeasurer` replaces `measurementUnavailable` as the service's
measurer.** It is a top-level function, so it can be sent to the classification
isolate (SPEC 0083). It returns what the seam already expects: a frame, its
millimetres per pixel, and the soil region's centre and diameter.

1. **Find the sheet** with `findSheet`. `notFound` becomes the cause
   `sheetNotFound`, and `cropped` becomes `sheetCropped`.
2. **Find the soil patch on a coarse rectification.** The whole sheet is
   rectified at 2 px/mm (420 × 594 px), which is cheap and enough to locate a
   patch 8 to 10 cm across. A 5 mm band along the sheet's edges is ignored,
   because the paper's rim carries shadow and the surface's colour bleeds into
   it. Soil is what Otsu's threshold, taken over the interior, puts on the dark
   side. The patch is the largest dark 4-connected component, with its holes
   filled.
3. **Take the largest disc inside the patch.** The disc's centre is the
   patch's point farthest from paper, found by an exact Euclidean distance
   transform. Its radius is that distance less a **2 mm margin**, so the grid's
   outermost patch corners stay on soil when the patch's edge is irregular. A
   round patch then yields a disc about as wide as the patch, the geometry of
   the dish the model was trained on. An irregular patch yields the largest
   round part of it, and never pixels of paper.
4. **Rectify only the square around the disc, at native resolution**, with
   `rectifySheet`'s region. That is about a ninth of the sheet, so the
   full-resolution projective pass never covers pixels the grid does not read.
   The measurement is expressed in that square's pixels.

No patch at all, meaning no dark component in the interior, is the existing
`soilRegionTooSmall`. The remedy is the same: put soil on the sheet and spread
it. A disc too small for the grid's minimum patch count is refused by the grid
itself, under the same cause, as it is today.

**The failure causes follow, and ADR 0015 is amended again.** They go from
thirteen to fourteen:

- `sheetNotFound` and `sheetCropped` arrive in the "retry, or retake the
  photograph" column, as ADR 0017 placed them.
- `measurementUnavailable` leaves, together with the function of that name,
  because nothing is left that fails that way. SPEC 0083 declared it to be
  retired by this reader.

The amendment is appended after SPEC 0083's, because
`failure_causes_follow_adr_0015` reads the table under the last "Amended"
heading.

**The cost is re-measured.** The SPEC 0086 harness gains a second scene: a
12 MP photograph of a sheet with a soil patch, drawn in Dart. It times
`classify` end to end with the real measurer. The scene tests cost, not
geometry. Geometry is graded against SPEC 0091's independent fixtures.
`docs/ml/descriptor-path-cost.md` gains the new figures.

## Alternatives Considered

- **The patch's bounding circle, or its area-equivalent circle.** Rejected.
  Both reach outside an irregular patch, so the grid would read paper as soil.
  The inscribed disc is the only one of the three guaranteed to hold only soil.
- **Locating the patch at full resolution.** Rejected. It is a 12 MP pass to
  find something 90 mm wide, and 2 px/mm resolves its edge to half a
  millimetre, far finer than the 2 mm margin.
- **A dedicated cause for an empty sheet.** Rejected. Its remedy is
  `soilRegionTooSmall`'s, and a cause is added when something can fail in a way
  that changes what the user does (ADR 0015).
- **Keep `measurementUnavailable` declared.** Rejected. It would be a cause
  with no producer, in a type the UI switches over, which the Developer refused
  in SPEC 0083.

## Scope

- Includes:
  - `lib/core/services/descriptors/a4_sheet.dart` gains `a4SheetMeasurer`, the
    soil-patch location and the inscribed disc.
  - `lib/core/services/descriptors/photograph_measurement.dart` loses
    `measurementUnavailable`.
  - `InferenceService`'s default measurer becomes `a4SheetMeasurer`.
  - `ClassificationFailureCause` gains `sheetNotFound` and `sheetCropped`, and
    loses `measurementUnavailable`. ADR 0015 gains a second 2026-09-29 amendment.
  - The tests:
    - the measurer against SPEC 0091's fixtures: the disc's centre and diameter
      against the golden's soil patch, and the two refusals;
    - an end-to-end `classify` that returns `ok` for a sheet photographed at
      12 MP;
    - the capture-screen and inference tests that named the retired cause;
    - `failure_causes_follow_adr_0015`, with fourteen causes.
  - The SPEC 0086 harness's second scene, and the record's new figures.
  - README, `docs/agents/project.md` (with `CLAUDE.md` regenerated) and the
    map: the app now classifies a photograph taken to the protocol.
- Does NOT include:
  - Any screen that shows a cause, or offers a retry for it. That is the UI/UX
    terminal's roadmap item 2.
  - The onboarding copy (#282), which the other session writes from ADR 0017's
    protocol.
  - Validation on real photographs, which is still owed before the Play
    release (SPEC 0091, Risks).
  - Calibration or verdict bands (C2).
  - Any change to the patch grid or the descriptors.

## Acceptance Criteria

- `the_soil_disc_is_found_on_the_sheet`: over SPEC 0091's whole-sheet fixtures,
  the measured disc's centre lies within 2 mm of the golden patch's centre. Its
  diameter is the patch's less twice the margin, within 3 mm.
- `a_missing_sheet_is_refused_as_sheet_not_found` and
  `a_cropped_sheet_is_refused_as_sheet_cropped`: from `a4SheetMeasurer`, on the
  `no_sheet`, `pale_on_pale` and `cropped` fixtures.
- `an_empty_sheet_is_refused_as_soil_region_too_small`: a whole sheet with no
  patch.
- `a_sheet_photograph_is_classified`: `InferenceService` with its default
  measurer returns an `ok` report for a 12 MP photograph of a sheet with a soil
  patch, through the real isolate.
- `the_default_measurer_is_the_a4_sheet_reader`: `InferenceService().measurer`
  is `a4SheetMeasurer`.
- `failure_causes_follow_adr_0015`: the enum equals the table under ADR 0015's
  latest "Amended" heading, fourteen causes.
- The harness re-run records `classify`'s median and maximum with the real
  measurer, and the record states whether they fit the 15 s timeout.

## Reproducibility

```sh
flutter test test/services/a4_sheet_test.dart test/services/inference_service_test.dart test/features/capture/capture_screen_test.dart
flutter analyze && flutter test && mf check
flutter drive --profile -d emulator-5554 --driver=test_driver/integration_test.dart --target=integration_test/descriptor_path_cost_test.dart
```

## Risks and Assumptions

- **Assumption: soil is darker than paper.** Every soil class in the archive is,
  and a sheet with nothing darker on it is the empty-sheet refusal.
- **Risk: shadows.** A hard shadow across the sheet is dark too. The 5 mm band
  handles the rim. A shadow reaching the interior could be taken for soil if it
  is larger than the patch. Real photographs are where this shows (SPEC 0091's
  owed validation).
- **Risk: cost.** It adds the coarse rectification, the distance transform and
  a region rectification of about 1.3 MP. The harness re-run is where that is
  measured, and the record says whether it fits.
- **Merge order:** after SPEC 0091 (#303), on which this branch is stacked.
