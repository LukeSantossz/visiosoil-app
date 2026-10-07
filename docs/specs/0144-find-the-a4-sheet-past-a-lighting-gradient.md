# SPEC: fix(inference): find the a4 sheet past a lighting gradient

## Problem

The A4-sheet reader refuses 160808 and 160808_1 as `notFound` although each holds a whole sheet, because a lighting gradient darkens one side of the paper below the reader's threshold, so the reader fits that edge along the gradient and the edge-step check of SPEC 0140 rightly rejects it.

SPEC 0140 recorded these two photographs as a safe refusal, with the protocol's diffuse light as the remedy. They are 2 of the 7 photographs the reader still refuses from the 2026-10-05 session. The other 5 hold no sheet, or a sheet that leaves the frame, and are refused correctly. These 2 hold a whole sheet, and their four paper edges can be measured on the photograph.

What happens on the committed fixture `photo_160808.jpg` (1024 × 461):

- The table on the right is lit less than the table on the left. The paper darkens with it, from about 190 grey across most of the sheet to about 165 at its right edge.
- The second split of SPEC 0140 puts its threshold at 181. The right part of the paper falls under it, so the paper region's right boundary is a curved contour of the gradient. It runs from x ≈ 670 at the top to x ≈ 730 at the bottom.
- A lit patch of table joins the region to the frame's border at the bottom left, so the reader takes the line path. Its right line follows the contour.
- The paper's true right edge is at x ≈ 761 at the top and x ≈ 758 at the bottom. It steps about 20 grey levels from paper to table. The edge the reader fits steps 3, under the floor of 10, so the reader refuses.

## Design Decision

The reader keeps every step it has today. It gains one step, which runs only where today's reader refuses with exactly one weak edge. If that step finds the paper's edge, the reader checks the new quadrilateral exactly as it checks the first one.

**When it runs.** After the edge-step check of SPEC 0140, if exactly one of the four edges steps by less than `_minEdgeStep` (10) and the other three pass, the reader looks for that edge's paper boundary past the gradient. Two or more weak edges are refused as `notFound`, as they are today. So is a sheet whose edge is not found by this step.

**1. A scan across the sheet, row by row.** The weak edge runs from corner a to corner b. The opposite edge runs from d to c, and the two side edges run from d to a and from c to b.

1. Rows are placed along the opposite edge at fractions f in the middle 80 % of its length, one row per detection pixel of the longer of the weak and opposite edges.
2. Each row starts on the opposite edge and points toward the weak edge. Its direction blends the two side edges' directions: (1 − f) along d → a, and f along c → b. So the rows fan out with the perspective.
3. Each row starts 8 px in (`_gradientInsetPx`) and moves forward while it stays inside the paper region. It leaves the region at the gradient's contour.
4. From there, it reads a step at each pixel: the mean grey of the 8 pixels behind it (`_gradientBandPx`) less the mean of the 8 pixels ahead. It scans forward up to 8 % of the detection copy's long side (`_gradientReach`, 82 px at 1024 px).
5. The row's point is the peak of the **first** run of steps at or above `_minEdgeStep`. The first run, not the strongest: on 160808 the table's own border, about 36 px past the paper's edge, steps by 30 or more, which is more than the paper's 20.

**2. A straight edge through the rows' points.**

1. At least half of the rows must give a point.
2. A total-least-squares line is fitted through the points. Points more than 2 px off the line (`_gradientTrimPx`) are dropped, and the fit is repeated up to three times.
3. At least half of the rows must still have a point on the line.
4. The new line replaces the weak edge. The other three edges keep their lines, and the four lines meet in the new corners.

**3. The surface must continue round each new corner.** At a true corner, the surface just outside the two edges is the same surface at the same place, so it reads about the same grey. At a false corner, such as the table's own border, it does not.

For each of the two new corners, the reader compares two medians:

- the grey 4 px (`_edgeOffsetPx`) outside the new edge, from 5 % to 20 % of its length from the corner;
- the grey at the same offset outside the side edge, over the same fractions of its length from the corner.

