# ML Terminal Handoff

Short, current state of the vision/ML workstream for the other terminals.
Last updated: 2026-08-11. The ordered backlog with acceptance criteria lives in
`docs/architecture/ml-implementation-map.md`.

Full reasoning lives in `docs/architecture/soil-classification.md`, **with one
caveat worth reading before it**: that study predates the 2026-08-11 answers and
four of its premises are false — label traceability, the grouping thresholds,
moisture as a live confound, and field capture as the collection method. It
carries a supersession table at its head. Where it and ADR 0014 disagree, ADR
0014 wins.

**Ownership, settled 2026-08-01.** This workstream owns all of `ml/`, the
`spec.json` runtime contract, local diagnostics, and the calibration of every
threshold and band constant either side ships. The UI/UX terminal owns the
classification contract and verdict bands (their roadmap item 1, SPEC 0031),
wiring the quality gate into capture (item 6, which consumes SPEC 0030), and the
v4 → v5 migration (item 15). Neither owns UI/UX rework beyond that, or the
research agent. Full reasoning and what each side owes the other:
`ml-implementation-map.md` §2 and §8.

## Decisions taken

| Decision | Record |
|---|---|
| TFLite stays the only inference runtime; no Core ML, ONNX Runtime Mobile, or ExecuTorch | ADR 0008 |
| Target isolation is a fixed centred-square ROI plus model-free quality checks; no segmentation, no detector; background subtraction rejected on mechanism | ADR 0009 |
| One acceptance-criteria set governs both the dataset and the capture gate | ADR 0009 |
| Generative synthetic data (GAN, VAE, diffusion) deferred behind five named conditions and a downstream ablation | ADR 0010 |
| The released `.tflite` and its `spec.json` are tracked in git; experiment outputs stay ignored; a model update ships as an app release | ADR 0012 |
| Monitoring is local-first: aggregates on the device, nothing transmitted, no image or coordinate in telemetry under any setting | ADR 0013 |
| Task stays five-way classification of the Embrapa textural groups; no granulometry regression, no ordinal loss | Study §12.2 |
| The dataset is the laboratory's existing sample archive photographed on a fixed rig — 90 mm Petri dish, two background conditions, zero new analyses | ADR 0014 |
| Field-fresh material is **not** covered by the dataset. Today this is a stated accuracy limitation, not an enforced rule — nothing in the app can detect it | ADR 0014 |
| The target is a centred circle of known diameter, so ADR 0009's unknown-target premise is amended and the ROI shape becomes an E1 experiment | ADR 0014, ADR 0009 |
| Per-class sample targets are asymmetric; Siltosa is rare in the material and no effort fixes it | ADR 0014, SPEC 0033 |

## Hypotheses, not yet verified

1. Textural class is visually determinable from a 20 cm top-down RGB photograph.
   **Unproven, and everything depends on it.** Experiment E0 tests it against a
   label-shuffled control before any further investment.
2. Soil moisture confounds colour and may be what a model learns instead of
   texture. Not recorded anywhere in the current pipeline.
3. ImageNet pretraining transfers to a texture-statistics task with no object to
   localize.
4. The declared dataset counts in `ml/README.md:29-35` are unverifiable; the
   raw data is absent from the repository and from this machine. **Updated
   2026-08-11:** labelled physical samples with measured granulometry do exist,
   archived at the project's own laboratory. What is absent is the photography,
   not the material.
5. **New, and now the dominant one: the application has no way to establish
   scale.** The dataset is shot on a fixed rig with a 90 mm dish, so its
   millimetres per pixel is constant; the app is handheld with no dish. The
   precise gap is not that the frame lacks an object of known size — the
   collection protocol keeps the coin and onboarding instructs it — but that
   **nothing in the code reads one**, and ADR 0009 defers detection. A reference
   nobody reads is not a reference, and conflating the two would send the remedy
   in the wrong direction. On a task whose signal is particle size, that is a
   train/serve skew where both sides look correct. Unresolved by design — the
   three candidate resolutions are in ADR 0014 and the decision is registered as
   §7 question 6 in `ml-implementation-map.md`. It does not block collection. It
   blocks every claim about accuracy in a user's hands.

## Verified defects found

- Classification never runs in production: no `.tflite` asset exists, so
  `classify()` always returns `null` and every record is saved unclassified.
- Train/serve skew on EXIF orientation. The app bakes orientation via
  `img.copyResize` (`image-4.8.0/lib/src/transform/copy_resize.dart:33-35`);
  training ignores EXIF entirely (`ml/src/dataset.py:257-259`).
