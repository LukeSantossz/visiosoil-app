# SPEC: feat(inference): wire the descriptor path into the inference service

## Problem

`InferenceService` still runs the TFLite path. It reads a
`soil_classifier.tflite` that no longer exists for v1 (ADR 0024), labels its
output from a hardcoded `SoilTextureLabels`, and fails every classification
with `modelMissing`. Meanwhile the descriptor path's parts sit unused: the
released contract (`assets/models/spec.json`, SPEC 0082), its reader (SPEC
0079), the patch grid (SPEC 0081) and the descriptors (SPEC 0077). This is the
first half of the wiring in the implementation map, and it closes #79.

## Design Decision

**`classify` runs the descriptor path end to end, behind one seam for what
nothing measures yet.**

`initialize` loads `assets/models/spec.json` as text and parses it with
`parseDescriptorContract`. An absent asset is `contractMissing`, and the
parser's refusals are `contractMalformed` and `contractUnsupported`. A parse
refusal is a build fact, so it is not retried. An asset load that fails is
retried, as the model load was.

Inside the isolate, `runInference` runs these steps in order:

1. **Decode** the file, then bake its EXIF orientation (`img.bakeOrientation`),
   as `ImageOps.exif_transpose` does before anything else in Python.
2. **Convert** the image to an `RgbFrame`.
3. **Measure** the frame with the injected measurer, which returns a
   measurement or a cause.
4. **Cut** with `canonicalPatches`, using the measurement and the contract's
   geometry.
5. **Describe** each patch with `describePatch`.
6. **Score** with `DescriptorContract.distribution`.
7. **Label** the result with `DescriptorContract.classes`.

**The seam is a measurer.** It is a top-level function the service takes, so
that it can be sent to the isolate:

```dart
({PhotographMeasurement? measurement, ClassificationFailureCause? cause})
    Function(RgbFrame frame)
```

