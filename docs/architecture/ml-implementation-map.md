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
| Capture | The declared protocol is enforced, not merely described. One criteria set (SPEC 0030) governs both what enters the dataset and what the app accepts, so the two populations cannot drift apart **in photographic quality**. They still differ in subject: collection is bench-prepared, air-dried and sieved, deployment is in situ. Shared admission criteria cannot close that, and ADR 0009 records why |
| Region of interest | The largest centred square after baking EXIF orientation, applied identically in Python and Dart. No aspect-ratio squashing, no segmentation, no detector (ADR 0009) |
| Inference | TFLite in an isolate (ADR 0008), reading labels, input size, normalization, and band constants from a tracked `spec.json` (ADR 0012). No value hardcoded in Dart |
| Result | A calibrated distribution over all classes plus a status, not a single label. `failed` when the analysis could not run, and the UI derives its verdict bands from top-1 and the top1−top2 margin. `rejectedOod` is a **reserved** status for the "not soil" signal — whether it is produced by a trained negative class or by the quality gate plus a threshold is open, informed by E12 |
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

- **Lane A** — application-side work this workstream owns. Needs no dataset.
- **Lane B** — training pipeline. Needs no dataset. Can start now.
- **Lane C** — everything that requires images to exist. Gated by E0.

The distinction matters because the dataset does not exist and collecting it is
human work measured in weeks. Lanes A and B are what makes that time productive.

### Ownership, settled 2026-08-01

The first version of this map claimed the classification contract, the capture
gate, and the schema v5 migration for this workstream. It was written before
`docs/design/ux-2026/13-roadmap.md` was in version control, and that roadmap
already owns all three. Duplicating them would have put two specs on the same
files. The split, decided by the project owner:

| Owner | Work |
|---|---|
| UI/UX terminal | Their roadmap item 1 — the classification contract, `ClassScore`, the distribution, and the verdict bands (their SPEC 0031). Item 6 — wiring the quality gate into capture. Item 15 — the v4 → v5 migration that persists the distribution |
| This workstream | All of `ml/`. The `spec.json` runtime contract beyond the label list. Local diagnostics. Calibration of every threshold and band constant either side ships |

Two consequences worth recording, because neither is obvious from the split:

- **Their SPEC 0031 does not resolve the `null` conflation.** It keeps
  `classify()` returning `null` and derives `notAnalysed` from it, so the six
  distinct causes — model absent, empty asset, decode failure, timeout,
  interpreter error, isolate death — remain indistinguishable to the caller.
  That is still a live defect after item 1 lands. It sits inside
  `inference_service.dart`, which this workstream owns, and is folded into A4.
- **`ClassificationStatus` is already taken, and the replacement is decided.**
  `capture_ui_state.dart:10` declares it as a UI state machine,
  `{idle, running, done, failed}`. The domain type is therefore
  **`ClassificationOutcome`**, `{ok, rejectedOod, failed}`, and the study and the
  handoff both declare it under that name. The two are not variants of one idea:
  the UI type tracks where a screen is in an operation, the domain type reports
  what an operation concluded. Giving them one name would force a prefixed import
  in the one file where both meet, the capture screen.

---

## 3. Lane A — application and shared libraries

### A1 — Image acceptance criteria library

**Record:** SPEC 0030 (**gate-approved 2026-08-01**, and implemented on
`feat/image-quality-acceptance-criteria`, which is not merged yet). Implementing
it surfaced three defects in the specification itself, each corrected in the
specification with its reason recorded, so the merged text differs from the one
approved at the Gate.
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
- Only the four calibrated criteria — blur, exposure, clipping, and effective
  resolution — can produce `blocking`. The remaining three (contrast, colour
  cast, specular) are `advisory` until calibrated against a real validation set.
  This read "three ... the remaining four" until implementing SPEC 0030 showed
  the count was wrong: it put `roiSidePx` on both sides at once, blocking as
  "effective resolution" and advisory as "the ROI-side report". The seven
  criteria map one-to-one onto the seven metrics, so the split is four and
  three. SPEC 0030 carries the correction and its reasoning.
- The ROI is defined once and reused by B2 and A3 rather than reimplemented.

### A2 and A3 — reassigned to the UI/UX terminal

The identifiers are kept so earlier references still resolve.

- **A2, the classification contract and schema v5** — their roadmap items 1 and
  15. Their SPEC 0031 is already gate-approved.
- **A3, the capture quality gate** — their roadmap item 6, which depends on
  SPEC 0030 from this workstream.

What this workstream still owes both: the calibrated band constants, published
in `spec.json` (C2), and the recalibrated quality thresholds. Both sides ship
provisional numbers today and both say so in their source.

