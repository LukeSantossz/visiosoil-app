# ML Implementation Map

The ordered backlog for the vision/ML workstream. Every item below is scoped,
has acceptance criteria, and names its dependencies, so that executing it is
implementation rather than design. The reasoning behind the choices lives in
`docs/architecture/soil-classification.md`; the decisions live in ADRs 0008–0010
and 0012–0013; the current state for other terminals lives in
`docs/architecture/ml-handoff.md`. This file is the plan, and only the plan.

Last updated: 2026-08-01.

## 1. What we are building

An agronomist photographs soil, the app decides whether the photograph is usable
before it is analysed, classifies it into one of the five Embrapa textural
groups with a probability the number actually justifies, says so honestly when it
cannot decide, and records enough about the analysis that an old result can still
be interpreted a year later. All of it offline.

Concretely, the end state is:

| Stage | End state |
|---|---|
| Capture | The declared protocol is enforced, not merely described. One criteria set (SPEC 0030) governs both what enters the dataset and what the app accepts, so the collection population and the deployment population cannot drift apart by construction |
| Region of interest | The largest centred square after baking EXIF orientation, applied identically in Python and Dart. No aspect-ratio squashing, no segmentation, no detector (ADR 0009) |
| Inference | TFLite in an isolate (ADR 0008), reading labels, input size, normalization, and band constants from a tracked `spec.json` (ADR 0012). No value hardcoded in Dart |
| Result | A calibrated distribution over all classes plus a status, not a single label. `rejectedOod` when the negative signal wins, `failed` when the analysis could not run, and the UI derives its verdict bands from top-1 and the top1−top2 margin |
| Persistence | Status, quality flags, model version, and dataset version stored beside the record (schema v5) |
| Monitoring | Local-first aggregates, nothing transmitted (ADR 0013) |
| Training | Deterministic, fail-loud, group-aware splits, versioned datasets, recorded experiments, and a post-conversion parity gate measured on real held-out images |

## 2. How to read this map

Work items carry a stable identifier (`A1`, `B2`, `C0`). **Spec and ADR numbers
are assigned when the record is authored, not reserved here.** Two terminals
work on this repository in parallel and both consume the same number sequence;
SPEC 0031 and ADR 0011 were taken by the UI/UX terminal while this workstream
held 0030 and 0012–0013. Reserving a block would either collide or leave a hole,
and a hole fails the contiguity check on `main`
(`test/standards/durable_numbering_test.dart`).

Each item states the spec tier it needs. Per
`.standards/docs/standards/spec_method.md`, a spec-lite is enough for a bounded
correction with an obvious shape; full tier is for anything that introduces a
contract, a migration, or a shared surface.

Three lanes run in parallel:

- **Lane A** — application and shared libraries. Needs no dataset. Can start now.
- **Lane B** — training pipeline. Needs no dataset. Can start now.
- **Lane C** — everything that requires images to exist. Gated by E0.

The distinction matters because the dataset does not exist and collecting it is
human work measured in weeks. Lanes A and B are what makes that time productive.

---

## 3. Lane A — application and shared libraries

### A1 — Image acceptance criteria library

**Record:** SPEC 0030 (written, **awaiting the Spec Gate**).
**Depends on:** nothing.
**Blocks:** A3, B2.

Seven model-free metrics over the ROI, implemented in Dart and Python from one
definition, with a committed golden file proving the two agree. No UI, no
capture-flow change.

**Acceptance criteria**

- `ImageQualityAnalyzer` (Dart) and `ml/src/image_quality.py` return the same
  seven metrics for every golden fixture within `1e-9` relative tolerance.
- Three verdicts — `ok`, `advisory`, `blocking` — plus `unvalidated` when the
  analyzer itself fails. An analyzer failure never blocks.
- Only the three calibrated criteria (blur, exposure, ROI side) can produce
  `blocking`. The remaining four are `advisory` until calibrated against a real
  validation set.
- The ROI is defined once and reused by B2 and A3 rather than reimplemented.

### A2 — Classification result contract and schema v5

