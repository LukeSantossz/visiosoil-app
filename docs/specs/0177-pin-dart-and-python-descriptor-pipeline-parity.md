# SPEC: test(descriptors): pin Dart and Python descriptor-pipeline parity

## Problem

The released classifier reads nearly every 2026-10-19 field soil photograph as clay, but before a descriptor-model retrain can attribute that result to capture-domain shift, the application and the Python training and study paths must be shown to derive the same 26 descriptors from the same photograph.

## Design Decision

This change adds one committed, Python-generated cross-language golden for the part of the descriptor pipeline that both languages implement from a decodable photograph through the complete 26-feature vector. It uses the committed, location-free real sheet photograph `test/fixtures/sheet_photos/photo_160609.jpg`, a fixed documented measurement in its displayed frame, and the released contract geometry. Python decodes and applies EXIF orientation with Pillow, cuts the canonical patch grid, describes every patch, and records the mean of each feature across the patch rows. Dart decodes and bakes orientation with `package:image`, uses the same fixed measurement, cuts and describes the patches, and compares its per-patch and photograph vectors to the golden.

The golden pins every shared stage that was not already held across languages: JPEG decode and orientation, the composition of the patch grid and descriptors over a real decoded photograph, and mean aggregation of the 26 descriptor rows into a photograph vector. Its numeric comparison uses SPEC 0030's `1e-9` relative plus `1e-12` absolute tolerance. A different tolerance is not introduced: any decoder or resampling difference outside this tolerance is a finding, not noise to widen away. The Dart comparison helper rejects a NaN or infinite actual or expected value as a violation before the tolerance check runs: `atol + rtol * |expected|` compares false against a NaN operand in either direction, so without this guard a non-finite actual value would silently pass rather than fail.

The generator also emits the Pillow-decoded, EXIF-oriented RGB frame itself — `decoded_rgb_pre_resample`, the stage before any resample — as a second, lossless fixture, `pipeline_golden_decoded_frame.png`, and records its path and stage name in `pipeline_golden.json` under `decoded_frame_fixture`. This exists because the descriptor-stage comparison originally decoded the committed JPEG a second time in Dart, so the Pillow/`package:image` JPEG decoder divergence recorded under Risks contaminated a comparison that was meant to isolate the canonical-resample, patch-cut and descriptor stages. `descriptor_pipeline_golden_test.dart` now runs three tests against the one golden:

- **Decoder stage** (`dart_decoded_frame_matches_python_for_a_real_photograph`): decodes the committed JPEG in Dart and compares its decoded RGB statistics to Python's. Skipped with the named decoder-divergence reason.
- **End-to-end stage** (`dart_pipeline_matches_python_for_a_real_photograph`, JPEG decode included): decodes the committed JPEG in Dart, then runs the full canonical-resample through mean-descriptor path and compares to the golden. Skipped with the same reason, since it inherits the decoder-stage divergence.
- **Descriptor stage, decode-isolated** (`dart_pipeline_matches_python_for_a_real_photograph`): decodes `pipeline_golden_decoded_frame.png` — a lossless PNG, so the pixels Dart reads are bit-identical to the array Python described — and runs the same canonical-resample through mean-descriptor path from there. This test is active, not skipped: with the decode stage held identical by construction, every remaining stage (canonical resample, BT.601 greyscale, grid geometry, patch cut, the 26 descriptors, and their mean) agrees with Python within SPEC 0030's tolerance.

The PNG fixture is capped at 2 MiB; `generate_descriptor_pipeline_golden.py` raises rather than committing a larger one, naming the stage it would fall back to (the canonical-size frame) if a future fixture photograph's decoded frame does not fit. For `photo_160609.jpg` the decoded frame itself is about 211 KiB, so no fallback is needed today.

The following map records the boundary and the existing evidence:

