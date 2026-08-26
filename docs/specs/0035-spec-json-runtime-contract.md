# SPEC (full): refactor(inference): read the model contract from spec.json instead of hardcoding it


> **Revised 2026-08-25.** The schema below is incomplete against three decisions
> taken after this specification was Gate-approved. The contract must declare
> every value the model was trained under, and six are missing.
>
> | Field | From |
> |---|---|
> | `canonical_mm_per_px` | [ADR 0017](../adr/0017-scale-is-read-by-a-classical-operator-on-a-known-circle.md) — a model trained at one canonical scale cannot be served at another |
> | `scale_reference` | ADR 0017 — which object carries the reference on the application side |
> | `patch_mm`, `patch_count` | [ADR 0018](../adr/0018-model-sees-fixed-size-greyscale-patches-and-their-spread-is-a-quality-signal.md) |
> | `color_mode` | ADR 0018 — greyscale, replicated to three channels |
> | `aggregation` | ADR 0018 — mean over patch distributions |
> | `dispersion_threshold` | ADR 0018 — advisory, uncalibrated |
>
> Two further changes:
>
> - **`classes` carries four entries, not five.** ADR 0016 excludes Siltosa from
>   the first model. This makes reading the contract a **release blocker rather
>   than a next item**: `SoilTextureLabels.ordered` declares five and
>   `resolveTextureLabel` refuses a four-class tensor, so a four-class model
>   cannot run in the application until the labels come from this file.
> - **The centred-square crop is not the preprocessing any more.** Reading the
>   scale precedes the crop, and the crop is a patch grid.
>   [SPEC 0037](0037-scale-normalised-greyscale-patch-pipeline.md) owns that
>   pipeline; this specification owns the contract file and the failure taxonomy,
>   and gains one cause — the scale reference could not be read — in ADR 0015's
>   middle column, where retrying is the right response.
>
> Everything else here stands: the twelve causes, the refusal to fall back
> silently, the enum-plus-payload shape, and the preservation of the initialise
> cause across the isolate boundary.

## Problem

`InferenceService` hardcodes the label list, the input size and the
normalization that `ml/src/export.py` already publishes in `spec.json` and that
`deploy_to_app.sh` already copies into the application, so a pipeline change and
a Dart change must be made by hand in step or the app classifies against a
contract the shipped model does not implement.

This is work item A4 of `docs/architecture/ml-implementation-map.md` and it
closes issue #79. Issue #116, its stated precondition, is closed: the label
order already has a single app-side declaration.

## Design Decisions

The contract ships inside the artifact and is read when the model is loaded.
`spec.json` becomes the single runtime source for the label list and its order,
the input size, the normalization method and the preprocessing geometry, and
`InferenceService` holds none of them as source constants. Because a contract
that can be absent must not degrade into the values it replaced, `classify`
stops returning `null` and returns a report that names what happened — which is
also what separates the causes `null` collapsed. The centred-square region of
interest the contract declares is applied in `inference_service.dart` and in
`ml/src/preprocess.py` in this same change, because applying it on one side only
is the skew this spec exists to remove.

### The schema, defined here and emitted by B3