### A4 — `spec.json` as the runtime contract

**Record:** SPEC, full tier. Closes #79; #116 lands with the UI/UX terminal's
item 1, which makes the label list single-source first.
**Depends on:** ADR 0012, and their item 1 for the label source.
**Paired with:** B3, which must emit exactly what this reads. **The schema is
defined in this spec and consumed by B3, not defined twice.**

`InferenceService` stops hardcoding labels, input size, and normalization, and
reads them from the tracked `assets/models/spec.json`. This file is owned by
this workstream, so the remaining failure-cause work lands here rather than in
their item 1.

**Acceptance criteria**

- The `spec.json` schema is written down in the spec: labels in model output
  order, input size, normalization mode, preprocessing, model version, dataset
  version, and the per-class band constants.
- A missing, malformed, or version-incompatible `spec.json` produces a
  distinguishable failure cause — never a silent fallback to hardcoded defaults.
  A silent fallback is how a train/serve skew survives review.
- **The six `null` conditions are separated.** Model absent, empty asset, decode
  failure, timeout, interpreter error, and isolate death each carry their own
  cause, so A5 can count them apart and the UI can eventually say which one
  happened. Their SPEC 0031 keeps returning `null` and derives `notAnalysed`
  from it, so this defect survives item 1 and is this workstream's to close.
  The domain type is called `ClassificationOutcome`, not
  `ClassificationStatus`: `capture_ui_state.dart:10` already uses the latter for
  a UI state machine.
- Zero string literals naming a texture class remain in `lib/`, enforced by a
  test that greps the tree. The label list currently exists in six independent
  copies with nothing asserting they agree.
- Dart-side preprocessing matches `ml/src/preprocess.py` exactly: centred square
  ROI, then resize, then the normalization named in `spec.json`. The current
  `img.copyResize(width: 224, height: 224)` squashes the aspect ratio and is a
  defect, not a convention.

### A5 — Local diagnostics

**Record:** SPEC, spec-lite. Implements ADR 0013.
**Depends on:** A4 for the failure causes worth counting apart.

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
  class, collection site, capture device, capture date, and **`setting`**
  (`bench` or `in_situ`). An earlier version of this criterion required a
  **moisture state** instead, on the reasoning that moisture confounds colour
  and is not recoverable retroactively. The project owner has since confirmed
  that photographs are taken on a bench after standard preparation, air-dried
  and sieved, and that moisture **cannot** be recorded. Bench preparation makes
  it near-constant, so the column would collect either nothing or a guess.
  `setting` replaces it: it is constant today too, but it is the axis every
  later question about the bench-to-field gap is asked along, and that gap is
  now the dominant unmeasured risk. SPEC 0033 carries the full decision.
- Admission is by A1's criteria: an image that would be `blocking` in the app
  does not enter the dataset. A divergence here reopens the exact gap ADR 0009
  closes.
- A dataset version is an immutable directory. Adding images creates `vN+1`; it
  never mutates `vN`. Every experiment record names the version it used.
- Splits are group-aware on sample id and stratified by class. Site and device
  are **recorded and reported per split, not held out**, and the validator
  states each split's composition along both axes.

  This criterion previously said stratification meant "a split cannot leak a
  location or a camera". That does not follow. Stratification balances how a
  factor is *distributed* across splits; only grouping prevents the same value
  appearing on both sides. Stratifying by site puts every site in train and in
  test, which is the opposite of holding one out, so the claim asserted a
  guarantee the algorithm does not provide. SPEC 0033 declines to force a
  site-held-out split for a stated arithmetic reason — holding a site out costs
  all of its samples from training and nobody yet knows how many sites exist,
  question 1 in §7 — so the axis is recorded now and the policy is decided when
  the count is known. `splits.json` is committed; the generator is deterministic
  given the seed.
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
  `setting`. Image counts alone do not size a split.
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
A1 (0030) ── done ──┬─ their item 6, the capture gate
                    └─ B2 ── dataset collection (human, weeks)
                                                     │
B1 (0032) ──────────── B2 ───────────────────────────┤
                                                     │
their item 1 ── A4 ─┬─ B3                            │
                    └─ A5                            │
                                                     ▼
                                          C0 ── GATE ── C1 ── C2 ── C3 ── release