A `PhotographMeasurement` is the four numbers the dataset manifest carries per
photograph (millimetres per pixel, and the soil region's centre and diameter),
plus the frame they are measured in. The frame is returned rather than assumed
because the A4-sheet reader will rectify it (ADR 0017), and the grid must cut
from the frame the measurement describes.

**This build has no measurer, and it says so.** The only one that exists
returns the new cause `measurementUnavailable`, in the "build is wrong" column.
The app therefore still classifies nothing, as it does today, but it reports
the true reason instead of a missing model. It never guesses a scale: ADR 0017
forbids that. The A4-sheet reader replaces this measurer and retires the cause.
The tests drive the whole path with a fake measurer.

**The labels come from the contract, and `SoilTextureLabels` is deleted.** The
class list lives in one place, the released contract. `buildDistribution`
takes the contract's classes: ties still break on their order, and a value that
is not a probability is still `outputInvalid`. Three things follow:

- `SoilTextureColors.all` goes with the labels, because it only re-read their
  order and no production code calls it.
- `SoilTextureColors`' keys stay: SPEC 0035's narrowing permits exactly that
  file.
- A sweep test holds the rule that no other file under `lib/` names a texture
  class.

`test/standards/class_list_test.dart` now asserts that the shipped contract's
classes are `ml/config.yaml`'s. SPEC 0048's two lists become one list and one
config.

**The TFLite path leaves.** These go:

- the interpreter code, `checkTensors`, `outputRow`, `_imageToInputTensor` and
  the model asset;
- the `tflite_flutter` dependency and its R8 keep rule.

**ADR 0015's table is amended in place, under a dated "Amended" heading**, as
ADR 0008 and 0009 were. The causes that only the TFLite path could produce
leave: `modelMissing`, `modelEmpty` and `modelContractMismatch`.
`interpreterError` becomes `computationError`, since the descriptor path can
still throw and there is no interpreter. Four causes arrive:

- `measurementUnavailable`, with the build;
- `photographTooCoarse`, `soilRegionTooSmall` and `soilRegionOutsideFrame`,
  with retrying, because the remedy is to retake the photograph. These are
  SPEC 0081's three refusals, which ADR 0017 places in that column.

That makes thirteen causes. The test that reads the table reads the one under
the latest "Amended" heading.

| Nothing to do — the build is wrong | Retry, or retake the photograph | Re-release the contract |
| --- | --- | --- |
| `contractMissing` | `timeout` | `contractUnsupported` |
| `contractMalformed` | `computationError` | `outputInvalid` |
| `measurementUnavailable` | `isolateFailure` | |
| | `imageMissing` | |
| | `imageUndecodable` | |
| | `photographTooCoarse` | |
| | `soilRegionTooSmall` | |
| | `soilRegionOutsideFrame` | |

`outputInvalid` keeps its meaning. It is what `distribution` throwing on a
non-finite logit becomes, and what a value that is not a probability becomes.

## Alternatives Considered

- **Keep the TFLite path until the sheet reader lands.** Rejected by the
  Developer on 2026-09-29. v1 has no `.tflite`, so the user gains nothing, and
  the labels would stay hardcoded against a contract that already declares
  them.
- **Return a default scale when nothing measures.** Rejected. ADR 0017 refuses a
  guessed scale because the classification would then be confidently wrong.
- **Keep the TFLite causes as dead members and only add the new ones.** Rejected
  by the Developer on 2026-09-29. It would leave causes that no code produces,
  in a type the UI switches over.
- **Add the dispersion metric here, or delete `export.py` and the CNN training
  path.** Deferred by the Developer on 2026-09-29, to later work. The metric has
  no consumer until the UI/UX terminal's quality surface exists, and the Python
  cleanup is a different language and a different review.
- **Parse the contract inside the isolate on every classification.** Rejected.
  The parsed contract is plain lists and strings, so the one parsed at
  `initialize` is copied into the isolate as it is. A parse refusal is then
  reported before any isolate is spawned.

## Scope

- Includes:
  - `lib/core/services/inference_service.dart`, rewritten around the steps
    above.
  - `lib/core/services/classification_report.dart`, with the amended causes.
  - `lib/core/services/descriptors/photograph_measurement.dart`:
    `PhotographMeasurement`, the measurer type, and `measurementUnavailable`,
    the measurer this build ships with.
  - `lib/core/features/capture/capture_screen.dart`: its fallback for a throw
    becomes `computationError`.
  - `lib/models/soil_texture_labels.dart` deleted, `SoilTextureColors.all`
    removed, and `ClassScore`'s documentation updated.
  - `pubspec.yaml` and `pubspec.lock` lose `tflite_flutter`, and
    `android/app/proguard-rules.pro` loses its TFLite keep rule.
  - The tests:
    - the inference tests, rewritten;
    - `class_list_test.dart`, now reading the contract;
    - `soil_texture_labels_test.dart`, deleted;
    - `classification_verdict_test.dart` and the capture-screen test, where
      they named a removed label source or cause;
    - a new sweep test for texture-class literals under `lib/`.
  - ADR 0015's amendment.
  - The README and `docs/agents/project.md` statements that describe TFLite in
    the app, with `CLAUDE.md` regenerated. The map's wiring entry.
- Does NOT include:
  - The A4-sheet reader, the homography, or locating the soil on paper. That
    is its own spec, which replaces `measurementUnavailable`.
  - The dispersion metric and its quality criterion.
  - Any change under `ml/`: `export.py`, the CNN training path and the
    `models/` layout stay.
  - Any screen that shows a cause, or a cause-specific retry. That is the UI/UX
    terminal's roadmap item 2.
  - Calibration, and the verdict bands read from the contract (C2, #243).
  - The patch grid, the descriptors or the contract reader themselves.

## Acceptance Criteria

Dart:

- `missing_contract_asset_yields_contract_missing`
- `malformed_contract_yields_contract_malformed` and
  `unsupported_contract_yields_contract_unsupported`, both from `initialize`,
  and neither retried.
- `the_shipped_contract_loads`: `assets/models/spec.json` initialises the
  service with no cause.
- `no_measurer_yields_measurement_unavailable`: a decodable photograph with the
  measurer this build ships reports `measurementUnavailable`.
- `a_measured_photograph_is_classified_with_the_contract`: with a fake
  measurer, the report is `ok`. Its distribution equals what
  `canonicalPatches`, `describePatch` and `DescriptorContract.distribution`
  give for the same frame, labelled with the contract's classes, highest first.
- `patch_refusals_yield_their_causes`: a measurement coarser than the canonical,
  a region too small, and a region outside the frame report
  `photographTooCoarse`, `soilRegionTooSmall` and `soilRegionOutsideFrame`.
- `orientation_is_baked_before_measuring`: the measurer receives the frame in
  its displayed orientation.
- `missing_image_file_yields_image_missing` and
  `undecodable_image_yields_image_undecodable`, kept.
- `inference_timeout_yields_timeout`, `isolate_spawn_failure_yields_isolate_failure`
  and `isolate_death_yields_isolate_failure`, kept, along with the kill on
  timeout.
- `a_throw_in_the_pipeline_yields_computation_error`
- `non_probability_output_yields_output_invalid`, kept for `buildDistribution`.
- `failure_causes_follow_adr_0015`: the enum equals the table under ADR 0015's
  latest "Amended" heading, thirteen causes.
- `no_texture_class_literal_in_lib`: only `soil_texture_colors.dart` names a
  texture class under `lib/`.
- `the_shipped_contract_classes_are_the_configured_classes`: in
  `class_list_test.dart`.

## Reproducibility

```sh
flutter pub get
flutter analyze && flutter test
flutter build apk --release
mf check
```

Flutter 3.44.1 and Dart 3.12.1. There is no Python step.

## Risks and Assumptions

- **Risk: cost on a device.** The isolate now decodes a full-resolution
  photograph, resamples it and describes up to 25 patches. On a desktop JIT a
  patch takes about 40 ms, and nothing has been measured on a phone. The 15 s
  timeout stays, and A7 measures the cost.
- **Risk: the JPEG decoders differ** (SPEC 0081). The photograph Dart decodes
  can differ slightly from the one Pillow would decode. It is unmeasured.
- **Assumption: a parsed contract crosses into the isolate by copy.** It holds
  only lists, strings and numbers, which `Isolate.spawn` copies.
- **What would invalidate this spec:** the sheet reader needing to return
  something other than a frame and four numbers, such as a mask instead of a
  disc. The measurement type would then widen, and the seam would stay.