**Record:** SPEC, full tier. **Shared surface — coordinate with the UI/UX
terminal before editing.**
**Depends on:** nothing.
**Blocks:** A3, A4, A5.

Replace `InferenceResult?` with the contract in `ml-handoff.md` §"Contract other
terminals consume", and migrate `soil_records` to v5 to store status, quality
flags, model version, and dataset version.

**This item is first in priority order after A1, and it needs no model.** Today
`classify()` returns `null` for at least six distinct conditions — model absent,
asset empty, decode failure, timeout, interpreter error, isolate death — and
every one of them is presented to the user identically. Fixing that is real
value delivered while the dataset is still being collected, and it is what
unblocks the UI/UX terminal's SPEC 0031.

**Acceptance criteria**

- `ClassificationStatus` is `{ ok, rejectedOod, failed }`. No `inconclusive`:
  conclusive, ambiguous, and insufficient-evidence are bands the UI derives.
- `distribution` carries every class, descending, and is empty unless status is
  `ok`.
- The six `null` conditions are separated internally and mapped to `failed` with
  a distinguishable cause, so A5 can count them apart.
- Migration v4→v5 follows the cumulative pattern in `AppDatabase.migration`,
  backfills existing rows with a null model version rather than a fabricated
  one, and has a test that opens a v4 database and reads it at v5.
- Existing records classified before v5 remain readable and are not silently
  relabelled.

### A3 — Capture quality gate

**Record:** SPEC, full tier. **Shared surface — `lib/core/features/capture/` is
being redesigned by the UI/UX terminal. Interface agreed before either side
edits.**
**Depends on:** A1, A2.

Wire the criteria into the capture flow: ROI overlay, verdict surfaced before
analysis, named reason for a retake, and an override path.

**Acceptance criteria**

- A `blocking` verdict offers a retake and names which criterion failed, in
  pt-BR product copy.
- The override path exists and is one tap. A false block costs more than a
  flagged bad analysis; a gate with no escape hatch will be worked around by
  photographing a screen, which is worse than analysing a blurry photo.
- An overridden capture is recorded with its quality flags, so the override is
  visible later rather than lost.
- `advisory` never interrupts the flow.
- The analyzer runs off the UI thread and does not delay the shutter.

### A4 — `spec.json` as the runtime contract

**Record:** SPEC, full tier. Closes #79 and #116.
**Depends on:** A2, ADR 0012.
**Paired with:** B3, which must emit exactly what this reads. **The schema is
defined in this spec and consumed by B3, not defined twice.**

`InferenceService` stops hardcoding labels, input size, and normalization, and
reads them from the tracked `assets/models/spec.json`. The label list gets one
source of truth, consumed by `SoilTextureColors` too.

**Acceptance criteria**

- The `spec.json` schema is written down in the spec: labels in model output
  order, input size, normalization mode, preprocessing, model version, dataset
  version, and the per-class band constants.
- A missing, malformed, or version-incompatible `spec.json` produces `failed`
  with a distinguishable cause — never a silent fallback to hardcoded defaults.
  A silent fallback is how a train/serve skew survives review.
- Zero string literals naming a texture class remain in `lib/`, enforced by a
  test that greps the tree. The label list currently exists in six independent
  copies with nothing asserting they agree.
- `SoilTextureColors.all` returns the `spec.json` order. It currently documents
  itself as "model output order" while ordering Siltosa before Media,
  contradicting `InferenceService`.
- Dart-side preprocessing matches `ml/src/preprocess.py` exactly: centred square
  ROI, then resize, then the normalization named in `spec.json`. The current
  `img.copyResize(width: 224, height: 224)` squashes the aspect ratio and is a
  defect, not a convention.

### A5 — Local diagnostics

**Record:** SPEC, spec-lite. Implements ADR 0013.
**Depends on:** A2.

On-device Tier 1 aggregates, visible in settings, resettable, and shareable only
by explicit action.

**Acceptance criteria**

- Counters only, no per-record event log, no unbounded growth.
- Counts are keyed by model version so a version change does not pollute the
  history.
- The shareable summary is human-readable text and contains no image path, no
  coordinate, no address, and no record identifier. A test asserts this against
  a populated database.