They must differ by less than that side edge's own paper-to-surface step, which the edge-step check measured on the first pass. A surface that changes across the corner by as much as paper differs from the surface marks a corner on a boundary of the surface, not of the sheet.

| On `photo_160808.jpg` | Difference round the corner | Side edge's step |
|---|---|---|
| The true edge, bottom-right corner | 14 | 24.5 |
| The true edge, top-right corner | 10.5 | 26 |
| The true edge under the darkening variant, worst corner | 12 | 19.5 |
| The paper edge erased, the scan lands on the table's border | 41 and 42 | 24.5 and 26 |

**4. The same checks as the first pass.** The new corners go through the plausibility check, the in-frame check and the edge-step check, unchanged. The step is not repeated: a second weak edge is refused as `notFound`.

**The values.** The scan's reach was swept on `photo_160808.jpg`:

- 0.02 of the long side finds the edge on no row, so 160808 is refused.
- 0.04 finds it on 231 of 327 rows. This is the least that reads the sheet.
- 0.08 finds it on all 327 rows. So do 0.10, 0.12, 0.15 and 0.20, and they give the same corners.

0.08 is the least that finds the edge on every row. The reach does not keep the scan off the table's border: near the bottom of the sheet the border is 67 px from the contour, inside the reach. The first-run rule and the corner check do that. The inset of 8 px, the band of 8 px and the trim of 2 px were not tuned, and a band of 4 px gives the same result.

**The tests use the committed photograph.** In `test/fixtures/sheet_photos/expected.json`, 160808 becomes a sheet. Its corners are measured on the full-resolution original with the method the file records for the other photographs, and mapped to the fixture: (219.5, 23.5), (218.7, 426.2), (757.6, 433.3) and (760.9, 23.0). A second measurement, by lines fitted through 25 points of each edge, agrees within 1.5 px. The reader's corners lie within 27 % of the 1 % tolerance and its scale within 0.15 % of the measured one, and within 40 % and 0.21 % under the five variants.

A new test erases the paper's right edge on `photo_160808.jpg` by a linear ramp across columns 735 to 785, which leaves the table's border at x ≈ 797 in place. The reader must refuse the result as `notFound`, and under each of the five variants. Without the corner check, the scan lands on the table's border, and the reader returns a sheet about 7 % too wide. On four ramps (735–785, 745–790, 730–775, 740–795) under the six conditions, that happens 19 times in 24. With the check, all 24 are refused.

## Alternatives Considered

- **Keep refusing.** SPEC 0140's position, with diffuse light as the remedy. Rejected, because the paper's edge is visible on these photographs and its step of about 20 is twice the floor. A refusal the photograph does not need costs the agronomist a retake.
- **Flatten the lighting before the split.** Dividing the grey by a blurred copy of itself is the classical remedy for a gradient. Rejected, because it would change the paper region on every photograph, including the 24 the reader already reads and every synthetic scene. The scan runs only where the reader refuses today.
- **Scan outward from the weak edge, parallel to it.** Tried first. It passes the clean photograph, the quarter turn, the mirror and the darkening, but it fails under the noise variant: the noisy weak edge lies slanted across the true one, so its parallels cross the paper's edge at a slant. Rejected. Rows anchored on the paper region's boundary do not depend on the weak edge's angle.
- **Take the strongest step in reach.** Rejected. The table's border steps more than the paper's edge, so the strongest step is the wrong edge.
- **Check the new edge's step only.** Rejected. That is the check that lets the erased edge through: the table's border steps by 30 or more.
- **An aspect-ratio check against A4.** Rejected. Perspective distorts the ratio. On 160808 the true quadrilateral reads 1.33, and the false one through the table's border reads 1.42, nearer A4's 1.414.

## Scope