| Stage | Dart path | Python path | Cross-language parity evidence after this change |
| --- | --- | --- | --- |
| Decode and EXIF orientation | `InferenceService.runInference` then `img.bakeOrientation` | `dataset._photograph_patches` then `ImageOps.exif_transpose` | `pipeline_golden.json`'s skipped decoder-stage and end-to-end-stage tests decode the committed real JPEG in both languages and find a divergence (see Risks); the active descriptor-stage test does not re-decode the JPEG in Dart, reading Python's decoded frame from `pipeline_golden_decoded_frame.png` instead, so this stage is a named gap rather than a shared one today. |
| A4-sheet detection, soil-disc location and perspective rectification | `a4SheetMeasurer` | No Python implementation | Not a shared stage. Dart has synthetic and real-sheet tests; Python studies consume the app's exported canonical region under SPEC 0174. |
| Canonical resample, BT.601 greyscale, grid geometry and patch cut | `canonicalPatches` | `resample_to_canonical`, `cut_patches` | Already exact in `patches/golden.json`, generated by `generate_patch_golden.py`; also exercised from the real JPEG by the new golden. |
| Patch pixels to 26 descriptors | `describePatch` | `describe_patch` | Already within the SPEC 0030 tolerance in `descriptors/golden.json`, generated by `generate_descriptor_golden.py`; also exercised on each real-photo patch by the new golden. |
| Patch-probability mean for the released classifier | `DescriptorContract.distribution` | `predict_proba(...).mean(axis=0)` | Already within tolerance in `contract/golden.json`, generated by `generate_contract_golden.py`. |
| Mean of 26 descriptor rows used by parity reporting | test-only aggregation | NumPy `mean(axis=0)` | `pipeline_golden.json` holds both languages to the same real-photo vector. |
| Field-study input boundary | `VISIOSOIL_EXPORT` creates canonical PNG regions | `field_features` reads the exported PNG then cuts and describes it | SPEC 0174 defines this hand-off. It is not independently reimplemented by Python, so the real-photo golden verifies the shared decoded-photograph path rather than fabricating a second sheet reader. |

## Alternatives Considered

- **Port the A4-sheet reader to Python for one end-to-end golden.** Rejected. Python intentionally has no second A4 reader; SPEC 0174 defines the Dart export as the boundary to avoid two implementations that could drift.
- **Use only synthetic raw RGB fixtures.** Rejected. Existing patch and descriptor goldens already do that well, but they leave image-codec and orientation behavior untested.
- **Compare classifier labels only.** Rejected. A top class could match while individual descriptor values diverge enough to bias a retrain or a study. The golden exposes every patch row and the 26-value photograph vector.

## Scope

- Includes:
  - A Python generator and Python regression test for a committed descriptor-pipeline golden.
  - A Python-emitted, lossless PNG of the Pillow-decoded, EXIF-oriented RGB frame, so a Dart comparison can start after decode.
  - Dart regression tests that read the same golden — one decode-isolated and active, two JPEG-decode-dependent and skipped — and compare per-patch and mean photograph descriptors.
  - The stage map above, including explicitly non-shared boundaries.
- Does NOT include:
  - Changes to `assets/models/spec.json`, descriptor mathematics, preprocessing behavior, classifier fitting, or any retraining.
  - A Python A4-sheet reader, field photographs with location data, or a new image-processing dependency.
  - Changing tolerances to hide a discovered divergence.

## Acceptance Criteria