```

Recommended immediate order for this workstream: **B1 → B2 → A4 → B3 → A5**,
with collection starting the moment B2 lands. B1 first because it is the only
item with no external dependency at all and E0 cannot be interpreted without it.
B2 next because it starts a human process that no amount of code shortens. A4
waits on the UI/UX terminal's item 1, which makes the label list single-source.

## 7. Decisions required from you

These are not work items. They are inputs that only you can supply, and Lane C
cannot be scheduled without them.

0. **Which capture modes does the product support, and does the dataset have to
   cover every one of them?** Opened 2026-08-06, **undecided**, and listed first
   because more of this map depends on it than on anything else here.

   The study, ADR 0009 and SPEC 0033 were all written assuming two fixed worlds:
   a bench-prepared collection and an in-situ deployment, with an unmeasured gap
   between them. The project owner has since stated that the product supports
   **both, switchable per case**, and that field use has more than one form —
   one candidate being a sample taken from 10 cm depth and spread over a sheet
   of paper. (That 10 cm is extraction depth. The protocol's ~20 cm is camera
   distance. Both can hold at once.)

   What it would change, so the cost of leaving it open is visible:

   - **`setting` is probably too small at two values.** Soil spread on white
     paper is a third visual condition, nearer the bench than raw ground.
   - **Risk R11 becomes measurable. It does not become mitigated.** A declared
     mode records the condition each photograph was taken under, so evaluation
     can report per mode instead of averaging incomparable rows together.
     Recording a condition is not evidence about it: the mitigation is still
     either covering every offered mode in the dataset, or refusing in the app
     the modes there is no data for. Knowing which rows are field rows tells you
     nothing about field accuracy until field rows exist.
   - **ADR 0009's rejection of segmentation was argued from an unknown
     background.** A paper backing makes the background known and controlled,
     so that rejection deserves re-examination for that mode rather than
     inheritance.
   - **A paper sheet is also a white reference, and a standard size is a scale
     reference.** White balance matters here more than it looks, because soil
     colour is signal rather than decoration, and a known sheet size would do
     what the coin currently does.
   - **Either the dataset covers every mode the app offers, or the app refuses
     the modes it has no data for.** Training on one mode while allowing
     several reopens the gap — declared this time rather than invisible, which
     is better but not solved.

   Sub-questions, none answered: the closed list of modes; whether the user
   declares the mode or the app infers it; whether one mode is canonical for
   training; and whether the sheet is a standard size.

1. **Who collects the dataset, at which sites, with which devices?** The split
   axes in B2 are only meaningful if there is more than one of each. Partly
   answered 2026-08-01 — **one** capture device — which makes the device axis
   constant in the dataset while it varies in deployment. Sites remain open.
2. **Is there access to the laboratory granulometry reports**, and what are the
   exact Embrapa grouping thresholds that produced the labels? Needed to build
   the cost-weighted confusion matrix — confusing Arenosa with Muito Argilosa is
   not the same error as confusing Média with Argilosa.
3. ~~**Can moisture state be recorded at collection time?**~~ **Answered
   2026-08-01: no, and it no longer matters.** Collection is on a bench after
   air-drying and sieving, which makes moisture near-constant by construction
   rather than merely unrecorded. The confound is removed, not deferred. What
   the same answer created is the bench-to-field domain gap, which is now the
   dominant unmeasured risk and is why no field-accuracy claim is supportable
   from this dataset. Kept here struck through rather than deleted, so the
   answer stays attached to the question it settles.
4. **What does one laboratory analysis cost, in money and turnaround?** It sets
   the realistic target N per class and decides whether active learning is worth
   building.
5. **Target N per class.** Without an answer, B2's protocol states a minimum
   derived from the split constraint alone, which is a floor, not a goal.

## 8. Coordination with the UI/UX terminal

Resolved:

- **Ownership** — settled in §2 above. They own the contract, the verdict, the
  capture gate, and the migration; this workstream owns `ml/`, `spec.json` at
  runtime, diagnostics, and all calibration.
- **Criteria count** — SPEC 0030 keeps seven metrics; four can block (blur,
  exposure, clipping, resolution) and three are advisory until calibrated, so
  nothing the UX design expected to pass can be rejected by an uncalibrated
  criterion.
- **`SoilTextureColors` label order** — theirs, in item 1. A4 later moves the
  source of truth to `spec.json`, which supersedes that fix rather than
  conflicting with it.
- **Band constants** — this workstream calibrates and publishes them in
  `spec.json` (C2). The UI reads them; it does not hardcode them. The 0.15 /
  0.50 / 0.65 thresholds in their SPEC 0031 are provisional on both sides and
  must be recalibrated after temperature scaling, not before.

What each side still owes the other:

- **To them, from here:** the calibrated band constants and quality thresholds,
  and a `spec.json` whose label order is authoritative once A4 lands.
- **To here, from them:** item 1, which makes the label list single-source and
  is A4's precondition, and item 15's persisted fields, which are what A5 counts.
- **Neither side has claimed** the `null` conflation in `inference_service.dart`
  until now. It is A4's, stated explicitly there because item 1 reads as though
  it covers the result type and does not.