- Includes:
  - `lib/core/services/descriptors/a4_sheet.dart`: the scan past a weak edge, the corner check, and their constants `_gradientReach`, `_gradientBandPx`, `_gradientInsetPx` and `_gradientTrimPx`.
  - `test/fixtures/sheet_photos/expected.json`: 160808 becomes a sheet, with its measured corners.
  - `test/services/a4_sheet_photos_test.dart`: the fixture count becomes five sheets and one refusal, and the erased-edge test is added.
  - `docs/ml/sheet-reader-real-photographs.md`: 26 of 31 read, 160808 and 160808_1 rows, the variants and margins tables, and what the check does not show.
  - The README, `docs/agents/project.md` with the instruction files `mf agents sync` generates from it, and `docs/architecture/ml-implementation-map.md`. Each says the reader reads 24 of the 31 photographs.
- Does NOT include:
  - Two or more weak edges. They stay refused as `notFound`.
  - The floors `_minContrast` (60), `_minPaperContrast` (20) and `_minEdgeStep` (10), the hull path, the line path or `_refinedCorners`.
  - A synthetic gradient scene in `ml/scripts/generate_sheet_fixtures.py`. The measured corners on 160808 are the reference, and the variants move them.
  - The patch grid. 160808 and 160808_1 hold a soil disc too small for nine patches, so both end in `soilRegionTooSmall` like the other 24.
  - The capture screen, onboarding copy, the model and the contract.

## Acceptance Criteria

- `a_real_sheet_is_found_where_it_lies` holds for 160808: each found corner within 1 % of the long side of an annotated corner, and each annotated corner of a found one, and the scale within 1 %. This fails on today's reader, which refuses 160808 as `notFound`.
- `the_verdict_survives_the_variants` holds for 160808 as a sheet under all five variants. This fails on today's reader.
- `the_fixtures_hold_five_sheets_and_one_refusal`: the fixture holds five sheets, and one refusal, `cropped`. This fails on today's fixture.
- `a_real_photograph_without_a_true_edge_is_refused` still refuses 160812 as `cropped`.
- `an_erased_paper_edge_is_not_read_at_the_table_border`: `photo_160808.jpg` with columns 735 to 785 replaced by a linear ramp is refused as `notFound`, and so is each of its five variants. This passes on today's reader, which never scans, and it fails on the scan without the corner check.
- Every test in `test/services/a4_sheet_test.dart` passes unchanged.
- On the 31 originals, the reader's verdict and corners are unchanged on 29. On 160808 and 160808_1 it finds the sheet. The check document records both.

## Reproducibility

```sh
flutter test test/services/a4_sheet_test.dart test/services/a4_sheet_photos_test.dart
flutter analyze && flutter test && mf check
```

Flutter 3.44.1 and Dart 3.12.1. The originals stay out of git, under the ignored `/images/` folder. The comparison on all 31 runs `findSheet` on each original after `bakeOrientation`, on `main` and on this branch, through a throwaway test that is not committed.

## Risks and Assumptions

- **Risk: a straight feature on the surface past an invisible paper edge.** If the paper's edge does not step on most rows, and a seam, tape or shadow line on the same surface runs parallel to it within reach, the scan can land on it. The corner check stops it only when the surface changes across the line. A line on one even surface does not change it. This needs a weak paper edge, a parallel line within 8 % of the frame, and a surface the same on both sides of that line, all at once. The remedy is still the protocol's diffuse light and plain surface.
- **Risk: the values come from one photograph pair.** The reach, band, inset and trim were set on 160808 and its twin. Every other photograph of the session and every synthetic scene is untouched, because none of them reaches the scan. A new session with a gradient is what would test them.
- **Risk: a corner hidden by an object on the table.** The corner check reads the surface near each new corner. An object lying there changes that surface, and the sheet is refused. That is the safe answer.
- **Assumption: the gradient is smooth across the paper.** The scan crosses it as a ramp with no step of 10 inside 8 px. A sharp shadow edge across the paper would stop a row early. The half-the-rows rule and the trimmed fit reject a few such rows. Many would leave the sheet refused.
- **Still owed:** classification end to end on a real photograph, which needs a soil patch 8 to 10 cm across.
- **What would invalidate this spec:** a photograph where the scan returns a sheet whose scale is more than 1 % from the measured one. The erased-edge test is the case built to show it, and the check document records the scale on 160808 and 160808_1.