The schema below is the contract. It is defined in this spec and consumed by
work item B3, which makes `ml/src/export.py` emit it; it is not defined twice.
It is the file `_build_spec` (`ml/src/export.py:118`) already produces — which
returns exactly `version`, `input`, `output` and `classes` (`export.py:159-172`)
— plus **four** additions, so that B3 is a bounded change rather than a rewrite
of a producer nobody has exercised end to end.

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
  "bands": {
    "per_class": {
      "Arenosa": { "conclusive_min_margin": 0.15, "conclusive_min_top_share": 0.50, "ambiguous_min_pair_share": 0.65 },
      "Media": { "conclusive_min_margin": 0.15, "conclusive_min_top_share": 0.50, "ambiguous_min_pair_share": 0.65 },
      "Siltosa": { "conclusive_min_margin": 0.15, "conclusive_min_top_share": 0.50, "ambiguous_min_pair_share": 0.65 },
      "Muito Argilosa": { "conclusive_min_margin": 0.15, "conclusive_min_top_share": 0.50, "ambiguous_min_pair_share": 0.65 },
      "Argilosa": { "conclusive_min_margin": 0.15, "conclusive_min_top_share": 0.50, "ambiguous_min_pair_share": 0.65 }
    }
  }
}
```

`bands.per_class` carries **one entry for every member of `classes`**, and the
block is written out in full above rather than abbreviated, because a schema
shown with one class and described as per-class is a schema B3 can implement
partially without noticing.

The four additions, and why each is not optional:

- **`spec_version`** guards the reader against a file written to a different
  schema. The artifact ships inside the APK, so schema skew between app and
  model is not the ordinary case; a `spec.json` copied in by hand from an older
  export is, and `deploy_to_app.sh` is exactly the tool that makes that easy.
  Without this field an older file is read successfully and wrongly. What it
  does **not** do is bind the contract to a particular model artifact; that is
  the next subsection.
- **`dataset_version`** exists because SPEC 0033 now produces one and ADR 0012
  requires the release record to name it. Carrying it in the contract rather
  than only in a commit message is what lets a diagnostic report which data a
  running model came from.
- **`input.preprocessing`** turns two tacit conventions into declared ones. The
  centred-square ROI and the baked EXIF orientation are today agreements between
  files that never reference each other; a contract that omits them cannot
  detect a producer that stops honouring them.
- **`bands`** carries the per-class verdict constants, keyed by class name, each
  naming the three quantities ADR 0011 decided — the constants
  `ClassificationVerdict` currently declares globally as
  `conclusiveMarginThreshold`, `conclusiveTopShareThreshold` and
  `ambiguousPairShareThreshold` (`classification_verdict.dart:41,44,52`). The
  values shown above are those provisional globals repeated per class as
  placeholders; **work item C2 calibrates them after temperature scaling, and
  this spec invents no number.** The block is defined here because the map
  requires the schema to include the band constants and to be defined once; it
  is **not read** by this spec, because nothing consumes band constants today —
  `ClassificationVerdict` has no production caller — and parsing a field nothing
  reads is dead code. The acceptance criteria make that safe by requiring an
  unrecognised key to be ignored rather than rejected, so C2 can add or rename
  a band quantity without an application change.

### Binding the contract to the artifact, and the residual this leaves

`spec_version` versions the schema, not the release. Two files copied
independently into `assets/models/` can therefore be a current schema describing
a different model, and nothing in the paragraph above would notice.

The contract is checked against the loaded model itself: after
`Interpreter.fromBuffer`, the interpreter's own input and output tensors are
compared with `input` and `output` — **shape and dtype both** — and a
disagreement is `modelContractMismatch`. The dtype half matters on its own: a
model whose input tensor is `int8` or `float16` while the contract declares
`float32` passes every shape check, and the service would feed it the float32
tensor it built from the declaration. The service already reads the output shape
(`inference_service.dart:236-237`) to size its output buffer; this makes the
read a check rather than an assumption, and it costs nothing new. It catches the
mismatches that change the arithmetic — a different input size, a different
class count, a different element type.

**What it does not catch is recorded rather than papered over:** two models with
identical tensor shapes and different label orders are indistinguishable to this
check, and that is precisely the skew #79 exists to prevent. Three things
contain it. `deploy_to_app.sh` copies both files in one act, ADR 0012 makes the
release one commit carrying both, and `dataset_version` plus `version` in the
contract make the pairing auditable after the fact. If that proves insufficient,
the escalation is a `model_sha256` field the app verifies against the bytes it
loaded; it is not taken here because it needs a hashing dependency the project
does not have, to close a gap no released artifact has yet been able to open.

### Why the failure taxonomy arrives with the contract

This decision was promoted at the Gate into
[`docs/adr/0015-classification-reports-a-named-failure-cause.md`](../adr/0015-classification-reports-a-named-failure-cause.md),
which is the curated record of it; what follows is why it belongs in this spec's
scope rather than a later one.

`classify` returns `Future<InferenceResult?>` today, and seven `return null`
statements are reachable from it (`inference_service.dart:165, 190, 211, 215,
256, 259, 280`). ADR 0011 (`:92-106`) accepted shipping `notAnalysed` derived
from that `null` and priced the acceptance precisely: **no result surface may
offer retry on `notAnalysed` until A4 lands**. This spec is A4, so the
separation lands here rather than being deferred again.

It also cannot be deferred on its own terms. Reading a contract introduces three
new ways to fail — absent, malformed, unsupported — and the acceptance criterion
this spec inherits forbids any of them degrading into a hardcoded default. A
failure that must be distinguishable cannot be reported through a value whose
entire defect is that it distinguishes nothing.

The causes are grouped by what the reader can do about them, which is the only
grouping that earns their number:

| Nothing to do — the build is wrong | Retrying is the right response | Re-export the model |
| --- | --- | --- |
| `contractMissing` | `timeout` | `contractUnsupported` |
| `contractMalformed` | `interpreterError` | `modelContractMismatch` |
| `modelMissing` | `isolateFailure` | `outputInvalid` |
| `modelEmpty` | `imageMissing` | |
| | `imageUndecodable` | |

Twelve, derived once and the same way in this spec and in ADR 0015, from the six
ADR 0011 enumerated (`0011:95-97`): a missing model asset, an isolate spawn
failure, a timeout, a decode failure, a class-count mismatch, and an inference
error — which are `modelMissing`, `isolateFailure`, `timeout`,
`imageUndecodable`, `modelContractMismatch` and `interpreterError` here.

- **Three are new with the contract**: `contractMissing`, `contractMalformed`,
  `contractUnsupported`.
- **Three are facts the code already distinguishes and then discards on the way
  out**: `modelEmpty`, which `initialize` separates from an absent asset via
  `_modelUnavailable` (`inference_service.dart:124-128`); `imageMissing`, which
  `_runInference` separates from an undecodable one (`:211` against `:215`); and
  `outputInvalid`, which `buildDistribution` refuses for a different reason than
  a class-count mismatch (`:347-351` against `:333-334`).

`modelContractMismatch` is ADR 0011's class-count mismatch widened to cover the
input tensor as well, per the binding subsection above.

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

**The isolate response message changes with the return type.** `_runInference`
answers on `request.responsePort` with an `InferenceResult?` today
(`inference_service.dart:203`, cast back at `:184`), and five of the twelve
causes — `imageMissing`, `imageUndecodable`, `interpreterError`,
`modelContractMismatch` and `outputInvalid` — are produced inside the isolate.
The message therefore becomes the report, and the Scope names it, because a
taxonomy that cannot cross the boundary it is produced behind is not
implementable.

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
narrowing follows SPEC 0030, which carried three corrections its own
implementation forced (`0030:74,126,295`) in the specification rather than in
silence.

Two alternatives that would satisfy the criterion literally were weighed and are
recorded under Alternatives Considered; both cost more than the property is
worth.

`SoilTextureColors.all` is removed with the constant it orders itself by. **It
has no caller in `lib/`, and two in `test/`** —
`test/models/soil_texture_labels_test.dart:29,36`, a file this change deletes
outright. Three further test sites and one doc comment reference the deleted
constant or the nullable return and are named in the Scope, because a deletion
whose blast radius is discovered during implementation is a deletion that was
not specified.

### What the ROI parity proves, and what it does not

The order becomes identical on both sides: upright image, largest centred
square, resize, the normalization the contract names.

**The Dart correction is about order, not about absence.** `img.copyResize`
bakes EXIF orientation itself when the tag is present and not identity
(`image-4.8.0/lib/src/transform/copy_resize.dart:33-35`), so today's path is
already upright — by a side effect of the resize, discovered only by reading a
third-party function's body. Introducing a crop in front of it would make the
result depend on that internal, so the baking becomes explicit and happens
first. This is safe against double application because `bakeOrientation` clears
the orientation tag on the copy it returns
(`image-4.8.0/lib/src/transform/bake_orientation.dart:19`), so the subsequent
`copyResize` finds nothing to bake. The aspect-ratio squash at
`inference_service.dart:218-223` is the real defect and is what the crop fixes.

`ml/src/preprocess.py` gains the same crop, at the call site in `preprocess()`
(`preprocess.py:48`) rather than inside the generic `resize` helper, whose
contract is exactly to resize.

**One honest correction to the reuse claim.** `roiBounds`
(`image_quality_analyzer.dart:34`) is reused directly by the Dart path.
`roi_bounds` (`ml/src/image_quality.py:123`) **cannot** be: `preprocess` runs in
graph mode under `ds.map` (`ml/src/dataset.py:408-411`) on a tensor whose shape
is `[None, None, 3]` (`:376`), and `roi_bounds` is pure Python arithmetic over
concrete ints. The Python side therefore needs a symbolic expression —
`tf.shape` plus `tf.image.crop_to_bounding_box` — which is a second expression
of the same geometry. Rather than let that divergence be tacit, `roi_bounds`
stays the reference definition and the symbolic version is **proved equal to
it** by a committed table of shapes that both languages assert against. That is
the mechanism the cross-language criterion names, and it is the shape SPEC 0030
used for `golden.json`.

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
(`ml/src/dataset.py:375`, inside `_parse_image`) discards EXIF by construction,
so the Python path never bakes orientation, while admission measures quality
through `exif_transpose` (`ml/src/image_quality.py:161`). For rig-captured
dataset images the baking is a no-op and the two paths agree on their own
inputs; proving that belongs to the dataset side, and it is named in Risks and
Assumptions with where it is closed. The contract's
`input.preprocessing.exif_orientation` therefore describes what the **inference**
path does, which is what the app must honour, and the spec does not claim the
training path enforces it.

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
- **Bind the contract to the artifact with a `model_sha256` field.** Rejected
  for now, and it is the closest call in this list. It is the only option that
  closes the same-shape-different-labels case outright. It costs a hashing
  dependency Dart does not provide in its core libraries, to guard a pairing
  that `deploy_to_app.sh` and ADR 0012's single release commit already make
  atomic, against an artifact that does not exist yet. The tensor-shape check
  above takes the part that is free; this is named as the escalation so that
  taking it later is a decision rather than a discovery.
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
    version, input shape and dtype, normalization, preprocessing geometry,
    output shape, dtype and type, and the ordered class list. Parsing failures
    are typed, never thrown past the boundary.
  - `ClassificationOutcome` (`ok`, `rejectedOod`, `failed`),
    `ClassificationFailureCause` (the twelve above), and `ClassificationReport`
    carrying the outcome with its result or its cause.
  - `InferenceService.classify` returns `Future<ClassificationReport>`, and
    **`initialize` returns `Future<ClassificationFailureCause?>`** — `null` when
    the service is ready. A `bool` is what loses the cause: `classify` calls
    `initialize` before every run (`inference_service.dart:163-166`), so a bare
    `false` would put `contractMissing`, `contractMalformed`, `modelMissing` and
    `modelEmpty` back into one indistinguishable value at exactly the boundary
    this spec exists to widen.
  - **The isolate response message becomes the report**, so the five causes
    produced inside `_runInference` reach the caller.
  - **`_runInference` is decomposed into a decode-and-preprocess step and a pure
    interpret-output step**, both `@visibleForTesting`, mirroring how
    `resolveTextureLabel` and `buildDistribution` are already exposed
    (`inference_service.dart:311,329`). Without this, `InferenceIsolateEntry`
    replaces the whole worker, so a fake can only send a prebuilt report and the
    branches inside it are never exercised — the criteria would assert the
    taxonomy against a test double of themselves.
  - `InferenceService` reads labels, input size and normalization from the
    contract and declares none of them; it compares the contract's input and
    output shape **and dtype** against the loaded interpreter's own.
  - Dart preprocessing: bake EXIF orientation explicitly, crop the largest
    centred square via the existing `roiBounds`, resize, normalize as the
    contract declares.
  - `ml/src/preprocess.py`: crop the largest centred square inside
    `preprocess()` with a symbolic expression, plus
    `test/fixtures/roi/roi_bounds.json` — a committed table of image dimensions
    and their expected bounds, asserted by both test runners, which is what
    makes the two expressions of the geometry one contract.
  - `_bakeOrientation` in `image_quality_analyzer.dart` becomes public so the
    inference path reuses its identity-orientation guard.
  - Deleting `lib/models/soil_texture_labels.dart`, `SoilTextureColors.all`, and
    `test/models/soil_texture_labels_test.dart`; and migrating the sites that
    reference either the deleted constant or the nullable return —
    `test/models/classification_verdict_test.dart:12`,
    `test/services/inference_distribution_test.dart:17,20`,
    `test/services/inference_service_test.dart:192`,
    `test/features/capture/capture_screen_test.dart:26`, and the doc comment at
    `lib/models/class_score.dart:7`.
  - `capture_screen.dart` and `capture_ui_state.dart` consume the report. The
    existing four-member `ClassificationStatus` UI state machine keeps its name
    and its meaning; the cause is carried alongside it.
  - Removing `assets/models/*.tflite` and `assets/models/spec.json` from
    `.gitignore`, which is the change ADR 0012 states lands with this item. ADR
    0012 deferred it on the reasoning that there was "nothing to un-ignore"; what
    changes that is not a file arriving but the reader arriving — the entry now
    blocks the artifact that the code in this spec is written to consume, and
    leaving it would mean a release commit that has to edit `.gitignore` and ship
    a model in one act.
  - A test that fails when a texture label literal appears in `lib/` outside the
    colour table.
- Landed with the specification commit rather than the implementation, because
  a record nobody can find is not recorded:
  - The `README.md` Engineering Decisions row for ADR 0015.
  - The A4 row of `docs/architecture/ml-implementation-map.md`, naming this spec
    and recording the criteria it narrows.
- Does NOT include:
  - Any change to `ml/src/export.py`. B3 emits this schema.
  - Committing an `assets/models/spec.json` or any `.tflite`. Un-ignoring the
    paths admits a real artifact; writing a contract for a model that does not
    exist would declare a fact that is not true.
  - Reading or using the `bands` block.
  - A `model_sha256` field or any hashing dependency.
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
- `unsupported_exif_orientation_yields_contract_unsupported` — any
  `input.preprocessing.exif_orientation` other than `baked` is refused. The Dart
  path always bakes, so accepting `none` would declare the skew this field
  exists to detect and then proceed anyway.
- `unsupported_input_dtype_yields_contract_unsupported` — an `input.dtype` other
  than `float32` is refused, because the Dart path builds a float32 tensor.
- `unsupported_output_type_yields_contract_unsupported` — an `output.type` other
  than `probabilities` is refused; logits that happen to fall inside the unit
  interval would otherwise pass every downstream guard.
- `non_square_input_shape_is_rejected` — a `shape` whose height and width
  differ, or whose batch is not 1 or channels not 3, is refused.
- `output_shape_disagreeing_with_classes_is_rejected` — `output.shape[1]` must
  equal the length of `classes`.
- `empty_class_list_is_rejected` — `classes: []` is refused.
- `unknown_key_is_ignored` — a contract carrying `bands` and any other
  unrecognised key parses successfully.
- `labels_keep_their_declared_order` — the parsed label at index `i` is the
  contract's class at index `i`.

Failure taxonomy. The non-nullable return type is enforced by the compiler
rather than by a test; what the criteria assert is that each cause is reachable
and distinguishable:

- `missing_model_asset_yields_model_missing`.
- `empty_model_asset_yields_model_empty`.
- `failed_initialize_returns_the_cause` — `initialize` returns the cause
  `classify` then reports, and returns `null` once the service is ready, so no
  startup failure is flattened on its way to the caller.
- `missing_image_file_yields_image_missing`.
- `undecodable_image_yields_image_undecodable`.
- `inference_timeout_yields_timeout` — and the isolate is still killed.
- `isolate_spawn_failure_yields_isolate_failure`.
- `interpreter_error_yields_interpreter_error`.
- `interpreter_disagreeing_with_contract_yields_model_contract_mismatch` — for
  the input tensor and the output tensor independently, and for shape and dtype
  independently.
- `non_probability_output_yields_output_invalid` — a non-finite probability, or
  one outside the unit interval, refuses the tensor.
- `successful_run_yields_ok_with_the_distribution` — the existing distribution
  and its tie-breaking are unchanged.
- `capture_screen_renders_a_failed_report_without_a_result` — the screen reads
  the report rather than a null check, and a cause it does not distinguish still
  reaches the failed state it renders today.

Preprocessing:

- `dart_crops_the_centred_square_before_resizing` — a non-square input reaches
  the tensor as its centred square, not squashed.
- `dart_bakes_exif_orientation_before_cropping` — an image with a non-identity
  orientation tag is cropped upright, and is not rotated twice.
- `python_crops_the_centred_square_before_resizing` — same property for
  `preprocess()`, asserted on a symbolic tensor.
- `dart_roi_bounds_match_the_committed_table` and
  `python_roi_bounds_match_the_committed_table` — both languages agree with
  `test/fixtures/roi/roi_bounds.json`, which is what makes the Dart function and
  the symbolic Python expression one geometry.

Labels and repository contract:

- `no_texture_label_literal_outside_the_colour_table` — a sweep of `lib/` fails
  if any of the five class names appears outside
  `lib/core/theme/soil_texture_colors.dart`.
- `labels_come_from_the_contract` — the labels a result carries are the
  contract's, proved by a contract declaring a different order.
- `unknown_label_falls_back_to_outline` — the colour lookup still degrades.
- `soil_texture_colors_declares_no_ordering` — `all` is gone, so nothing claims
  a model output order on the theme side.
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

No randomness is involved in any criterion. Nothing here needs a real `.tflite`,
which is what makes the whole set runnable before a model exists, and the three
ways that holds are worth separating because the second is new:

1. The service-level criteria drive `InferenceService` through its two injected
   seams, `ModelAssetLoader` and `InferenceIsolateEntry`.
2. The criteria for causes produced inside the worker call the two
   `@visibleForTesting` steps directly — decode-and-preprocess with a real image
   file, interpret-output with a fabricated tensor — rather than through a fake
   entry point that would only replay a canned answer. `interpreterError` is the
   single exception: it needs a real interpreter to throw, so it is asserted
   through the injected entry point, and that is stated rather than hidden
   behind a criterion that looks like the others.
3. Four criteria do not touch the service at all and are static or fixture
   checks: `dart_roi_bounds_match_the_committed_table`,
   `no_texture_label_literal_outside_the_colour_table`,
   `unknown_label_falls_back_to_outline` and `model_asset_paths_are_not_ignored`.

The ROI table compares integer bounds and is exact. Versions: Flutter 3.44.1 /
Dart 3.12.1 as pinned by ADR 0004, Python 3.12 with `ml/requirements.txt`.

## Risks and Assumptions

- Assumption: no released model artifact exists, so changing the preprocessing
  geometry cannot invalidate one. `assets/models/` holds only `.gitkeep`, and
  `ml/models/v1` and `v2` hold only `.gitkeep`. Doing this after a model is
  trained would be a train/serve skew; doing it now is free, and it is the last
  moment at which that is true.
- Assumption: `deploy_to_app.sh` remains the only writer of
  `assets/models/spec.json`, and copies it with the artifact it belongs to. The
  tensor-shape check catches a mismatch that changes a dimension; a mismatch
  that only reorders labels is contained by process, not by code, and the
  `model_sha256` escalation is named in Alternatives Considered.
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
  it does not deliver, and the contract field is scoped to the inference path
  for the same reason.
- Risk: the symbolic Python crop is a second expression of `roi_bounds`. The
  committed table is what keeps them one geometry, and it is the only reason the
  reuse claim is narrowed rather than dropped. If a third consumer ever needs
  the bounds in graph mode, the table is what it is measured against too.
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