- No network client is added.

---

## 4. Lane B — training pipeline

### B1 — Deterministic and fail-loud training

**Record:** SPEC, spec-lite. Closes #80, #25, #81; the config-validation half of
#29; #28.
**Depends on:** nothing.
**Blocks:** B2, C0.

Four corrections that share one purpose: an experiment whose result cannot be
reproduced or whose inputs were silently dropped is not evidence.

**Acceptance criteria**

- One global seed set for Python, NumPy, and TensorFlow from `config.yaml`
  (#80). Two runs of one config produce identical metrics. **This is the
  denominator E0 needs**: without it, "better than the shuffled control by more
  than run-to-run variance" has no meaning.
- `_parse_image` fails loudly on an undecodable file and names it (#25). It
  currently swallows the failure, so a corrupt image silently becomes a black
  square with a real label attached.
- Brightness and contrast augmentation honour both bounds of their configured
  range (#81). The realized augmentation distribution today is not the
  configured one, which invalidates any before/after comparison of augmentation.
- `config.yaml` is validated on load: unknown keys rejected, ranges checked,
  class list non-empty and matching the label source (#29).
- `ml/tests/` runs in CI (#28).

### B2 — Dataset protocol, manifest, and versioning

**Record:** SPEC, full tier.
**Depends on:** A1 (Python criteria), B1 (seed).
**Blocks:** C0. **This is the long pole and should be authored early**, because
it defines the work a human then has to go and do.

The collection protocol, the metadata every sample must carry, the on-disk
layout, and the split generator. Written so that a field agronomist can execute
it without this terminal present.

**Acceptance criteria**

- Directory layout and the filename → `sample_id` convention are stated and
  parsed by one function, not a regex duplicated per script.
- Required metadata per sample: sample id, laboratory report reference, textural
  class, collection site, capture device, capture date, and **moisture state**.
  Moisture is recorded because it confounds colour, and a model that learns
  moisture instead of texture will look correct on a curated set and fail in the
  field. It is not recoverable retroactively.
- Admission is by A1's criteria: an image that would be `blocking` in the app
  does not enter the dataset. A divergence here reopens the exact gap ADR 0009
  closes.
- A dataset version is an immutable directory. Adding images creates `vN+1`; it
  never mutates `vN`. Every experiment record names the version it used.
- Splits are group-aware on sample id, and additionally stratified by site and
  device so that a split cannot leak a location or a camera. `splits.json` is
  committed; the generator is deterministic given the seed.
- The manifest validates: every row's image exists, every image has a row, every
  class has enough groups to split, and no `sample_id` appears in two splits.
- A dry-run on a synthetic fixture manifest proves the validator catches each of
  those failures.

### B3 — Export hardening and release path

**Record:** SPEC, full tier. Closes the export half of #29 and #30.
**Depends on:** B1, A4 (the `spec.json` schema), ADR 0012.

**Acceptance criteria**

- The post-conversion parity gate runs on the real held-out test set, not on
  `np.random.rand` (`export.py:92`). It reports agreement rate, accuracy delta,
  and calibration delta between the Keras and TFLite models — a max-absolute-
  difference against a hardcoded 0.01 threshold (`export.py:112`) measures
  nothing about whether the converted model still classifies soil.
- `export.py` exports the selected checkpoint, not always `model.keras`
  (`export.py:39-46` never loads `best_model.keras`).
- `spec.json` is emitted into `assets/models/` in the schema A4 defines, and
  `deploy_to_app.sh` promotes an export as one atomic act.
- Model path resolution exists once (#30).
- The release commit message names the dataset version and the headline metrics,
  per ADR 0012.

---

## 5. Lane C — requires the dataset

### C0 — Inventory and the E0 feasibility probe

**Record:** SPEC, spec-lite for the harness; the verdict is a document, not code.
**Depends on:** B1, B2, and images existing.
**Gate for:** everything below.

**Acceptance criteria**

- An inventory of whatever exists: counts by class, group, site, device, and
  moisture state. Image counts alone do not size a split.
- E0 runs three arms across several seeds: the real model, a
  colour-histogram-only baseline, and a label-shuffled control.
- The verdict is written down and committed with its numbers, whichever way it
  goes.

**If the real model does not separate from the shuffled control by more than
run-to-run variance, the product premise is wrong and Lane C stops.** Soil colour
tracks organic matter and iron oxides rather than granulometry, so this is a
genuine open question, not a formality. The colour-histogram baseline exists to
answer a second one: if the real model matches it, the model learned colour, not
texture, and no amount of architecture work will fix that.

### C1 — Baseline and sweep (E1–E5)

Real-only floor, corrected augmentation, compositing, backbone sweep
(MobileNetV2 / MobileNetV3 / EfficientNet-Lite0), loss sweep (weighted CE vs
focal). Exit gate: a recorded baseline in `ml/models/vN` with committed metrics.

### C2 — Calibration and rejection (E6, E7)

Temperature scaling, ECE and reliability diagrams, per-class rejection
thresholds swept at equal coverage. Exit gate: ECE reported, and the calibrated
distribution plus the per-class band constants published in `spec.json`.

**The band constants must be calibrated after temperature scaling.** The values
in the UI/UX terminal's design (0.70 / 0.45 / 0.15) are hypotheses about raw
softmax; calibrating against raw output and later enabling scaling would shift
every band silently.

### C3 — Quantization ladder (E8)

Float32, float16, dynamic range, full int8. Selection criterion is accuracy
**and** calibration, because quantization can preserve the argmax while
destroying the probability the UI presents as a percentage. Feeds the release
under ADR 0012.

### C4 — Conditional synthetic branch (E9–E12)

Runs only if ADR 0010's five conditions hold, which requires a measured dataset
deficiency that traditional augmentation and compositing failed to close.
Not scheduled.

---

## 6. Order of execution

```
now ─┬─ A1 (0030, awaiting gate) ─┬─ A3 ── (with UI/UX terminal)
     │                            └─ B2 ── dataset collection (human, weeks)
     ├─ A2 ─┬─ A3                                    │
     │      ├─ A4 ── B3                              │
     │      └─ A5                                    │
     └─ B1 ─┴─ B2                                    │
                                                     ▼
                                          C0 ── GATE ── C1 ── C2 ── C3 ── release
```

Recommended immediate order: **A1 gate → A2 → B1 → B2 → A4/A3 → A5**, with
collection starting the moment B2 lands. A2 before B1 because it unblocks
another terminal; B2 early because it starts a human process that no amount of
code shortens.

## 7. Decisions required from you

These are not work items. They are inputs that only you can supply, and Lane C
cannot be scheduled without them.

1. **Who collects the dataset, at which sites, with which devices?** The split
   axes in B2 are only meaningful if there is more than one of each.
2. **Is there access to the laboratory granulometry reports**, and what are the
   exact Embrapa grouping thresholds that produced the labels? Needed to build
   the cost-weighted confusion matrix — confusing Arenosa with Muito Argilosa is
   not the same error as confusing Média with Argilosa.
3. **Can moisture state be recorded at collection time?** If not, it is
   unrecoverable and the confound stays.
4. **What does one laboratory analysis cost, in money and turnaround?** It sets
   the realistic target N per class and decides whether active learning is worth
   building.
5. **Target N per class.** Without an answer, B2's protocol states a minimum
   derived from the split constraint alone, which is a floor, not a goal.

## 8. Coordination with the UI/UX terminal

Resolved:

- **Criteria count** — SPEC 0030 keeps seven metrics; only the three the UX gate
  names can block. The other four are advisory until calibrated, so nothing the
  UX design expected to pass can be rejected by them.
- **`SoilTextureColors` label order** — the UI/UX terminal owns the immediate
  fix in its own spec. A4 later moves the source of truth to `spec.json`, which
  supersedes the fix rather than conflicting with it.
- **Band constants** — this terminal calibrates and publishes them in
  `spec.json` (C2). The UI reads them; it does not hardcode them.

Still requiring agreement before either side edits:

- `lib/core/features/capture/` (A3) and the schema v5 migration (A2). Both are
  shared surfaces. The contract is in `ml-handoff.md`; the sequencing is here.
