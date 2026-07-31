# ML Terminal Handoff

Short, current state of the vision/ML workstream for the other terminals.
Last updated: 2026-07-30. Full reasoning lives in
`docs/architecture/soil-classification.md`.

This terminal owns: computer vision, real and synthetic data, training, image
processing, mobile inference, calibration, model monitoring. It does not own
UI/UX rework or the research agent.

## Decisions taken

| Decision | Record |
|---|---|
| TFLite stays the only inference runtime; no Core ML, ONNX Runtime Mobile, or ExecuTorch | ADR 0008 |
| Target isolation is a fixed centred-square ROI plus model-free quality checks; no segmentation, no detector; background subtraction rejected on mechanism | ADR 0009 |
| One acceptance-criteria set governs both the dataset and the capture gate | ADR 0009 |
| Generative synthetic data (GAN, VAE, diffusion) deferred behind five named conditions and a downstream ablation | ADR 0010 |
| Task stays five-way classification of the Embrapa textural groups; no granulometry regression, no ordinal loss | Study §12.2 |

## Hypotheses, not yet verified

1. Textural class is visually determinable from a 20 cm top-down RGB photograph.
   **Unproven, and everything depends on it.** Experiment E0 tests it against a
   label-shuffled control before any further investment.
2. Soil moisture confounds colour and may be what a model learns instead of
   texture. Not recorded anywhere in the current pipeline.
3. ImageNet pretraining transfers to a texture-statistics task with no object to
   localize.
4. The declared dataset counts in `ml/README.md:29-35` are unverifiable; the
   raw data is absent from the repository and from this machine.

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

```dart
enum ClassificationStatus { ok, rejectedOod, failed }

class ClassScore {
  final String textureClass;
  final double probability;   // calibrated
}

class ClassificationResult {
  final ClassificationStatus status;
  final List<ClassScore> distribution;  // all classes, descending; empty unless ok
  final String modelVersion;
  final String datasetVersion;
  final List<String> qualityFlags;      // acceptance criteria that failed
  final int inferenceMs;
}
```

- Classes: the five Embrapa textural groups in the order declared by
  `spec.json`, plus a negative class that never appears in `distribution` —
  when it wins, the status is `rejectedOod`. That is the "not soil" signal
  `06-capture-experience.md` §3 correctly reports as absent today.
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

| Phase | Content |
|---|---|
| 0 | Global seed (#80); inventory of whatever partial dataset exists; feasibility probe E0 |
| 1 | Acceptance criteria library in Dart and Python (SPEC 0030), then the capture gate wiring |
| 2 | Remaining pipeline corrections: #26, #25, #81, #29, #30, #28 |
| 3 | Baseline and architecture sweep |
| 4 | Calibration and rejection |
| 5 | Quantization and the `spec.json` contract (#79, #116) |
| 6 | Telemetry |
| C | Conditional synthetic-data branch, only if ADR 0010's conditions hold |

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

**Divergences to resolve before either side implements:**

1. **Criteria count.** SPEC 0030 defines seven metrics; the UX gate names three.
   The extra four (contrast, colour cast, specular, ROI side) are `advisory`
   only until calibrated, so they cannot block anything the UX design expected
   to pass. Colour cast matters more here than it looks: soil colour is part of
   the signal, so an uncorrected white balance is a real threat, not a cosmetic
   one.
2. **`SoilTextureColors` label order.** `08-results-and-uncertainty.md` §2
   claims the fix in its spec P2-5; this terminal listed it under #116. One
   owner, not two — proposing the UI/UX terminal takes it, since #79 will later
   move the source of truth to `spec.json` on this side anyway.
3. **Band constants.** They are hypotheses on both sides today. They must be
   calibrated once, on this terminal's validation set, after temperature
   scaling, and published in `spec.json`.

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
  schema work. Schema is at v4; coordinate before writing v5.
- **`assets/models/` and `.gitignore`** — whether the artifact and `spec.json`
  are tracked in git or produced by CI is undecided and blocks #79 and #116.

## Dependencies

- Blocking everything: the dataset. Absent or partial today.
- Blocking every experiment: reproducible training (#80).
- Blocking the runtime contract: the artifact-tracking decision above.
- Compute available: local machine plus free Kaggle/Colab tiers. This is what
  rules out training any generator from scratch.

## Open questions

Listed in `docs/architecture/soil-classification.md` §24. The two that block
other terminals: how the model artifact is delivered, and when the schema
migration for the new result fields lands.
