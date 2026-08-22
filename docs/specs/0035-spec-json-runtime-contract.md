# SPEC (full): refactor(inference): read the model contract from spec.json instead of hardcoding it

## Problem

`InferenceService` hardcodes the label list, the input size and the
normalization that `ml/src/export.py` already publishes in `spec.json` and that
`deploy_to_app.sh` already copies into the application, so a pipeline change and
a Dart change must be made by hand in step or the app classifies against a
contract the shipped model does not implement.

## Design Decisions

The contract ships inside the artifact and is read when the model is loaded.
`spec.json` becomes the single runtime source for the label list and its order,
the input size, the normalization method and the preprocessing geometry, and
`InferenceService` holds none of them as source constants. Because a contract
that can be absent must not degrade into the values it replaced, `classify`
stops returning `null` and returns a report that names what happened — which is
also what separates the six causes `null` collapsed. The centred-square region
of interest the contract declares is applied in `inference_service.dart` and in
`ml/src/preprocess.py` in this same change, because applying it on one side only
is the skew this spec exists to remove.

### The schema, defined here and emitted by B3

The schema below is the contract. It is defined in this spec and consumed by
work item B3, which makes `ml/src/export.py` emit it; it is not defined twice.
It is the file `_build_spec` (`ml/src/export.py:118`) already produces plus
three additions, deliberately, so that B3 is a small change rather than a
rewrite of a producer nobody has exercised end to end.

```json
{
  "spec_version": 1,
  "version": "v3",
  "dataset_version": "v1",
  "input": {
    "shape": [1, 224, 224, 3],
    "dtype": "float32",
    "normalization": { "method": "divide_255" },
    "preprocessing": { "roi": "centered_square", "exif_orientation": "baked" }
  },
  "output": { "shape": [1, 5], "dtype": "float32", "type": "probabilities" },
  "classes": ["Arenosa", "Media", "Siltosa", "Muito Argilosa", "Argilosa"],
  "bands": {}
}
```

The three additions, and why each is not optional:

- **`spec_version`** guards the reader against a file written to a different
  schema. The artifact ships inside the APK, so version skew between app and
  model is not the ordinary case; a `spec.json` copied in by hand from an older
  export is, and `deploy_to_app.sh` is exactly the tool that makes that easy.
  Without this field an older file is read successfully and wrongly.
- **`dataset_version`** exists because SPEC 0033 now produces one and ADR 0012
  requires the release record to name it. Carrying it in the contract rather
  than only in a commit message is what lets a diagnostic report which data a
  running model came from.
- **`input.preprocessing`** turns two tacit conventions into declared ones. The
  centred-square ROI and the baked EXIF orientation are today agreements between
  files that never reference each other; a contract that omits them cannot
  detect a producer that stops honouring them.

**`bands` is declared and not read by this spec.** It is the per-class band
block that work item C2 calibrates after temperature scaling, and nothing
consumes band constants today: `ClassificationVerdict` carries global
provisional thresholds and has no production caller. Parsing a field nothing
reads would be dead code, and omitting it from the schema would mean defining
the schema twice. Declaring it here and leaving it unread is the third option,
and the acceptance criteria make it safe by requiring an unknown key to be
ignored rather than rejected, so the block can arrive without an application
change.

### Why the failure taxonomy arrives with the contract

This decision was promoted at the Gate into
[`docs/adr/0015-classification-reports-a-named-failure-cause.md`](../adr/0015-classification-reports-a-named-failure-cause.md),
which is the curated record of it; what follows is why it belongs in this spec's
scope rather than a later one.

`classify` returns `Future<InferenceResult?>` today and reaches `return null`
from eight places. ADR 0011 (`:92-106`) accepted shipping `notAnalysed` derived
from that `null` and priced the acceptance precisely: **no result surface may
offer retry on `notAnalysed` until A4 lands**. This spec is A4, so the
separation lands here rather than being deferred again.

It also cannot be deferred on its own terms. Reading a contract introduces three
new ways to fail — absent, malformed, incompatible — and the acceptance criterion
this spec inherits forbids any of them degrading into a hardcoded default. A
failure that must be distinguishable cannot be reported through a value whose
entire defect is that it distinguishes nothing.

The causes are grouped by what the reader can do about them, which is the only
grouping that earns their number:

| Nothing to do — the build is wrong | Retrying is the right response | Re-export the model |
| --- | --- | --- |
| `contractMissing` | `timeout` | `contractUnsupported` |
| `contractMalformed` | `interpreterError` | `outputMismatch` |
| `modelMissing` | `isolateFailure` | `outputInvalid` |
| `modelEmpty` | `imageMissing` | |
| | `imageUndecodable` | |

