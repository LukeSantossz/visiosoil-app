# The A4-sheet reader on real photographs: the check

[SPEC 0091](../specs/0091-find-the-a4-sheet-and-rectify-it-at-native-resolution.md) built the A4-sheet
reader against synthetic scenes, and recorded that it owed a check against real
photographs. [ADR 0026](../adr/0026-the-first-play-release-waits-for-classification.md)
puts that check on the critical path to the Play release. This document records
the first one: 31 photographs from one session, the reader's verdict on each
before and after [SPEC 0140](../specs/0140-find-the-a4-sheet-on-a-pale-table.md),
and what the session could not show.

## The answer

**The reader now finds the sheet on 24 of the 31 photographs, and refuses the
other 7 by the right name. Before SPEC 0140 it found none.** No photograph is
classified yet: every sheet found ends in `soilRegionTooSmall`, because the soil
patch on these photographs is smaller than the patch grid needs.

| | Before (`main` at `0c33c2f`) | After (SPEC 0140) |
|---|---|---|
| Sheet found | **0** | **24** |
| Refused as `cropped` | 16 | 1 |
| Refused as `notFound` | 15 | 6 |
| Classified | 0 | 0 |

Every refusal after the fix is correct. Four photographs hold no sheet, two
hold a sheet whose one edge cannot be told from a lighting gradient, and one
holds a sheet that runs off the frame. Before the fix, all 26 photographs with
a whole sheet in view were refused.

## The session

All 31 photographs were taken on 2026-10-05, between 16:06 and 16:09, with one
phone, on one table, under the room's light. They are `IMG_20261005_160609.jpg`
to `IMG_20261005_160908_1.jpg`.

| Size (px) | Photographs |
|---|---|
| 4080 × 1836 | 20 |
| 1836 × 4080 | 5 |
| 3200 × 1440 | 2 |
| 8192 × 6144 | 2 |
| 6144 × 8192 | 2 |

Each original is 1.3 to 6.3 MB, 67 MB in all, and its EXIF carries the place it
was taken. The originals stay out of git. `.gitignore` ignores a local
`/images/` folder, which is where the check read them from.

### How the scenes depart from ADR 0017's protocol

- **The table is pale.** It is darker than the paper, as the protocol asks, but
  only by 32 to 43 grey levels. That is under the reader's contrast floor of 60,
  and it is the first of the two faults SPEC 0140 fixes.
- **The light is not diffuse.** A lit spot on the table touches a corner of the
  sheet on many of the photographs, which is the second fault. On 160808 and
  160808_1 a lighting gradient across the table runs along one edge of the
  sheet.
- **The soil patch is small.** It is a heap, or from 160756 to 160808_1 a dark
  round container, and the largest disc inside it is 46 to 51 mm across. The
  protocol asks for soil spread 8 to 10 cm across.
- **Some scenes are not the protocol's at all.** 160611, 160802, 160803 and
  160803_1 show the soil on the bare table with no sheet in the frame. 160812
  holds a sheet that runs off the top and the bottom of the frame. 160903 holds
  a second sheet beside the first.
- **The paper is not flat.** On 160706 the bottom edge bows by about 2.5 px at a
  1024 px long side.

## Per photograph

The "after" column is the cause `InferenceService` reports with `a4SheetMeasurer`,
the path the app runs. Where the sheet is found, the scale is what
`rectifySheet` read and the disc is the largest one `locateSoilDisc` found
inside the soil patch.

| Photograph | Size | Before | After | Scale (mm/px) | Disc (mm) |
|---|---|---|---|---|---|
| 160609 | 4080 × 1836 | `cropped` | found → `soilRegionTooSmall` | 0.1252 | 50.6 |
| 160611 | 4080 × 1836 | `notFound` | `notFound`: no sheet in the frame | | |
| 160620 | 4080 × 1836 | `cropped` | found → `soilRegionTooSmall` | 0.1247 | 50.9 |
| 160620_1 | 4080 × 1836 | `cropped` | found → `soilRegionTooSmall` | 0.1240 | 50.4 |
| 160622 | 4080 × 1836 | `cropped` | found → `soilRegionTooSmall` | 0.1238 | 50.9 |
| 160622_1 | 4080 × 1836 | `cropped` | found → `soilRegionTooSmall` | 0.1240 | 50.7 |
| 160633 | 4080 × 1836 | `cropped` | found → `soilRegionTooSmall` | 0.1231 | 50.7 |
| 160634 | 4080 × 1836 | `cropped` | found → `soilRegionTooSmall` | 0.1233 | 51.0 |
| 160642 | 4080 × 1836 | `notFound` | found → `soilRegionTooSmall` | 0.1226 | 49.9 |
| 160645 | 4080 × 1836 | `notFound` | found → `soilRegionTooSmall` | 0.1237 | 50.5 |
| 160647 | 4080 × 1836 | `notFound` | found → `soilRegionTooSmall` | 0.1235 | 49.6 |
| 160654 | 4080 × 1836 | `notFound` | found → `soilRegionTooSmall` | 0.1217 | 50.2 |
| 160655 | 4080 × 1836 | `notFound` | found → `soilRegionTooSmall` | 0.1215 | 50.1 |
| 160656 | 4080 × 1836 | `notFound` | found → `soilRegionTooSmall` | 0.1219 | 50.4 |
| 160656_1 | 4080 × 1836 | `notFound` | found → `soilRegionTooSmall` | 0.1224 | 50.1 |
| 160700 | 4080 × 1836 | `cropped` | found → `soilRegionTooSmall` | 0.1235 | 51.2 |
| 160706 | 8192 × 6144 | `notFound` | found → `soilRegionTooSmall` | 0.0424 | 51.4 |
| 160756 | 8192 × 6144 | `notFound` | found → `soilRegionTooSmall` | 0.0408 | 46.5 |
| 160802 | 4080 × 1836 | `notFound` | `notFound`: no sheet in the frame | | |
| 160803 | 4080 × 1836 | `notFound` | `notFound`: no sheet in the frame | | |
| 160803_1 | 4080 × 1836 | `notFound` | `notFound`: no sheet in the frame | | |
| 160808 | 3200 × 1440 | `cropped` | `notFound`: an edge with no step | | |
| 160808_1 | 3200 × 1440 | `cropped` | `notFound`: an edge with no step | | |
| 160812 | 4080 × 1836 | `cropped` | `cropped`: the sheet runs off the frame | | |
| 160900 | 1836 × 4080 | `cropped` | found → `soilRegionTooSmall` | 0.1240 | 47.6 |
| 160900_1 | 1836 × 4080 | `cropped` | found → `soilRegionTooSmall` | 0.1239 | 47.5 |
| 160900_2 | 1836 × 4080 | `cropped` | found → `soilRegionTooSmall` | 0.1241 | 47.5 |
| 160901 | 1836 × 4080 | `cropped` | found → `soilRegionTooSmall` | 0.1242 | 47.4 |
| 160903 | 1836 × 4080 | `cropped` | found → `soilRegionTooSmall` | 0.1251 | 47.8 |
| 160908 | 6144 × 8192 | `notFound` | found → `soilRegionTooSmall` | 0.0424 | 47.2 |
| 160908_1 | 6144 × 8192 | `notFound` | found → `soilRegionTooSmall` | 0.0425 | 47.5 |

