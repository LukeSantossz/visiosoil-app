# SPEC: fix(inference): find the a4 sheet on a pale table

## Problem

The A4-sheet reader (SPEC 0091) refuses all 31 real photographs taken on 2026-10-05, so the app cannot classify a field photograph at all. The scenes follow ADR 0017's surface rule, because the table is darker than the paper. Two faults in the reader cause the refusals:

- **One global threshold merges paper and table.** The table is pale grey. Otsu's split falls between the table and the dark objects (soil, shadows, a container), not between the paper and the table. The paper's contrast with the table is about 32 to 43 grey levels, which is under the reader's floor of 60. The merged bright region fills the frame (`notFound`) or reaches its border (`cropped`).
- **One lit spot joins the sheet to the frame's border.** Even at a threshold that separates paper from table, a bright reflection on the table touches one corner of the sheet and runs to the edge of the photograph. The reader refuses any region that touches the border as `cropped`, even when the four corners of the sheet are in view.

SPEC 0091 recorded this risk ("synthetic scenes are cleaner than the field") and owed a check against real photographs. This is that check, and the fix it calls for.

## Design Decision

The reader keeps every step it has today. It gains three steps, and each one runs only where today's reader refuses.

**1. A second split on the bright side.** The reader still runs Otsu on the whole detection copy and still refuses below the contrast floor of 60. A low-contrast photograph cannot hold a sheet, and that refusal does not change. If the largest bright region fills more than 90 % of the frame, or touches its border, the reader runs Otsu again on the pixels above the first threshold only. This splits the paper from the pale table. If the two bright classes differ by at least **20** grey levels (`_minPaperContrast`), the reader uses the region above the second threshold. Otherwise it keeps the first region. Paper on a pale table differs by 32 to 43. Noise on bare paper differs by less than 20.

**2. Straight lines when the region touches the border.** A region that still touches the border goes through a line fit instead of the convex hull. A spot that leaks across a corner bends the hull, but it does not bend the sheet's four straight edges. The steps are:

1. Run a Hough transform on the region's boundary points (0.5° and 1 px bins).
2. Take the strongest line.
3. Take the strongest line at least 45° from it.
4. For each of those two, take the strongest line of the same family with the centroid of the region's boundary between the pair.
5. The four lines meet in a quadrilateral. From there, today's least-squares refinement and plausibility checks apply unchanged.

If four lines cannot be found, the reader refuses as `cropped`, which matches today's verdict. A region that does not touch the border goes through today's hull path, byte for byte.

**3. Each edge must be a step from paper to surface.** After the corners are in the frame, the reader compares the grey just inside and just outside each edge. It samples at 4 detection pixels in from the edge and 4 pixels out, over the middle 80 % of the edge.

- If fewer than half of those positions have both samples inside the frame, the edge runs along the frame's border. The reader refuses as `cropped`, which is SPEC 0091's rule for such an edge. This check runs on all four edges before any step is judged, so a sheet that leaves the frame is called `cropped` whether or not one of its corners is just inside it.
- Otherwise, the step is the median inside minus the median outside. If an edge's step is under **10** (`_minEdgeStep`), the reader refuses as `notFound`. A real paper edge on the committed photographs steps by 25 to 40, and by 20 or more under the variants below. A false edge along a lighting gradient steps by 4 or 5. Without this check, the false edge gives a quadrilateral that passes the checks above but is about 6 % short, and that would be a silent scale error, which ADR 0017 forbids. The check runs on both paths, so a hull edge must also step.

**The tests use the real photographs.** Six photographs are committed, reduced to a 1024 px long side with their orientation baked in and their EXIF removed:

- four where the reader finds the sheet;
- one it must refuse as `notFound` (the lighting gradient);
- one it must refuse as `cropped`.

Each photograph that holds a sheet has its corners annotated in `test/fixtures/sheet_photos/expected.json`. They are measured on the full-resolution original: the strongest grey step across each edge, 8 px in from the corner, mapped to the reduced photograph. They agree with a reading by eye to within 1.5 px.