Twelve rather than the six the implementation map names, because this spec adds
the three contract causes and because `modelMissing` and `modelEmpty` are
already distinct facts in the code — `initialize` sets `_modelUnavailable` for an
empty asset and not for an absent one (`inference_service.dart:124-128`) — that
collapse into one value on the way out.

The shape follows the one SPEC 0030 established for
`ImageQualityVerdict`/`ImageQualityReport`: an enum verdict with a nullable
payload, not a sealed class hierarchy. The precedence rule in
`code_conventions.md` puts an established project pattern above a framework
default, and two report types with two different shapes in one service layer is
the cost of ignoring it.

`ClassificationOutcome.rejectedOod` is declared and never produced. It is the
reserved not-soil signal the implementation map records; whether it comes from a
trained negative class or from the quality gate plus a threshold is open, and
declaring the member without a producer is what keeps that decision from being
foreclosed by an enum that has to be widened later.

### Why the labels leave the source tree entirely

`SoilTextureLabels` is deleted rather than kept as a fallback. Its own doc
comment anticipates becoming "the fallback rather than the source", and that is
the one outcome the criterion forbids: a silent fallback to hardcoded defaults
is how a train/serve skew survives review, because every screen keeps rendering
plausible class names while the model disagrees.

The label copies that remain after this change are the keys of
`SoilTextureColors._colorMap`, and they stay by decision. **The criterion "zero
string literals naming a texture class remain in `lib/`" is narrowed here to the
values the model decides** — the labels used to name a classification, the input
size, and the normalization — and does not extend to design tokens. A colour is
not model output: it encodes what sandy or clayey soil looks like, `forClass`
already degrades to `AppColors.outline` for a label it does not know, and a
wrong colour is cosmetic where a wrong label is a wrong result. Recording the
narrowing follows SPEC 0030, which corrected three of its own map criteria in
the specification rather than in silence.

Two alternatives that would satisfy the criterion literally were weighed and are
recorded under Alternatives Considered; both cost more than the property is
worth.

`SoilTextureColors.all` is removed with the constant it orders itself by. It has
no caller in `lib/` or `test/`, and its ordering source is exactly what this
change deletes.

### What the ROI parity proves, and what it does not

The order becomes identical on both sides: upright image, largest centred
square, resize, the normalization the contract names.

Dart today calls `img.copyResize(width: 224, height: 224)`
(`inference_service.dart:218`), which squashes the aspect ratio, and never bakes
EXIF orientation — although ADR 0005 keeps the orientation tag specifically
because "both display and inference apply it". Both are corrected.
`ml/src/preprocess.py:32` resizes without a crop and gains the same one. Neither
side reimplements the geometry: `roiBounds` (`image_quality_analyzer.dart:34`)
and `roi_bounds` (`ml/src/image_quality.py:121`) already exist and are reused,
which is SPEC 0030's own criterion that the ROI is defined once per language and
reused.

**Pixel-exact parity is not claimed and is not tested.** `img.copyResize` with
linear interpolation and `tf.image.resize` with bilinear interpolation do not
agree to `1e-9`, and making them agree would mean hand-writing a shared resize
in both languages the way SPEC 0030 hand-wrote `box_downscale`. What the
criteria verify is the geometry and the order — same crop, same target, same
sequence, same normalization — and the residual interpolation difference is
recorded as a known bounded divergence, to be measured on the trained model in
Lane C rather than asserted here. A criterion that promised exactness and
delivered a tolerance would be worse than one that says what it checks.

A second divergence is recorded rather than closed: `tf.io.decode_image`
(`ml/src/dataset.py:311`) discards EXIF by construction, so the Python path
never bakes orientation, while admission measures quality through
`exif_transpose` (`ml/src/image_quality.py:161`). For rig-captured dataset
images the baking is a no-op and the two paths agree on their own inputs;
proving that belongs to the dataset side, and it is named in Risks and
Assumptions with where it is closed.

## Alternatives Considered

- **Keep `SoilTextureLabels` as a fallback when the contract is absent.**
  Rejected. It is a silent fallback to hardcoded defaults, which the acceptance
  criterion inherited from the implementation map forbids by name, and the
  reasoning is ADR 0012's: replacing six hardcoded copies with one unread file
  relocates the problem instead of fixing it. A fallback makes the app look
  functional against a model it cannot describe.
- **Add a stable machine `key` per class to the schema** (`{"key": "sandy",
  "label": "Arenosa"}`) so the colour table never keys on pt-BR product copy.
  Rejected. It satisfies the literal criterion and survives a label rename, but
  it invents a concept that must then exist in `ml/config.yaml`, in `export.py`,
  and in Dart, for a benefit that is cosmetic — and no producer emits it today,
  so the app would ship a reader for a field nothing writes. "Never add
  unrequested abstraction" decides this against the tidier shape.