Each of the 24 found sheets was rectified and inspected: the whole sheet is in
the rectified frame, no table shows along its rim, and the disc sits on the
soil.

## Why every found sheet stops at `soilRegionTooSmall`

The patch grid needs at least nine patches of 160 px at the canonical
0.1292 mm/px. A 3 × 3 grid at half-patch stride fits inside a disc only when
the disc is about 58.5 mm across. The largest disc on these photographs is
51.4 mm. This is a capture fault, not a reader fault, and SPEC 0140 does not
touch the grid. Classification end to end on a real photograph is still owed,
and it needs soil spread 8 to 10 cm across, as the protocol already asks.

## The six photographs the tests read

Six photographs are committed under `test/fixtures/sheet_photos/`, so that CI
reruns part of this check on every change:

| Photograph | Expected | Why it was chosen |
|---|---|---|
| 160609 | sheet | Landscape; a lit spot joins the sheet to the frame's border |
| 160645 | sheet | Landscape; the table merges with the paper at one threshold |
| 160706 | sheet | 50 megapixels; a bowed edge (see below) |
| 160808 | `notFound` | An edge along a lighting gradient |
| 160812 | `cropped` | The sheet runs off the top and the bottom |
| 160903 | sheet | Portrait; a second sheet in the scene |

Each was reduced by Pillow's `ImageOps.exif_transpose`, a `LANCZOS` resize to a
1024 px long side, and a JPEG save at quality 90 with no EXIF, so none carries
the place it was taken. The six weigh 260 KB together.

The corners in `expected.json` were measured on the full-resolution original,
as the strongest grey step across each edge 8 px in from the corner, and mapped
to the reduced photograph. They agree with a reading by eye to within 1.5 px.
The tests hold each found corner, and each annotated one, to 1 % of the long
side, and the scale to 1 %.

**The bowed edge on 160706.** The paper's bottom edge bows by about 2.5 px,
and the lit table leaks along its left part. The straight line the reader fits
meets the next edge 0.87 % of the long side from the measured corner, inside
the 1 % tolerance but close to it. The scale it reads is within 0.3 %.

### The variants

Each of the six also runs under five deterministic variants, with the
annotated corners moved by the same transform. The variants run in the test
only; the dataset and training are untouched.

| Variant | Found sheets | 160808 | 160812 |
|---|---|---|---|
| Quarter turn | found, within tolerance | `notFound` | `cropped` |
| Mirror image | found, within tolerance | `notFound` | `cropped` |
| Darkening to 85 % | found, within tolerance | `notFound` | `cropped` |
| Seeded noise of ±8 grey levels | found, within tolerance | `notFound` | `cropped` |
| Reduction to 75 % | found, within tolerance | `notFound` | `cropped` |

The margins the two new floors keep, on the six photographs and their
variants:

| | Observed | Floor |
|---|---|---|
| Paper against a pale table (second split) | 32 to 43; 28 under the darkening | 20 |
| A real paper edge's step | 25 to 40; 20 or more under the variants | 10 |
| The false edge's step on 160808 | 4 or 5 | 10 |

## What this check does not show

- **That the reader holds in the field.** This is one phone, one table, one
  room and one afternoon. ADR 0026 still owes sessions on other surfaces, in
  other light and with other phones, and the two floors may need revisiting on
  a surface unlike this one.
- **That a photograph classifies.** None did. See above.
- **That a lighting gradient is read.** It is refused, which is the safe
  answer: on 160808 the false edge would have given a scale about 6 % wrong.
  The remedy is the protocol's diffuse light.

## Reproducing it

The six committed photographs are rerun by
`flutter test test/services/a4_sheet_photos_test.dart`. The full table above was
produced by a throwaway test, not committed, that ran each original in
`/images/` through `InferenceService.runInference` with `a4SheetMeasurer`, on
Flutter 3.44.1 and Dart 3.12.1. The "before" column is the same run on `main` at
`0c33c2f`.