The corners are judged at 1 % of the photograph's long side, which is wider than the synthetic scenes' 0.5 % of the diagonal. A real sheet is not the straight-edged quadrilateral a renderer draws. On one photograph, the paper's bottom edge bows by about 2.5 px, and the lit table leaks along the left part of that edge. The straight line the reader fits through the edge's middle therefore meets the next edge 0.87 % of the long side from the measured corner. The scale it reads, which is what the app uses, is still within 0.3 %. So each photograph is also judged on its scale: 297 mm over the mean long edge of the found corners must be within 1 % of the same reading from the annotated corners.

Each photograph also runs under five deterministic variants, with the annotated corners moved by the same transform:

- a quarter turn;
- a mirror image;
- a darkening to 85 %;
- seeded noise of ±8 grey levels;
- a reduction to 75 %.

These variants run in the test only. Training and the dataset are untouched. The 31 originals stay out of git, and `docs/ml/sheet-reader-real-photographs.md` records each photograph's verdict before and after this fix.

A synthetic `pale_table_lit` scene is added to `ml/scripts/generate_sheet_fixtures.py`. It has a table a little darker than the paper, and a lit spot that joins one corner of the sheet to the frame's border. Its geometry is exact, so it tests the line path against corners that an independent renderer placed.

## Alternatives Considered

- **Change only the protocol: ask for a dark surface.** Rejected. These photographs already follow ADR 0017, because the table is darker than the paper. A protocol that the reader fails at its own wording is not a protocol the field can follow.
- **A printed fiducial marker.** Rejected for now. ADR 0017 names it as the fallback if a bare sheet cannot be read classically. This fix reads 24 of the 31 photographs, so that condition is not met.
- **A morphological opening to cut the leak.** Tried and rejected: 0 of 31. The bridge between the sheet and the lit spot is wider than any opening that leaves the sheet's corners intact.
- **Line fitting on every photograph.** Rejected. It would change the hull path that every synthetic scene proves, and gain nothing where the region does not touch the border.
- **Lowering the contrast floor of 60.** Rejected. That floor is what refuses a pale sheet on a pale surface (SPEC 0091). The second split adds a floor of its own and leaves the first one in place.

## Scope

- Includes:
  - `lib/core/services/descriptors/a4_sheet.dart`:
    - the bright-side split, with `_minPaperContrast`;
    - the line path for a region that touches the border;
    - the edge step check, with `_minEdgeStep`.
  - The `pale_table_lit` case in `ml/scripts/generate_sheet_fixtures.py`, its fixture, and its entry in `golden.json`. It is appended last, so every earlier fixture is unchanged.
  - `test/fixtures/sheet_photos/`: six reduced photographs and `expected.json`.
  - `test/services/a4_sheet_photos_test.dart`.
  - `test/services/a4_sheet_test.dart`, which adds `pale_table_lit` to the whole-sheet cases.
  - `docs/ml/sheet-reader-real-photographs.md`, the recorded check.
  - `.gitignore`, so a local `/images/` folder of originals is never committed.
  - The README, `docs/agents/project.md` and `docs/architecture/ml-implementation-map.md`. Each says the reader is graded on synthetic scenes only, and each will say what the check found.
- Does NOT include:
  - The smallest soil patch the grid accepts, or the patch grid in any way. On these photographs the largest disc inside the soil patch is 46 to 51 mm across. The grid's nine patches need a disc of about 58.5 mm, and the protocol asks for a patch 8 to 10 cm across, so a found sheet still ends in `soilRegionTooSmall`. That is a capture fault, recorded in the check document. It is not a reader fault.
  - The model, the contract, the capture screen, onboarding copy, and any user-facing text.
  - A dark container or a second sheet in the scene. Neither is in the protocol. The check records how the reader answers them.

## Acceptance Criteria