- `python_pipeline_golden_reproduces_a_real_photograph`: Python reads the committed real JPEG, applies the documented measurement, and reproduces every committed patch vector and its 26-value mean within the SPEC 0030 tolerance.
- Descriptor stage, decode-isolated (`dart_pipeline_matches_python_for_a_real_photograph` reading `pipeline_golden_decoded_frame.png`): Dart decodes the lossless PNG — bit-identical to the array Python described — and every patch vector and the mean vector agree with the Python golden within `1e-9` relative plus `1e-12` absolute tolerance. This test is active; the test prints its largest measured differences unconditionally, pass or fail. Measured on `photo_160609.jpg`, the largest is `first_order.kurtosis` at patch 6, Δ≈`2.6e-11` (≈`8.6e-12` standard deviations), with the rest below `1.2e-11` — floating-point accumulation-order noise between Dart's and NumPy's arithmetic over bit-identical input, well inside tolerance. No tolerance was loosened to reach a pass.
- The end-to-end stage and the decoder stage (both reading and decoding the committed JPEG in Dart): skipped with a named reason — JPEG decoder divergence between Pillow and `package:image` — recorded rather than silently passing or widening the tolerance; see Risks.
- `pipeline_golden_generation_is_deterministic`: two Python generations produce byte-identical JSON and match the committed fixture; the committed PNG is regenerated identically because `decoded_frame()` has no random input.
- `the_stage_map_names_every_shared_stage_and_its_evidence`: this spec identifies existing coverage and each newly covered shared stage, while identifying the A4 reader as a one-language boundary.
- `a_real_photo_vector_has_twenty_six_features`: the committed end-to-end real-photo result has at least the contract minimum number of patches and exactly 26 descriptor values.
- The committed `pipeline_golden_decoded_frame.png` is under the generator's 2 MiB budget; `generate_descriptor_pipeline_golden.py` raises rather than silently committing a larger PNG.

## Reproducibility

```sh
cd ml && python scripts/generate_descriptor_pipeline_golden.py
cd ml && python -m pytest tests/test_descriptor_pipeline_golden.py -q
flutter test test/services/descriptor_pipeline_golden_test.dart
cd ml && python -m pytest tests/ -q
flutter test
mf check
```

Python 3.12 with the versions in `ml/requirements.txt`; Flutter 3.44.1 and Dart 3.12.1. The generator reads only committed fixtures and has no random input.

## Risks and Assumptions

- Assumption: `photo_160609.jpg` is retained as a reviewed, location-free fixture; it is already committed for SPEC 0140.
- Risk: Pillow and `package:image` can decode JPEG coefficients differently. The cross-language golden is intended to expose that result rather than conceal it. It did: the committed real JPEG decodes to different RGB statistics in the two libraries, outside the stated tolerance, and every stage downstream of decode (canonical resample, patch cut, descriptors, mean) diverges with it when both languages decode the JPEG themselves. `descriptor_pipeline_golden_test.dart` records this as a named, skipped test in both its decoder-stage and end-to-end-stage forms rather than widening the tolerance or deleting the comparison, and isolates decode by having Dart read Python's own decoded frame from `pipeline_golden_decoded_frame.png` for the active descriptor-stage test, which passes with its largest measured difference (`first_order.kurtosis`, Δ≈`2.6e-11`) two orders of magnitude inside tolerance — floating-point accumulation-order noise, not a decode difference. The open follow-up is narrower than before: find or fix the JPEG decoder divergence itself, not the comparison.
- Risk: Pillow version upgrades can themselves change this golden, independent of the Dart/Python decoder gap. Pillow's JPEG decode and its `BILINEAR` resample are implementation-defined at the coefficient level, so regenerating the golden after a Pillow bump in `ml/requirements.txt` can change `decoded_rgb_statistics`, `patches`, `mean_features`, and the committed PNG even though no descriptor logic changed. A regeneration after a Pillow upgrade should be reviewed as a potential golden change, not treated as a no-op refresh.
- Risk: the fixed measurement is a test seam, not a claim that Python can read the sheet. The map names that boundary so a passing test does not overclaim sheet-reader parity.
- Risk: a future fixture photograph's decoded frame could exceed the generator's 2 MiB budget. The generator raises rather than committing it; the documented fallback is to freeze a later, smaller lossless stage (e.g. the canonical-size frame) and record the new stage name in `decoded_frame_fixture`.
- What would invalidate this spec: a decoding, orientation, canonical-grid, per-patch descriptor, or mean-vector difference outside the stated tolerance with no unambiguous correct side.
