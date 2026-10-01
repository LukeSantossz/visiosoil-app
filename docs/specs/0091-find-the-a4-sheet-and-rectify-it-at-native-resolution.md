# SPEC: feat(inference): find the a4 sheet and rectify it at native resolution

## Problem

The app cannot classify any photograph, because nothing measures a
photograph's scale (the only measurer is `measurementUnavailable`, SPEC 0083),
although ADR 0017 fixes the reference as a bare A4 sheet whose four corners give
the millimetres per pixel and the homography, and ADR 0026 makes the reader
that finds them the Google Play release's critical path.

## Design Decision

**The reader is split in two.** This spec finds the sheet and rectifies it. The
next spec (0092 or later) finds the soil on the rectified sheet and wires the
reader into `classify`. Both halves are pure Dart arithmetic over pixels: no
model and no native dependency. Each half stays small enough for one R2 pass.

**The capture protocol, decided by the Developer on 2026-09-29.** It is
recorded here because #282's onboarding copy waits on it:

1. Put a bare white A4 sheet flat on a surface **darker than the paper**. The
   sheet carries nothing else (ADR 0017).
2. Spread the soil into a **round patch about 8 to 10 cm across in the middle of
   the sheet**. That mirrors the 90 mm dish the model was trained on, so the
   patch grid (SPEC 0081) is unchanged.
3. Photograph **from above**, with the **whole sheet in the frame** and a margin
   around it, in diffuse light and without flash.

**Finding the sheet.** These are classical steps, fixed so that review can
check them:

1. Work on a detection copy whose long side is at most 1024 px, reduced by box
   averaging, in BT.601 grey (`greyOf`, as the patch grid uses).
2. Separate bright from dark with Otsu's threshold, and take the largest bright
   4-connected component. A component covering almost the whole frame is a
   pale sheet on a pale surface, or no sheet at all, and is refused as
   **`notFound`**. So is a component too small to be a sheet at the protocol's
   framing.
3. Take the convex hull of the component's boundary, and from its vertices the
   quadrilateral of largest area. Refine each of the four edges by a
   least-squares line through the boundary points near it, and take the
   corners as the lines' intersections, scaled back to full resolution.
4. A corner outside the frame, or a sheet edge running along the frame's
   border, is refused as **`cropped`**. A quadrilateral that is not convex, or
   whose opposite edges differ beyond what a photograph from above can produce,
   is `notFound`.

The long side is the pair of opposite edges with the larger mean length, and
it maps to 297 mm.

**Rectifying at native resolution, then the byte-exact resample.** The four
corners give a homography, solved by the 4-point direct linear transform in
double precision. The rectified sheet is sampled at the sheet's own mean scale
along its long edges, so perspective is corrected with the scale close to
1 : 1, by bilinear projective sampling. The rectified frame's millimetres per
pixel are exact by construction: 297 mm over its long side in pixels.

The descriptors never see this sample directly. The patch grid then takes the
rectified frame to the canonical 0.129 mm/px with ADR 0025's `BILINEAR`, which
is identical to training. That resample, a reduction of about 4× at 12 MP,
shapes the frequencies the descriptors read, and it is the one that has to
match. The near-identity rectification only softens detail finer than the
canonical Nyquist, which the reduction removes anyway.

**A region, not only the whole sheet.** `rectifySheet` takes an optional
rectangle in the sheet's millimetres and samples only that. The next spec
rectifies only the square around the soil patch, which is about a ninth of the
sheet, because rectifying the whole sheet at native resolution costs a
full-frame pass for pixels the grid never reads.

**The tests grade the reader against an independent geometry.**
`ml/scripts/generate_sheet_fixtures.py` renders synthetic scenes with numpy and
Pillow's `Image.transform(PERSPECTIVE)`, a projective implementation the Dart
reader shares nothing with. It writes JPEGs and the corners, scale and marks it
placed. The Dart tests recover them. A renderer written in Dart would test the
reader's mathematics with a copy of itself.

**ADR 0017 is amended** to record the rectification's resolution and order,
and the combined-warp alternative this rejects.

## Alternatives Considered

- **One warp straight to the canonical scale.** Rejected by the Developer on
  2026-09-29. It uses one resample instead of two, but a projective bilinear
  sample reducing about 4× applies no anti-alias filter. It would fold aliasing
  into the band the spectral descriptors measure, the very defect #180 existed
  to prevent.
- **Not rectifying; refusing a tilted photograph.** Rejected by the Developer on
  2026-09-29. It would have matched training's unrectified photographs, and
  amended ADR 0017's tilt correction away.