- `spec.json` is generated and never read; labels, input size, and normalization
  are hardcoded in `inference_service.dart` (#79, #116).
- `export.py` verifies TFLite parity against `np.random.rand` (`export.py:92`).
- Confidence is decorative: `ConfidenceLevel` gates nothing, and there is no
  inconclusive state.

## Contract other terminals consume

Reconciled with `docs/design/ux-2026/08-results-and-uncertainty.md`. **This
terminal produces evidence; the UI terminal decides presentation.**

> **Partly shipped, 2026-08-11 (PR #173, SPEC 0031).** What exists in `lib/` is
> narrower than the shape below, deliberately: `InferenceResult.distribution`
> (a `List<ClassScore>`, every class, ordered descending) plus a separate
> `ClassificationVerdict` with `conclusive`, `ambiguous`, `insufficient` and
> `notAnalysed`. There is **no** outcome enum, no `modelVersion`, no
> `datasetVersion`, no `qualityFlags` and no `inferenceMs` yet; those land with
> item A4 and the schema migration. The shape below is the target, not the
> present state.
>
> One constraint from that release is live and binding on the UI terminal's next
> spec: **no result surface may offer retry on `notAnalysed`** until A4 splits
> the six causes `classify` collapses into `null`, because it cannot know
> whether anything is retryable.

```dart
// NOT `ClassificationStatus`: capture_ui_state.dart:10 already declares that
// name for the capture screen's UI state machine, {idle, running, done, failed}.
enum ClassificationOutcome { ok, rejectedOod, failed }

class ClassScore {
  final String textureClass;
  final double probability;   // calibrated
}

class ClassificationResult {
  final ClassificationOutcome status;
  final List<ClassScore> distribution;  // all classes, descending; empty unless ok
  final String modelVersion;
  final String datasetVersion;
  final List<String> qualityFlags;      // acceptance criteria that failed
  final int inferenceMs;
}
```

- Classes: the five Embrapa textural groups in the order declared by
  `spec.json`. A negative class, if one is trained, never appears in
  `distribution` — when it wins, the status is `rejectedOod`. That is the
  "not soil" signal `06-capture-experience.md` §3 correctly reports as absent
  today.
- **`rejectedOod` is a reserved status, not a required one.** Whether that
  signal comes from a trained negative class or from the quality gate plus a
  threshold is still open, informed by E12. Handle the member; do not assume a
  producer emits it. The study's §24 question 5 carries the decision.
- **No `inconclusive` status.** Conclusive, ambiguous, and insufficient-evidence
  are bands the UI derives from top-1 and the top1−top2 margin. This terminal
  supplies the distribution, the calibration that makes the numbers mean what
  they say, and the per-class band constants, published in `spec.json` so both
  sides read one source.
- **Calibration changes what the numbers mean.** The constants in
  `08-results-and-uncertainty.md` §3 (0.70, 0.45, 0.15) must be calibrated after
  temperature scaling. Calibrating them against raw softmax and later enabling
  scaling would silently shift every band.
- `failed` covers model absent, decode failure, timeout, and interpreter error;
  those are separated in telemetry, not in the UI. It maps to *não analisado*.
- When `qualityFlags` is non-empty the UI must be able to name what failed, so a
  retake is actionable.
- Inference time is unmeasured. The 15 s value in `inference_service.dart:78` is
  a timeout, not an expectation.
- This replaces `InferenceResult?`, where `null` currently conflates at least six
  conditions.

### `TargetSignal`: no producer in phase one

`06-capture-experience.md` §3.1 requests a shape for target detection and
correctly refuses to simulate it. ADR 0009 defers detection and segmentation, so
nothing will construct `targetFound`, `targetCount`, or a detected
`regionOfInterest`, and those states stay dormant. The fixed centred-square ROI
in SPEC 0030 is **not** a substitute: it is a geometric convention applied
unconditionally to every image on both the training and the inference side, and
it carries no claim about what is inside it.

## Planned work

Scoped item by item, with acceptance criteria and dependencies, in
`docs/architecture/ml-implementation-map.md`. Summary:

| Lane | Content | Needs the dataset |
|---|---|---|
| A | Acceptance criteria library (SPEC 0030); `spec.json` at runtime (#79, #116); local diagnostics | No |
| B | Deterministic and fail-loud training (#80, #25, #81, #29, #28); the dataset protocol, manifest and split generator; export hardening (#29, #30) | No |
| C | Inventory and the E0 feasibility gate, then baseline and sweep, calibration and rejection, quantization | Yes |
| C4 | Conditional synthetic-data branch, only if ADR 0010's conditions hold | Yes |

**Three items are not in that table, because they are not this workstream's.**
Lane A originally claimed the `ClassificationResult` contract and the schema v5
migration (A2) and the capture quality gate (A3). The UI/UX terminal's
`docs/design/ux-2026/13-roadmap.md` already owned all three — it was simply not
in version control when this map was first drafted — and the project owner
settled the split on 2026-08-01 in favour of that roadmap. They are their
roadmap items 1, 15 and 6. The A2 and A3 identifiers are kept in the map so
earlier references still resolve, and the map's ownership section is
authoritative if this summary and it ever disagree again.

What this workstream still owes both sides across that boundary: the calibrated
band constants published in `spec.json`, and the recalibrated quality
thresholds. Both sides ship provisional numbers today and both say so in source.

Two things worth knowing from outside this workstream. First, most of Lanes A
and B need no images, so they proceed in parallel with collection. Second, **E0
is a real gate**: if the model cannot separate from a label-shuffled control,
Lane C stops and the product premise needs revisiting.

Spec and ADR numbers are assigned when a record is authored, never reserved in
advance — both terminals draw from one sequence and a reserved hole fails the
contiguity check on `main`.

## Files this terminal expects to touch

Owned outright: `ml/**`, `lib/core/services/inference_service.dart`,
`lib/core/services/image_quality/**`, `assets/models/**`.

Likely later: `lib/models/` (new `ClassificationResult`, shared label list),
`lib/models/confidence_level.dart` (thresholds re-derived after calibration),
`lib/core/theme/soil_texture_colors.dart` (consume the shared label list),
`lib/core/database/` (schema migration for status, quality flags, model and
dataset version).

## Coordination with the UI/UX terminal

`docs/design/ux-2026/` (untracked at the time of writing) covers the same ground
from the presentation side. It was read, not edited. Where the two designs met,
this terminal adopted theirs.

**Adopted from `06-capture-experience.md` §2.2-2.3 into SPEC 0030:**

- three verdicts (`ok` / `advisory` / `blocking`) instead of a two-state
  accepted/rejected model, so a marginal image can be analysed *and* flagged;
- the Laplacian computed on a downscaled copy. Their reason is cost; the
  stronger one is that Laplacian variance is resolution-dependent, so without a
  fixed downscale the same scene scores differently on a 12 MP and a 5 MP
  camera and no threshold is portable across devices. Pinned at 512 px on the
  ROI side;
- an analyzer failure yields an `unvalidated` verdict, never a block.

**Adopted from `08-results-and-uncertainty.md` §3:** the two-axis verdict model.
A high top-1 with a near-tie is still a near-tie, and one threshold cannot see
that. `inconclusive` was consequently dropped from the status enum above.

**Divergences, now resolved:**

1. **Criteria count.** SPEC 0030 keeps seven metrics; the UX gate names three
   signals. Four criteria can produce a `blocking` verdict — blur, exposure,
   clipping, and effective resolution — which matches those three signals,
   because the UX design's single "exposure" covers this specification's
   separate exposure and clipping criteria. The extra three (contrast, colour
   cast, specular) stay `advisory` until calibrated, so they cannot reject
   anything the UX design expected to pass. Colour cast matters more here than
   it looks: soil colour is part of the signal, so an uncorrected white balance
   is a real threat, not a cosmetic one.

   This listed four advisory criteria including ROI side, and three blocking,
   until implementing SPEC 0030 showed `roiSidePx` had been counted on both
   sides at once. The specification carries the correction.
2. **`SoilTextureColors` label order.** The UI/UX terminal owns the immediate
   fix (its spec P2-5). Item A4 in the map later moves the source of truth to
   `spec.json` under #79, which supersedes that fix rather than conflicting with
   it. One owner at a time.
3. **Band constants.** Calibrated once on this terminal's validation set, after
   temperature scaling, and published in `spec.json` (map item C2). The UI reads
   them; it does not hardcode them. The current 0.70 / 0.45 / 0.15 are
   hypotheses about raw softmax and will move.

## Potential integration conflicts

- **`lib/core/features/capture/`** — shared. The ROI overlay, the quality gate,
  the guided retake, and the override path all land here. SPEC 0030 deliberately
  touches none of it; the wiring is a follow-up spec that must be coordinated
  before either terminal edits the screen.
- **`lib/core/features/details/widgets/classification_header.dart`** — owned by
  UI/UX. The contract above is its input.
- **`lib/models/confidence_level.dart`** — both terminals plan to replace it.
  Its 0.80 / 0.60 thresholds are arbitrary today. Do not build new UI semantics
  on the present values.
- **A database migration** for the new record fields collides with any other
  schema work. Schema is at v4; coordinate before writing v5 (map item A2).
- **`.gitignore`** — ADR 0012 removes the `assets/models/*.tflite` and
  `assets/models/spec.json` entries. Both files become tracked. This unblocks
  #79 and #116.

## Dependencies

- Blocking Lane C: the dataset. Still absent from the repository — `ml/data/`
  holds only `splits/.gitkeep`, and `ml/models/v1` and `v2` hold only
  `.gitkeep`. **What changed on 2026-08-11 is the cost of removing that
  blocker, not the blocker itself:** the samples exist, labelled and analysed,
  in the laboratory archive, so producing the dataset is rig time rather than a
  collection campaign and it consumes no new laboratory analysis. The per-class
  inventory is still unknown, and it is the number that decides whether E0 can
  run five ways.
- Blocking every experiment: reproducible training (#80).
- Compute available: local machine plus free Kaggle/Colab tiers. This is what
  rules out training any generator from scratch.

## Open questions

Listed in `docs/architecture/soil-classification.md` §24; question 6 (artifact
delivery) is now answered by ADR 0012. The ones needing input from outside this
workstream are in `ml-implementation-map.md` §7. The one that still blocks
another terminal is when the schema v5 migration lands, since it collides with
any other schema work.
