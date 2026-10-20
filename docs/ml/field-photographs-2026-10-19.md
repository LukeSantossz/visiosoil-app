# The classifier on labelled field photographs: 2026-10-19

On 2026-10-19 the Developer photographed the soils of the four trained classes to the capture protocol (SPEC 0164), on an A4 sheet, with a POCO X7 Pro. This document records what the released classifier (contract `1.0.0`, fitted on `v1`) reads on them, and what was tried to make it read them right. It is the baseline any refit is measured against (SPEC 0175).

## The answer

**Every photograph the app classified was right: 5 of 5. The other 49 were refused, 47 of them because the photograph was coarser than the contract's scale.** That refusal was caused by the guided camera's outline, and SPEC 0171 fixes it.

**Once the coarse photographs are upsampled, the classifier reads every soil as clay.** It reads the Media and Arenosa soils as Muito Argilosa: 0 of 24 right. No preprocessing in the app changed that. The descriptors of every field photograph are shifted from the archive's in the same direction, whatever the soil. That is a shift in how the photographs were taken, not in what was photographed.

## The photographs

54 photographs in five bursts, one soil sample each, with the phone's own camera. Their labels are the Developer's, given after the session:

| Burst | Class | Sample | Photographs | Size (px) |
|---|---|---|---|---|
| 15:01 | Argilosa | S1 | 11 | 1836 × 4080 |
| 15:06 | Muito Argilosa | S2 | 11 | 4080 × 1836 |
| 15:10 | Media | S3 | 13 | 4080 × 1836 |
| 15:13 | Arenosa | S4 | 11 | 1836 × 4080 |
| 16:59 to 17:00 | Argilosa | S5 | 8 | 1836 × 4080 and 6144 × 8192 |

The first four bursts lie on a dark chair seat, and the fifth on a pale table. The originals stay out of git, because they carry their location. The labelled copy the runner reads is laid out as `<class>/<sample>/`.

## What the app reads

From `VISIOSOIL_PHOTOS=<labelled copy> flutter test test/field_session/field_session_test.dart` on `main` with SPEC 0174:

| Class | Right | Classified | Refused |
|---|---|---|---|
| Arenosa | 0 | 0 | 11 |
| Media | 0 | 0 | 13 |
| Muito Argilosa | 1 | 1 | 10 |
| Argilosa | 4 | 4 | 15 |

Refusals: `photographTooCoarse` 47, `sheetNotFound` 1, `soilRegionTooSmall` 1.

The sheet was found on 52 of the 54 photographs, and the soil discs measured 79 to 88 mm. The small discs of 2026-10-05 are gone. The 47 coarse photographs read at 0.130 to 0.145 mm/px, against the contract's 0.1292.

## What was tried

Each study ran the app's descriptor path in Dart, over the same photographs, in a throwaway test.

**Upsampling the coarse photographs to the canonical scale** does not change the classification, but the classification is wrong. The five photographs that classify were reduced to 0.135, 0.14, 0.145, 0.15, 0.16 and 0.18 mm/px and upsampled back. Their top class never changed, and no probability moved by more than 3 points. With every photograph upsampled, 11 of 50 were read right:

| Class | Right, upsampled |
|---|---|
| Argilosa (S1) | 0 of 11 |
| Muito Argilosa (S2) | 7 of 11 |
| Media (S3) | 0 of 13 |
| Arenosa (S4) | 0 of 11 |
| Argilosa (S5) | 4 of 4 |

**A Gaussian blur before the descriptors**, at sigma 0.5 to 1.6 px, was tried to undo the phone's sharpening. It moves the reads between Argilosa and Muito Argilosa and never reaches Media or Arenosa. The best setting gives 15 of 50, with S1 and S2 never right together:

| Sigma | Right | S1 | S2 | S3 | S4 | S5 |
|---|---|---|---|---|---|---|
| 0 | 11 | 0 | 7 | 0 | 0 | 4 |
| 0.5 | 11 | 0 | 7 | 0 | 0 | 4 |
| 0.8 | 15 | 0 | 11 | 0 | 0 | 4 |
| 1.0 | 14 | 0 | 10 | 0 | 0 | 4 |
| 1.3 | 7 | 3 | 0 | 0 | 0 | 4 |
| 1.6 | 15 | 11 | 0 | 0 | 0 | 4 |

**Re-centring the descriptors** subtracted the field photographs' mean, each burst weighted equally, and added back the standardiser's mean. It gave low-confidence reads that did not separate the bursts.

## Why

Over every field photograph, the 26 descriptors stand away from the training mean in the same direction, whatever the class. The figures are in standard deviations of the standardiser:

- spectral bands 4 and 5: +1.2 to +3.5;
- LBP uniform codes 3 and 4: +1.8 to +2.5;
- LBP codes 0, 1, 7, 8 and non-uniform: -1.3 to -2.0.

The archive was photographed in a Petri dish on a fixed rig. These photographs are of crumbled, sieved soil, spread on paper and taken with a phone that sharpens and denoises. The classifier's texture descriptors read that difference as clay.

## What this does not show

- **Five soils are not a population.** S1 and S5 are both Argilosa, and every other class is one sample. A refit that reads these right is not shown to read other soils right. SPEC 0175 measures one held-out soil at a time for that reason.
- **The labels are the Developer's account of the bursts**, given after the session, not a laboratory analysis of these samples.
- **The phone's camera is not the app's.** These photographs come from the vendor camera app. The in-app camera's photographs of the same day (3072 × 4096) were all refused as too coarse, for the reason SPEC 0171 fixes.

## Reproducing it

```sh
VISIOSOIL_PHOTOS=<labelled copy> VISIOSOIL_EXPORT=<dir> flutter test test/field_session/field_session_test.dart
```

The export writes each measured photograph's region at the canonical scale, with a `manifest.json`, for the Python study of SPEC 0175. The upsampling, blur and re-centring studies were throwaway tests and are not committed. Their numbers are those above.