- **Wait for real photographs.** Rejected by the Developer on 2026-09-29.
  Synthetic scenes test the geometry now. Real photographs test robustness in
  the field, and that is recorded as a step still owed (Risks).
- **A contour-following polygon simplification (Douglas–Peucker) to four
  vertices.** Rejected for the hull's largest quadrilateral. The hull is immune
  to the soil patch denting the sheet's outline, and to a shadow nicking an
  edge.
- **A native computer-vision dependency (OpenCV).** Rejected. It would add a
  native library to both platforms for two operators, which ADR 0024 keeps out
  of the runtime.

## Scope

- Includes:
  - `lib/core/services/descriptors/a4_sheet.dart`:
    - `SheetRefusal { notFound, cropped }`;
    - `findSheet(RgbFrame)`, which returns four ordered corners, the long side
      marked, or a refusal;
    - `rectifySheet(RgbFrame, corners, {region})`, which returns the rectified
      frame and its millimetres per pixel.
  - `ml/scripts/generate_sheet_fixtures.py`, and its fixtures under
    `test/fixtures/sheet/` (JPEGs plus `golden.json`). The cases are: frontal;
    tilted about 15° and 30°; rotated in plane; landscape; dark and mid-grey
    backgrounds; one with marks at known millimetre positions for
    rectification; cropped; no sheet; a pale sheet on a pale surface; and every
    scene with a soil patch where the protocol places it.
  - `ml/tests/test_sheet_fixtures.py`, asserting the fixtures regenerate byte
    for byte.
  - `test/services/a4_sheet_test.dart`.
  - ADR 0017's amendment.
- Does NOT include:
  - Finding the soil patch on the sheet, the measurer, wiring into `classify`,
    and the new failure causes in `ClassificationFailureCause`. All of those
    belong to the next spec. `SheetRefusal` stays local until then, as
    `PatchRefusal` does.
  - The onboarding copy (#282), which follows the protocol above in its own
    change.
  - Validation on real photographs.
  - Performance tuning beyond the region rectification. The next spec's wiring
    re-measures the cost with SPEC 0086's harness.

## Acceptance Criteria

- `a_sheet_is_found_within_tolerance`: over every fixture that holds a whole
  sheet, each detected corner is within 0.5 % of the sheet's diagonal of the
  placed corner. The rectified millimetres per pixel are within 1 % of the
  placed scale.
- `no_sheet_is_refused_as_not_found` and
  `a_pale_sheet_on_a_pale_surface_is_refused_as_not_found`.
- `a_cropped_sheet_is_refused_as_cropped`.
- `a_mirrored_photograph_reads_the_same_scale`: the fixture and its mirror image
  give the same millimetres per pixel within 0.5 %. A geometric invariant is
  what caught the dish reader measuring the wrong circle (SPEC 0052).
- `rectification_puts_marks_where_the_sheet_has_them`: on the marked fixture,
  each mark's centroid in the rectified frame lies within 1 mm of its placed
  position.
- `rectification_keeps_the_native_scale`: the rectified pixels per millimetre
  are within 5 % of the sheet's mean scale in the photograph.
- `a_region_is_rectified_alone`: rectifying a millimetre rectangle gives the
  same pixels as cutting that rectangle from the whole rectified sheet.
- `the_sheet_fixtures_regenerate`: in `ml/`, the generator reproduces the
  committed fixtures byte for byte.

## Reproducibility

```sh
cd ml && python scripts/generate_sheet_fixtures.py && python -m pytest tests/test_sheet_fixtures.py -q
flutter test test/services/a4_sheet_test.dart
flutter analyze && flutter test && mf check
```

Flutter 3.44.1, Python 3.12 with `ml/requirements.txt`'s Pillow and numpy.

## Risks and Assumptions

- **Risk: synthetic scenes are cleaner than the field.** Soft shadows, a curled
  sheet, a patterned tablecloth and JPEG artefacts at the edges are all
  missing. **Real-photograph validation is owed.** It needs 5 to 10 photographs
  taken to the protocol above, and it lands as a recorded check against this
  reader before the Play release. It is not a condition of this spec.
- **Assumption: the surface is darker than the paper.** The protocol asks for
  it. Where it fails, the refusal says so, and nothing guesses a sheet (ADR
  0017).
- **Risk: cost.** A full-resolution rectification of the whole sheet is a
  12 MP projective pass. The region parameter exists so the wiring never pays
  it. SPEC 0086's harness re-measures the whole path in the next spec.
- **What would invalidate this spec:** real photographs showing the sheet's
  corners cannot be found classically at useful reliability. ADR 0017 already
  names the fallback, a printed fiducial marker, and the project owner's
  bare-sheet constraint would then have to be revisited.
