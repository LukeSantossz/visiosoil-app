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
- Required metadata per sample: sample id, textural class, collection site,
  capture device, capture date, and **`setting`** (`dish` or `paper`).

  **No granulometry and no laboratory report reference**, by the project owner's
  decision of 2026-08-11, and the validator **rejects** a manifest carrying those
  columns rather than ignoring them. An earlier version of this criterion listed
  the laboratory reference as required and a same-day revision added the three
  percentages; both are withdrawn. What it costs is recorded in ADR 0014.

  **`setting` records presentation, not deployment state**, and the distinction
  is the correction ADR 0014 forces. This criterion previously read
  `bench | in_situ` and described the column as the bench-to-field axis. Both
  values now denote how air-dried sieved archive material is presented — in a
  90 mm Petri dish on a bench surface, or arranged as a disc of that size on
  paper — and neither denotes a field condition. `in_situ` is **rejected** by the
  validator rather than accepted-and-unused, because a silently admitted value is
  how an uncovered condition enters a dataset that reports itself as covering it.
  The bench-to-field axis has no column today; it returns with the deferred
  in-situ mode, alongside `moisture`.

  An earlier version of this criterion required a
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
  guarantee the algorithm does not provide.

  **This criterion is unchanged by the 2026-08-11 site answer, and the reason is
  that there are two splits, not one.** The *primary* split — the one B2 builds,
  the one training consumes — stays grouped by sample and stratified by class,
  with site and device recorded and reported, never held out. A *site-held-out
  evaluation* is a second, separate split computed for reporting generalisation
  to unseen origins; it does not replace the primary one and it is not built
  here. SPEC 0033 declined to force one on an arithmetic reason — holding a site
  out costs all of its samples from training and nobody knew how many sites
  existed, question 1 in §7. The count is now known to be many, so that
  evaluation moves from declined to the expected default **in C1**, where the
  policy is set from the measured site distribution this validator reports.
  Nothing about it changes what B2 must build. `splits.json` is committed; the
  generator is deterministic given the seed.
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

### C1 — Baseline and sweep (E1–E5, E13)

Real-only floor, corrected augmentation, compositing, backbone sweep
(MobileNetV2 / MobileNetV3 / EfficientNet-Lite0), loss sweep (weighted CE vs
focal). Exit gate: a recorded baseline in `ml/models/vN` with committed metrics.

Two deliverables added 2026-08-11, both consequences of ADR 0014. Without them
a run could complete every item above and still not produce what that ADR
promises:

- **E13, the ROI shape comparison** — centred square versus circular mask versus
  the square inscribed in the circle, against the E1 floor. ADR 0014 defers the
  ROI decision to measurement, so if this experiment is not run the decision is
  never made and the current square survives by default rather than by evidence.
- **The site-held-out evaluation.** B2 builds the primary split only — grouped
  by sample, stratified by class, with site recorded and never held out — and
  that is deliberate and unchanged. The unseen-origin measurement is a *second*
  split computed here for reporting, over the site distribution B2's validator
  reports. Its acceptance criterion: the recorded metrics include per-class
  accuracy on at least one held-out origin, or a written statement of why the
  measured site distribution does not support one.

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

**Answered 2026-08-11.** Questions 0, 1, 2 and 5 are settled below, question 3
was already settled, and question 4 has stopped blocking. The protocol that
follows is ADR 0014, which also forces an amendment to ADR 0009 and a revision of
SPEC 0033. One **new** question was created by the answers and is listed as
question 6; it is now the one that matters most.

6. **How does the application establish scale?** Opened 2026-08-11, **undecided**,
   and listed first because it is the only unresolved input and because it
   governs whether any deployment accuracy claim is supportable.

   Textural class is a statement about particle size, and particle size in an
   image is meaningless without a known scale — coarse grains far away and fine
   grains close produce the same pixels. Scale is a precondition for the signal,
   not a nuisance variable.

   The archive is photographed on a fixed rig with a 90 mm Petri dish, so every
   `dish` row has the same millimetres per pixel. The application is handheld,
   uses no dish, and — this is the precise gap — **nothing in it reads a scale
   reference even when one is present**. The collection protocol does keep the
   coin, and onboarding does instruct it, so the frame may well contain an object
   of known size; no code detects it, measures it, or normalises anything by it,
   and ADR 0009 defers detection. A reference nobody reads is not a reference.

   **The dataset is therefore at its strongest on exactly the axis where
   deployment is weakest, and both sides look correct**, which is what makes this
   the dominant skew rather than a detail.

   Three resolutions, none free, set out in full in ADR 0014:

   - **make the coin usable** — the object is already in the protocol and in the
     onboarding copy, so what is missing is the detector that recovers
     millimetres per pixel from it, plus the user compliance to place it. This is
     the cheapest of the three in physical terms and the most expensive in what
     it reopens: ADR 0009 deferred detection outright;
   - scale-invariant training, deliberately discarding absolute particle size,
     which is honest and throws away part of the signal;
   - enforced framing, constraining distance without measuring it, depending on
     compliance that nothing verifies.

   This does **not** block collection: every resolution is compatible with the
   archive being photographed as specified. It blocks any statement about how the
   model performs in the user's hands.

   One cheap partial fix is taken regardless: the `paper` condition arranges its
   disc against a 90 mm template, so the dataset does not acquire unrecorded
   scale variation of its own.