- **Key the colours by model output index.** Rejected. It satisfies the
  criterion with no literals at all, and it assumes the model's output order is
  the physical order of the textural scale. If a retraining reorders the
  classes, the colours follow the position and are silently wrong, and no test
  can catch it because both sides remain internally consistent.
- **Split the failure taxonomy into a second spec.** Rejected. This spec would
  then have to answer what happens when the contract is absent, and that answer
  is the second spec. It would also leave ADR 0011's retry prohibition standing
  after A4 had nominally landed.
- **Hand-write a shared resize so both languages agree bit for bit.** Rejected
  for now. It is the `box_downscale` approach and it works, but it costs a
  second cross-language numerical kernel to close a difference nothing has
  measured, on a path that cannot run at all until a model exists. What skews a
  classifier is the geometry, and the geometry is what this spec makes
  identical.
- **Emit the schema from `ml/src/export.py` in this change.** Rejected. B3 owns
  export hardening and the implementation map states the schema is defined here
  and consumed there. Writing the producer now would either duplicate the
  definition or pull B3's parity gate and checkpoint selection into this review.

## Scope

- Includes:
  - `ModelSpec` — the parsed contract: schema version, model version, dataset
    version, input size, normalization, preprocessing geometry, and the ordered
    class list. Parsing failures are typed, never thrown past the boundary.
  - `ClassificationOutcome` (`ok`, `rejectedOod`, `failed`),
    `ClassificationFailureCause` (the twelve above), and `ClassificationReport`
    carrying the outcome with its result or its cause.
  - `InferenceService.classify` returns `Future<ClassificationReport>` and never
    `null`; `initialize` reports its failures through the same causes.
  - `InferenceService` reads labels, input size and normalization from the
    contract and declares none of them.
  - Dart preprocessing: bake EXIF orientation, crop the largest centred square
    via the existing `roiBounds`, resize, normalize as the contract declares.
  - `ml/src/preprocess.py`: crop the largest centred square via the existing
    `roi_bounds` before the resize.
  - `bakeOrientation` in `image_quality_analyzer.dart` becomes public so the
    inference path reuses it rather than declaring a second copy.
  - Deleting `lib/models/soil_texture_labels.dart` and `SoilTextureColors.all`,
    and the test that asserted the deleted constant.
  - `capture_screen.dart` and `capture_ui_state.dart` consume the report. The
    existing four-member `ClassificationStatus` UI state machine keeps its name
    and its meaning; the cause is carried alongside it.
  - Removing `assets/models/*.tflite` and `assets/models/spec.json` from
    `.gitignore`, which is the change ADR 0012 states lands with this item.
  - A test that fails when a texture label literal appears in `lib/` outside the
    colour table.
  - Updating the A4 row of `docs/architecture/ml-implementation-map.md` to name
    this spec, and recording the two criteria this spec narrows.
- Does NOT include:
  - Any change to `ml/src/export.py`. B3 emits this schema.
  - Committing an `assets/models/spec.json` or any `.tflite`. Un-ignoring the
    paths admits a real artifact; writing a contract for a model that does not
    exist would declare a fact that is not true.
  - Reading or using the `bands` block.
  - Producing `rejectedOod`. The member is declared; its producer is open.
  - Retiring `ConfidenceLevel`, wiring `ClassificationVerdict` into any screen,
    or any threshold calibration. Those are the UI/UX terminal's roadmap item 2
    and work item C2.
  - Persisting the distribution, the outcome or the cause. Schema stays at v4;
    the migration is roadmap item 15.
  - Wiring the image quality gate into capture (roadmap item 6). This spec
    reuses that library's ROI function and changes nothing about the gate.
  - Pixel-exact resize parity between Dart and Python, and any change to
    `ml/src/dataset.py`'s EXIF handling.
  - Any user-facing string change. The capture screen maps every cause to the
    copy it already shows; distinguishing them on screen is roadmap item 2.

## Acceptance Criteria

Contract parsing:

- `absent_contract_yields_contract_missing` — no `spec.json` asset produces
  `ClassificationFailureCause.contractMissing`, not a default contract.
- `malformed_contract_yields_contract_malformed` — bytes that are not valid
  JSON, and valid JSON missing a required field, both produce
  `contractMalformed`.
- `unknown_schema_version_yields_contract_unsupported` — a `spec_version` the
  reader does not implement is refused by that name.
- `unknown_normalization_yields_contract_unsupported` — any method other than
  `divide_255` is refused rather than approximated.
- `unknown_roi_yields_contract_unsupported` — any `input.preprocessing.roi`
  other than `centered_square` is refused.
