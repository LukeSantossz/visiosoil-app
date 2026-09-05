# ML Terminal Handoff

Short, current state of the vision/ML workstream for the other terminals.
Last updated: 2026-09-03.

**Where the authority lives.** The tracked backlog is issues #178–#197. The
decisions are ADRs 0008–0018. The plan is
`docs/architecture/ml-implementation-map.md`. The 2026-07-30 study
`docs/architecture/soil-classification.md` has drifted — 44 of 95 verified
claims are not true as written (#189) — so **where a document and an issue
disagree, the issue is right**. This file points; it does not duplicate.

## What changed on 2026-08-25

The image set was delivered and audited, and it is not what the records
described. Five decisions followed in one day.

| | |
|---|---|
| **The dataset exists** | 221 photographs of **194 samples**: soil in a Petri dish, top-down, pale background. The laboratory number is in the filename, so grouping needs no extra record |
| **It is not a fixed rig** | Scale spans 5.73–14.93 px/mm, a factor of 2.6. At least two cameras. ADR 0014 is **Retired**; [ADR 0016](../adr/0016-dataset-is-the-existing-dish-archive-and-siltosa-is-out-of-v1.md) replaces it |
| **Siltosa holds 3 samples** | Below the floor of 30. **The first model classifies four classes** and the app declares the fifth absent |
| **Scale is measured, not assumed** | Dish rim in the dataset, A4 sheet in the app, both by classical operators. No reference found is a **refusal**. [ADR 0017](../adr/0017-scale-is-read-by-a-classical-operator-on-a-known-circle.md). **The dataset half is built and run**, [SPEC 0052](../specs/0052-read-the-dish-rim-and-recompute-the-canonical-scale.md): all 221 photographs read, none refused, canonical **0.1292 mm/px**, spread **4.83×** rather than the 2.6× measured before the HEIC session was readable |
| **The model sees greyscale patches** | Patches of ~21 mm at 160 px, overlapping by half, inset from the region boundary — 25 for a 90 mm dish, 9 at the refusal floor of ~70 mm. Their disagreement is an image-quality criterion, **not** a confidence. [ADR 0018](../adr/0018-model-sees-fixed-size-greyscale-patches-and-their-spread-is-a-quality-signal.md) |
| **The background gap largely closed itself** | A patch cut from inside the soil region is soil and nothing else, so dish-versus-paper stops mattering at the level the model sees. #192 drops to conditional, and the study's "severe" background rating is wrong |

**E0 is runnable and should not be run yet.** It was blocked on images for the
whole programme and no longer is — it is specified by SPEC 0044 and tracked as
**#216**, and the issue named here, #197, is closed. What now stands in front of
it is a number rather than a missing dependency: the capture-population probe
([SPEC 0055](../specs/0055-probe-whether-the-capture-population-is-predictable.md),
verdict in [docs/ml/capture-population-probe.md](../ml/capture-population-probe.md))
recovered the capture population from the same patches the arms see — **90 / 97
sample groups, Wilson 95 % lower bound 0.858 against a prior of 0.649**, with the
transported population `B` recovered **20 of 20**. Its pre-registered rule
re-opens **SPEC 0040 D6** by name, and both of D6's written options change which
photographs may train and therefore change the folds. E0 is about twenty hours of
compute; running it before the D6 decision risks spending all of it on a
partition the decision invalidates.

That verdict does **not** say the E0 result would be wrong. Recovering the
capture population is not the same as the texture arms exploiting it: the finding
is that the information is present in the representation, which makes D6 a
mitigation of unproven sufficiency.

## Decisions taken

| Decision | Record |
|---|---|
| TFLite is the only inference runtime | ADR 0008 |
| Fixed geometric region of interest and model-free quality checks; no segmentation, no learned detector. **A classical operator over an object of known size is not what this rejected** | ADR 0009, amended 2026-08-25 |
| Generative synthetic data deferred; zero of five conditions hold, and a sixth is added | ADR 0010, re-checked 2026-08-25 |
| Four-state verdict from margin and mass. **The app never shows nothing** — it always names the leading class, with a weak-evidence warning, an AI disclaimer, and advice to retake or consult a specialist | ADR 0011, amended 2026-08-25 |
| The released artifact and its `spec.json` are tracked in git | ADR 0012 |
| Monitoring is local-first; nothing transmitted | ADR 0013 |
| A classification reports an outcome and a named cause, never `null` | ADR 0015 |
| The dataset is the existing dish archive; Siltosa out of v1 | ADR 0016 |
| Scale read from a known-size object; no reference means refusal | ADR 0017 |
| Greyscale patches of fixed physical size; mean aggregates; dispersion is a quality criterion | ADR 0018 |
| No granulometry and no laboratory reference, anywhere in the project | ADR 0014, carried into ADR 0016 |
| Five-way classification of the Embrapa groups; no granulometry regression, no ordinal loss | Study §12.2 |

## Contract other terminals consume

`InferenceResult.distribution` (a `List<ClassScore>`, descending) plus
`ClassificationVerdict` with `conclusive`, `ambiguous`, `insufficient`,
`notAnalysed` — shipped by SPEC 0031. The target shape adds an outcome enum,
model and dataset versions, quality flags and inference milliseconds; those land
with SPEC 0035.

**Four things the UI/UX terminal should plan against.**

1. **The model emits four classes and the product names five.** `spec.json`
   becomes the label source with SPEC 0035, and that makes it a **release
   blocker**: `SoilTextureLabels.ordered` declares five and
   `resolveTextureLabel` refuses a four-class tensor, so a four-class model
   cannot run in the application at all until the labels come from the contract.
2. **A result surface never shows nothing.** ADR 0011's amendment: always name
   the leading class and its share; add a weak-evidence warning when the verdict
   is not `conclusive`; always state that the reading comes from an AI and can be
   wrong; when the share is low, tell the user to retake with better light or to
   consult a specialist. With four classes, chance is 0.25.
3. **Patch disagreement is an image-quality message, not a confidence.** It
   reads *the regions of this sample disagree — spread it more evenly and
   retake*. It has a different remedy from a weak reading and must not be merged
   into one number.
4. **Four new capture-flow requirements**, all theirs to design.
   **The framing rule changes completely**: the whole A4 sheet must be in frame,
   on a surface that contrasts with it, because the sheet is the scale reference
   — `onboarding_screen.dart:24-49` currently instructs a coin, 70 % fill and
   ~20 cm, and all three are now wrong. **The soil disc must be at least ~70 mm
   across**, which is the floor for nine patches; below it the app refuses. The
   user marks the **collection point** before preparing the sample, since the
   photograph may happen elsewhere and the coordinate must be the sample's
   origin. And the user declares whether the sample was **sieved**, with the app
   analysing either way and saying when the evidence covers sieved soil only.

5. **Two refusals the interface must carry copy for**: the sheet could not be
   found — retake showing the whole sheet, or move to a darker surface — and the
   soil region is too small — spread more soil. Both are new failure causes in
   ADR 0015's middle column, where retrying is the right response.

The standing constraint from ADR 0011 is unchanged: **no result surface may
offer retry on `notAnalysed` until SPEC 0035 lands**, because until then it
cannot know whether anything is retryable.

## Open defects, all tracked

**#196 and #179 are closed** and are no longer listed here; the table below is
what remains open.

| Issue | |
|---|---|
| #194 | The out-of-distribution score, **built for v1** — with Siltosa excluded it is the only guard against a confident wrong answer on silty soil |
| #178 | The training path does not pass `sample_ids`; grouping falls back to a filename regex that happens to match this archive |
| #180 | Neither downsample path anti-aliases; folded into A6 and closed by SPEC 0053's resample to the canonical scale |
| #185 | `Interpreter.fromBuffer` leaks the model on every classification |
| #187 | Calibration is scheduled before quantization; `spec.json` has no `temperature` or `quantization` field |
| #26, #29, #30, #188 | Checkpoint selection, export parity on real data, path resolution, calibration metrics |
| #79 | The contract is not read; SPEC 0035 is specified and unimplemented |
| #189 | The architecture study needs a resync |
| #180 | **Half open, and not a gate blocker.** Its Python half is resolved: `patches.resample_to_canonical` resizes through Pillow, which scales a filter's support by the reduction factor, so the canonical downsample is low-passed; and `preprocess.preprocess` — the `tf.image.resize(antialias=False)` the issue names — is off the patch path. The **Dart** half survives: `inference_service.dart` still uses `Interpolation.linear`. It belongs to A6's Dart half and is a **release** blocker |
| #229 | The `texture_class` axis of the spanning-group leak SPEC 0055 closed for the capture population. `v1` triggers neither, so it guards a future manifest |

## Order of work

**Rewritten 2026-09-03.** The list this replaces opened with "convert HEIC" and
ran E0 as issue #197. #196 and #179 are closed, #197 is closed, and two more
items have landed since, so following it would have queued work behind finished
dependencies. The map's §6 is the authority; this is its short form.

**Corrected 2026-09-05.** This list opened with #178 as "the remaining defect
that would bias E0". **#178 is closed**, and so is every other defect that was on
that list: nothing blocks the gate on defect grounds. #180's status was also
wrong here — see the correction under **Known status** below. What blocks the
gate now is a decision, not a defect.

1. **SPEC 0057** — the D6 sensitivity comparison: the descriptor arm run twice
   over one partition, with population `B` in the training sides and without,
   compared under a rule fixed before the run. About two hours. It exists
   because the probe demonstrated the capture population is **recoverable**,
   which is not the same as the texture arms **exploiting** it, and only a
   comparison of two trainings separates those.
2. **ADR 0021, the D6 decision** — written against SPEC 0057's number, choosing
   between the two options SPEC 0055 fixed in advance: population `B` leaves
   training entirely, or it is restricted to arms that provably cannot exploit an
   encoding signature. The Developer takes it.
3. **C0, SPEC 0044 (#216)** — run the gate: four arms, four classes, verdict
   committed either way. It waits on the ADR because both of D6's options change
   which photographs may train, therefore change the fold manifest, and a result
   pooled across two manifests is refused by construction.
4. **SPEC 0035**, then **A6's Dart half**, then #185. Both are release blockers
   and neither blocks the gate.
5. Everything else sits behind the C0 gate.

Done since this file was last rewritten: #196 (HEIC converted, SPEC 0040), #179
(BatchNorm, SPEC 0045), the four-class list (SPEC 0046), the evaluation protocol
(ADR 0020, SPEC 0042), the training environment (SPEC 0051), the canonical scale
(SPEC 0052) and **A6's Python half (SPEC 0053)** — training now scores a grid of
scale-normalised greyscale patches and averages them back into one prediction per
photograph.

**A6 opened a train/serve skew and has not closed it.** Training sees canonical
greyscale patches; `InferenceService` still resizes the whole frame to 224 and
keeps colour. That is deliberate — the Dart half needs SPEC 0035 — and it means
**no model may be released between SPEC 0053 and SPEC 0035**. A green training
run is not a shippable model until that closes.

## Limitations that travel with every number

Dry sieved bench material, so **no figure describes field-fresh soil**, and
re-wetting the archive is impossible so that gap has no collection remedy. Labels
are the folder and are not verified against the laboratory, so label noise is
unverifiable even in principle. Hue is discarded. Siltosa is absent. At
0.129 mm/px **silt and clay particles are not resolvable**, so whatever separates
the finer classes must come from aggregate appearance — and whether it exists at
all is what E0 asks. The test set holds 5 to 9 samples per class, so **no
per-class figure is supportable**.

## Files this terminal owns

`ml/**`, `lib/core/services/inference_service.dart`,
`lib/core/services/image_quality/**`, `assets/models/**`.

**Shared, and not edited from here without their spec:**
`lib/core/features/capture/`,
`lib/core/features/details/widgets/classification_header.dart`,
`lib/models/confidence_level.dart`, `lib/core/database/` migrations.