0. ~~**Which capture modes does the product support, and does the dataset have to
   cover every one of them?**~~ **Answered 2026-08-11.** Two conditions, both on
   air-dried sieved archive material: `dish`, soil in a 90 mm Petri dish on a
   bench rig, and `paper`, the same soil arranged as a disc of that size on a
   paper sheet without the dish. In-situ is deferred.

   **The dataset does not cover field-fresh material, and the app must not treat
   it as analysable.** The `paper` condition varies the background, not the
   physical state of the soil; fresh soil from 10 cm depth is moist and unsieved
   and holds aggregates. Reading the two values as two use cases is the specific
   over-reading ADR 0014 and SPEC 0033 both warn against.

   One correction is worth carrying forward, because it changes what may be
   concluded. The original analysis expected a paper backing to reopen ADR 0009's
   rejection of segmentation by making the **background** known and controlled.
   That pointed at the right premise for the wrong reason: what fell was the
   **target shape** being unknown, not the background. A known background would
   argue for segmentation; a known shape argues only for fixed geometry, which is
   far cheaper and stays inside what ADR 0009 already permits.

   > **The block below is historical and non-authoritative.** It is the analysis
   > as written on 2026-08-06, before any answer existed, kept so the reasoning
   > that produced the question survives alongside its answer. **Every claim in
   > it is superseded by the answer above and by ADR 0014**, including its
   > statements that the product supports both bench and field modes, that
   > `setting` is too small at two values, and that the mode list is undecided.
   > Do not cite it.

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

1. ~~**Who collects the dataset, at which sites, with which devices?**~~
   **Answered.** Devices: **one**, answered 2026-08-01, so the device axis is
   constant in the dataset and varies in deployment — an unmeasurable limitation
   by construction. Sites: **many**, answered 2026-08-11, because the laboratory
   serves many clients and the archive spans their origins.

   The site answer expires SPEC 0033's reason for declining a site-held-out
   split, which was stated as "with two sites it is unaffordable; with ten it is
   the right default". It moves to the expected default, implemented in C1.

   **One condition is not guaranteed by the answer and must be checked:** the
   origin has to be recoverable per sample from the laboratory record. If it is
   not, the axis exists in the material and not in the manifest, and nothing can
   split along it.
2. ~~**Is there access to the laboratory granulometry reports**, and what are the
   exact Embrapa grouping thresholds that produced the labels?~~ **Closed
   2026-08-11, and not by an answer to what it asked.** The project owner decided
   that **no granulometric data is linked into the classification process and the
   reports are not supplied to it.** Both halves of the question are therefore
   moot: the access exists and will not be used, and the thresholds are not
   needed by anything, since nothing checks a class against percentages it does
   not have.

   This question is left in place rather than deleted because what it was for is
   now a permanent limitation rather than a pending input. The cost-weighted
   confusion matrix it existed to enable **is not buildable**, so every confusion
   weighs the same in evaluation. Three more consequences travel with that, all
   on evaluation rather than training, and all recorded in ADR 0014 and
   SPEC 0033: label noise is unbounded, boundary samples cannot be told apart
   from model failures, and coverage is a per-class tally rather than a map of
   the textural triangle.

   A first draft of the 2026-08-11 records inferred the opposite from "the
   laboratory is ours" and made granulometry a required column. That inference
   was wrong and has been reverted. Access existing and access being used are
   different things.

   This is the answer with the widest consequences in this list. Granulometry
   moves from optional to required in the manifest, which makes three things
   possible that were previously written off: labels can be checked against the
   measurement that produced them, so label noise becomes measurable rather than
   an unbounded ceiling; boundary samples become identifiable, so an `ambiguous`
   verdict on one can be measured as correct instead of counted as an error; and
   dataset coverage becomes a map of the textural triangle rather than a tally
   per class.

   **The thresholds sub-question survives**, narrowed: which exact grouping
   thresholds the laboratory applies still has to be written down, because the
   verification criterion in SPEC 0033 checks a declared class against its own
   percentages and cannot do that without them.
3. ~~**Can moisture state be recorded at collection time?**~~ **Answered
   2026-08-01: no, and it no longer matters.** Collection is on a bench after
   air-drying and sieving, which makes moisture near-constant by construction
   rather than merely unrecorded. The confound is removed, not deferred. What
   the same answer created is the bench-to-field domain gap, which is now the
   dominant unmeasured risk and is why no field-accuracy claim is supportable
   from this dataset. Kept here struck through rather than deleted, so the
   answer stays attached to the question it settles.
4. **What does one laboratory analysis cost, in money and turnaround?**
   **No longer blocking, 2026-08-11.** The dataset is an archive photographed and
   consumes **zero** new analyses, so this stops gating collection. It still
   matters, and is kept open rather than struck through, for two later decisions:
   how much further collection costs — particularly for the in-situ mode and for
   any attempt to fill the thin regions of the textural triangle — and whether
   active learning pays for itself, which is a comparison against exactly this
   number.
5. ~~**Target N per class.**~~ **Answered 2026-08-11: ~150 per class on average,
   explicitly asymmetric.** One photograph per sample per condition, so a sample
   yields two images and remains one split group.

   **Siltosa is expected to fall short, and the expectation is not a
   measurement.** Silty soils are uncommon across much of the Brazilian soil
   population, so any shortfall would be a property of the material rather than
   an effort problem. But nobody has counted the archive, so what is fixed now is
   the *policy* — a declared per-class target, class weighting, and a per-class
   rejection threshold for Siltosa if it is thin — **conditional on the C0
   inventory**, which may equally show the uniform target is attainable after
   all. ADR 0014 sets out the three inventory outcomes and what each triggers.
   Treating the expectation as settled would risk under-targeting a class that is
   actually available.

   This does not relax SPEC 0033's reduced-class E0 rule; it makes it likely to
   bind. If Siltosa clears the 30-sample floor, E0 runs five ways as specified. If
   it does not, E0 runs on the classes that clear it, reports which were excluded,
   and **does not authorise Lane C** — a positive result on the easy classes
   bounds nothing.

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