- `non_square_input_shape_is_rejected` — a `shape` whose height and width
  differ, or whose batch is not 1 or channels not 3, is refused.
- `empty_class_list_is_rejected` — `classes: []` is refused.
- `unknown_key_is_ignored` — a contract carrying `bands` and any other
  unrecognised key parses successfully.
- `labels_keep_their_declared_order` — the parsed label at index `i` is the
  contract's class at index `i`.

Failure taxonomy:

- `classify_never_returns_null` — every path through `classify` returns a
  report.
- `missing_model_asset_yields_model_missing`.
- `empty_model_asset_yields_model_empty`.
- `missing_image_file_yields_image_missing`.
- `undecodable_image_yields_image_undecodable`.
- `inference_timeout_yields_timeout` — and the isolate is still killed.
- `isolate_spawn_failure_yields_isolate_failure`.
- `interpreter_error_yields_interpreter_error`.
- `class_count_mismatch_yields_output_mismatch` — a model whose output width
  differs from the contract's class count.
- `non_probability_output_yields_output_invalid` — a non-finite probability, or
  one outside the unit interval, refuses the tensor.
- `successful_run_yields_ok_with_the_distribution` — the existing distribution
  and its tie-breaking are unchanged.

Preprocessing:

- `dart_crops_the_centred_square_before_resizing` — a non-square input reaches
  the tensor as its centred square, not squashed.
- `dart_bakes_exif_orientation_before_cropping` — an image with a non-identity
  orientation tag is cropped upright.
- `python_crops_the_centred_square_before_resizing` — same property for
  `ml/src/preprocess.py`.
- `roi_geometry_agrees_across_languages` — for a set of widths and heights, the
  Dart and Python ROI bounds are equal.

Labels and repository contract:

- `no_texture_label_literal_outside_the_colour_table` — a sweep of `lib/` fails
  if any of the five class names appears outside
  `lib/core/theme/soil_texture_colors.dart`.
- `labels_come_from_the_contract` — the labels a result carries are the
  contract's, proved by a contract declaring a different order.
- `unknown_label_falls_back_to_outline` — the colour lookup still degrades.
- `model_asset_paths_are_not_ignored` — `.gitignore` no longer excludes
  `assets/models/*.tflite` or `assets/models/spec.json`.

## Reproducibility

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter analyze
flutter test
cd ml && python -m pytest tests/ -v
```

No randomness is involved in any criterion. Every Dart criterion drives
`InferenceService` through its two injected seams — `ModelAssetLoader` and
`InferenceIsolateEntry` — so no criterion needs a real `.tflite`, which is what
makes the whole set runnable before a model exists. The cross-language ROI
criterion compares integer bounds and is exact. Versions: Flutter 3.44.1 / Dart
3.12.1 as pinned by ADR 0004, Python 3.12 with `ml/requirements.txt`.

## Risks and Assumptions

- Assumption: no released model artifact exists, so changing the preprocessing
  geometry cannot invalidate one. `assets/models/` holds only `.gitkeep`, and
  `ml/models/v1` and `v2` hold only `.gitkeep`. Doing this after a model is
  trained would be a train/serve skew; doing it now is free, and it is the last
  moment at which that is true.
- Assumption: `deploy_to_app.sh` remains the only writer of
  `assets/models/spec.json`. Un-ignoring the path makes a hand-copied file
  committable, which is the point, and `spec_version` is what stops an old one
  being read as a current one.
- Risk, unmeasured: the interpolation difference between `img.copyResize` and
  `tf.image.resize` is not quantified, because quantifying it needs a trained
  model to measure the classification effect rather than the pixel delta. It is
  bounded by both being linear filters over the same crop. If Lane C's parity
  work finds it material, the fix is the shared hand-written resize this spec
  rejected, and rejecting it now is what makes that measurable later.
- Risk, recorded not closed: the Python training path never bakes EXIF
  orientation, while admission measures quality through `exif_transpose`. For
  rig-captured images the two agree; the general guarantee belongs to the
  dataset side and is closed either by baking at admission or by asserting an
  identity orientation there. Naming it here stops this spec claiming a parity
  it does not deliver.
- Assumption: narrowing the "zero string literals" criterion to model-decided
  values is the right reading of it. What would invalidate it: a decision that
  the pt-BR class names are themselves model output rather than product copy —
  at which point the `key` alternative becomes correct and this is reversed
  deliberately.
- What would invalidate this spec: `export.py` proving unable to emit
  `dataset_version` because the training run does not know which dataset version
  it consumed. SPEC 0033 makes the version a required config key, so it is
  known; if B3 finds otherwise, the field becomes optional and the reader has to
  say so instead of refusing the contract.