- `a_sheet_is_found_within_tolerance` holds for `pale_table_lit`, as well as every earlier whole-sheet case: each corner is within 0.5 % of the diagonal, and the scale is within 1 %. This fails on today's reader, which refuses the scene as `notFound`: its one split puts the paper and the table on the same side.
- `the_soil_disc_is_found_on_the_sheet` and `rectification_keeps_the_native_scale` hold for `pale_table_lit`.
- `a_real_sheet_is_found_where_it_lies`: on each committed photograph that holds a sheet, the four corners are found. Each found corner lies within 1 % of the photograph's long side of an annotated corner, and each annotated corner within 1 % of a found one. The scale from the found corners is within 1 % of the scale from the annotated ones. This fails on today's reader, which refuses every one of them.
- `a_real_photograph_without_a_true_edge_is_refused`: the lighting-gradient photograph is refused as `notFound`. The photograph whose sheet runs off the top and the bottom of the frame is refused as `cropped`.
- `the_verdict_survives_the_variants`: under each of the five variants, every found photograph is still found, with its corners and its scale held to the same tolerances against the transformed annotation. Every refused photograph is still refused with the same cause.
- Every earlier test in `test/services/a4_sheet_test.dart` passes unchanged, including `no_sheet_is_refused_as_not_found`, `a_pale_sheet_on_a_pale_surface_is_refused_as_not_found`, `a_cropped_sheet_is_refused_as_cropped` and `a_mirrored_photograph_reads_the_same_scale`.
- `the_sheet_fixtures_regenerate` and `the_golden_describes_its_own_expectations` pass in `ml/`.

## Reproducibility

```sh
cd ml && python scripts/generate_sheet_fixtures.py && python -m pytest tests/test_sheet_fixtures.py -q
flutter test test/services/a4_sheet_test.dart test/services/a4_sheet_photos_test.dart
flutter analyze && flutter test && mf check
```

Flutter 3.44.1, Dart 3.12.1, and Python 3.12 with `ml/requirements.txt`. The six photographs were reduced from the 2026-10-05 originals by Pillow's `ImageOps.exif_transpose`, a `LANCZOS` resize to a 1024 px long side, and a JPEG save at quality 90 with no EXIF. The check document lists the originals' names and sizes.

## Risks and Assumptions

- **Risk: a lighting gradient across a pale table is refused, not read.** That is the two photographs refused at the edge step. The refusal is the safe answer, because the alternative is a scale about 6 % wrong. The remedy is the protocol's diffuse light.
- **Risk: the floors of 20 and 10 are set from one session's photographs.** They sit in wide gaps: 20 against observed contrasts of 32 to 43 (28 under the darkening variant), and 10 against observed steps of 20 to 40 for real edges and 4 or 5 for the false one. A new surface may need them revisited, and the variants test is what would show it.
- **Risk: a sheet cut by the frame can be refused as `notFound` rather than `cropped`.** The line path keeps sixteen lines, so a weak one can stand in for the edge the frame cut. That edge then fails the step check, because paper lies on both sides of it. Either refusal stops the measurement, and only the advice on the capture screen differs. The cut sheets here, synthetic and real, are refused as `cropped`.
- **Risk: a bowed edge or a leak moves a corner.** The reader fits straight lines, and a real sheet's edges are not quite straight. On 160706 a corner is 0.87 % of the long side off, against a tolerance of 1 %. The scale holds to 0.3 %, and the homography's error at the soil patch, in the middle of the sheet, is smaller than at the corner. A sheet flattened on the surface, as the protocol asks, keeps this small.
- **Assumption: one session of photographs speaks for the field.** They are one phone, one table, and one afternoon. The check document says so, and more sessions are still owed before the Play release (ADR 0026).
- **Still owed:** classification end to end on a real photograph. Every sheet found here still ends in `soilRegionTooSmall`, because the soil patch is smaller than the grid needs. Photographs with a patch 8 to 10 cm across are needed.
- **What would invalidate this spec:** real photographs taken to the protocol, with diffuse light and a surface darker than the paper, that the reader still refuses at useful rates. ADR 0017's fiducial-marker fallback would then be due.
