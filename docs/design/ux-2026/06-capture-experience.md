# Assisted Capture

## 1. What is and is not possible today

The app does not own a camera. `image_picker` hands control to the operating
system's camera application and receives a file back. Between the user tapping
the shutter and the file arriving, the app has no frames, no preview surface,
and no ability to draw anything.

Every live-assistance feature — framing guide, region of interest, distance
indicator, stability indicator, blur warning, low-light warning, approach
guidance, target confirmation, capture lock, automatic capture — requires a
preview the app renders itself. None of them is achievable without replacing
`image_picker` with the `camera` package.

The design system has already drawn that screen (`CaptureScreen.jsx`: dark
canvas, corner-bracket guide, hint line, large shutter). It is a commitment the
code cannot currently honour.

**Decision (taken with the product owner): phase the work.** Phase 1 delivers
everything achievable without a viewfinder. Phase 2 introduces one.

## 2. Phase 1 — guidance before, validation after

### 2.1 Before: the capture guide

Content, taken from the design system's `CaptureGuideScreen`:

| # | Step | Body |
| --- | --- | --- |
| 1 | Limpe a superfície | Remova folhas, pedras e restos vegetais antes de fotografar |
| 2 | Mantenha ~20 cm | Câmera paralela ao solo, sem inclinar o aparelho |
| 3 | Luz natural difusa | Evite sombras fortes e não use flash direto sobre a amostra |
| 4 | Preencha a guia | Enquadre o solo dentro das bordas marcadas no visor |

Plus an "Evite" pair: solo encharcado, sombra do corpo.

**Timing is the substantive change.** Today this content lives in onboarding,
shown once on first launch — the moment the user has the least intent to
photograph anything — and afterwards only from Settings. It moves to the first
capture, and afterwards is reachable on demand from a "Como capturar" link on
the analysis screen.

The current three-step onboarding (framing, lighting, angle) is superseded by
these four. Onboarding retains only value framing and permission priming.

**Note on step 4.** "Preencha a guia" refers to a guide that phase 1 does not
draw. The phase-1 copy must be adjusted to describe framing without promising an
on-screen guide, and restored to the design-system wording when phase 2 lands.
This is recorded as an acceptance criterion in `13-roadmap.md`.

#### Unresolved: the guide drops two rules the dataset is collected under

**Raised by the reconciliation with SPEC 0030. It needs a joint decision.**

The current onboarding declares a capture protocol with five rules
(`onboarding_screen.dart:24-49`): a coin for scale, soil filling at least 70 %
of the frame, diffuse natural light, no flash, top-down at roughly 20 cm. SPEC
0030's problem statement is built on that protocol — the dataset is collected
under it, and ADR 0009's whole strategy is to *enforce* it rather than
compensate for its absence.

The design system's `CaptureGuideScreen`, which §2.1 above adopts, has four
steps and **contains neither the coin nor the 70 % fill**.

So replacing the onboarding content with the design-system guide would quietly
delete two rules of the protocol from the only place the user ever reads it,
while the dataset continues to be collected under them. That reopens the
subpopulation gap ADR 0009 exists to close — through the interface, and
invisibly.

Three ways out:

1. **Add both rules to the guide** as steps 5 and 6, or fold them into existing
   steps. Faithful to the protocol; makes the guide longer than the design
   system's.
2. **Drop them from the protocol and from collection.** Only defensible if
   neither rule is actually load-bearing — the coin is not measured by anything
   today, and ADR 0009 explicitly declines to measure the 70 % fill because it
   would need foreground separation. That is an argument that they are already
   inert.
3. **Keep the coin, drop the fill.** The fill is unmeasurable by decision; the
   coin is the one that unlocks a real scale if detection ever lands, which
   ADR 0009 names as the strongest argument for a detector.

**This terminal's recommendation is 3**, and it is not this terminal's to settle
alone: rule 2 would change what the ML terminal collects. Recorded here and in
`13-roadmap.md` as a cross-terminal decision blocking spec 5.

### 2.2 After: the quality gate

**This section was written before SPEC 0030 existed and has been reconciled
with it.** The vision terminal's ADR 0009 and SPEC 0030 adopt this document's
verdict model, its hypothesis stance on thresholds and its false-block
asymmetry, and deliver the analyzer as a library. What follows is therefore no
longer a proposal — it is the contract this terminal consumes, plus the parts
SPEC 0030 explicitly leaves to the interface.

**Produced by SPEC 0030**, as `lib/core/services/image_quality/`:
`ImageQualityCriteria`, `ImageQualityReport`, `ImageQualityAnalyzer.analyze()`.
A pure function of pixels and criteria — no I/O, no isolate, no state. It uses
`image ^4.3.0`, already a dependency. A Python twin and a committed golden file
keep the dataset audit and the app gate from diverging.

#### Region of interest

The ROI is the **largest centred square** of the source, taken after EXIF
orientation is baked. Every metric is computed over the ROI only.

This matters to the interface in a way that is easy to miss: the ROI is what
gets measured, and — once the follow-up applies it to preprocessing — what gets
classified. **Any framing guide this terminal draws must be that same centred
square.** A guide whose aspect or position differs from the ROI would show the
user one region and analyse another.

#### Metrics

Seven, all model-free arithmetic over the ROI:

| Metric | What it catches | Can block in phase 1 |
| --- | --- | --- |
| `blurScore` | Out of focus, motion blur | **Yes** |
| `meanLuminance` | Too dark or too bright | **Yes** |
| `clippedFraction` | Burnt-out or crushed detail | **Yes** |
| `roiSidePx` | Too few pixels to work with | **Yes** |
| `contrastScore` | Flat, washed out | Advisory only |
| `colorCastScore` | Whole photo tinted | Advisory only |
| `specularFraction` | Flash or hotspot on the surface | Advisory only |

Four are advisory-only until they are calibrated against real images. Blocking
on an uncalibrated criterion is how a gate starts refusing legitimate work.

`blurScore` is computed on a fixed 512 px downscale of the ROI. This document
originally gave cost as the reason; SPEC 0030 supplies a better one, and it is
the one that should be cited: Laplacian variance is resolution-dependent, so the
same scene at 12 MP and at 5 MP scores differently, and a threshold calibrated
on one device would be wrong on another. The fixed downscale is what makes the
score thresholdable at all.

#### Verdicts

Four, not three. `unvalidated` is promoted from a behaviour to a **verdict
value**, so a caller cannot forget to handle it:

| Verdict | Behaviour |
| --- | --- |
| **`ok`** | Proceed to classification silently |
| **`advisory`** | Proceed; attach the flags to the result and to the saved record |
| **`blocking`** | Do not classify. Name the defects. Retake as primary, "registrar assim mesmo" as secondary |
| **`unvalidated`** | The analyzer threw. Proceed with an advisory noting the check did not run |

**The blocking threshold is deliberately conservative.** A false block costs
more than a flagged bad analysis: it refuses work the user actually did, in a
field, on a sample they may not be able to revisit. ADR 0009 states the same
constraint from the other side — "a gate without an escape is a way to stop an
agronomist from working" — and makes the override path mandatory.

**All thresholds are provisional.** SPEC 0030 ships engineering starting points
labelled as such in the source, because no real images exist to calibrate
against. `ImageQualityCriteria` is injectable so recalibration does not touch
the analyzer.

### 2.3 What SPEC 0030 leaves to this terminal

Its scope section excludes, by name: any change to `capture_screen.dart`, the
capture UI, a viewfinder overlay, the retake flow, the override path, and
**persistence of quality flags on `SoilRecord`**. ADR 0009 nonetheless requires
that "the record stores which criteria failed". That persistence is therefore
this terminal's, and it belongs in the same spec that wires the gate.

Three interface obligations follow from the report's shape:

1. **Name every failure, not the first.** The report lists all failing criteria
   with measured values and margins, specifically so the user can fix everything
   in one retake. An interface that surfaces only the first defect wastes that
   and costs the user a second trip.
2. **Show the margin, not just the failure.** "Muito escura" is less useful than
   a statement that conveys how far off it was, and the margins are already in
   the report.
3. **Persist the flags.** A record saved through the override carries which
   criteria failed, so a later reading of that record is not more confident than
   the capture was — the same principle as persisting the distribution in
   `08-results-and-uncertainty.md` §5.

## 3. What phase 1 must not do

Two of the states requested in the brief have **no available signal**:

- **Target not found** — the classifier is single-label over the whole frame.
  It has no notion of a target being present or absent. Softmax over five soil
  textures on a photograph of a wall produces a confident-looking distribution
  over soil textures, because the model was never given an "not soil" option.
- **Multiple targets** — there is no detector and no segmentation. Nothing
  counts anything.

Neither may be simulated. A colour-histogram heuristic, a "does this look
brown enough" check, or a saturation threshold standing in for target detection
would be inventing precision the system does not have — the exact failure the
brief prohibits.

**ADR 0009 reaches the same conclusion from the modelling side and endorses this
constraint by name.** It rejects segmentation, detection and background
subtraction for phase one, and states that the fixed ROI "does not simulate
them — it is a geometric convention applied unconditionally, carrying no claim
about what is inside it", leaving `TargetSignal` without a producer, "which is
the correct state". The two terminals agreed independently; the constraint below
is now joint, not unilateral.

The ADR does record one path back: the coin the capture protocol already asks
for would yield a real millimetres-per-pixel scale if detected, which is its
strongest argument for a detector and the reason detection is deferred rather
than discarded.

Their UI contracts are specified below as hypotheses so that the interface is
ready when a signal exists, and so the vision terminal knows what shape is
expected.

### 3.1 Hypothetical contract — awaiting the vision terminal

```dart
/// HYPOTHESIS — no producer exists. Do not implement a stand-in.
class TargetSignal {
  final bool targetFound;
  final int targetCount;
  final Rect? regionOfInterest;   // normalised to the frame
  final double detectionScore;
}
```

Consuming states, ready but dormant:

| Signal | State | Primary | Secondary |
| --- | --- | --- | --- |
| `targetFound == false` | "Nenhuma amostra de solo identificada" | Retake | Record anyway |
| `targetCount > 1` | "Mais de uma amostra no enquadramento" | Retake framing one sample | Analyse the largest |
| `regionOfInterest != null` | Crop to the region before inference | — | — |

Until a producer exists, these states are unreachable and no code path
constructs a `TargetSignal`.

## 4. Phase 2 — the in-app viewfinder

Its own spec, gated separately. Recorded here so phase 1 does not paint it into
a corner.

**Introduces** the `camera` package — the only new dependency this dossier
recommends. Full evaluation in `11-libraries.md`.

**Adds** a rendered preview and therefore the ability to draw:

| Element | Behaviour |
| --- | --- |
| Framing guide | Corner brackets, per the design system's `CaptureScreen` |
| Region of interest | The guide's interior is what gets cropped and classified |
| Distance hint | Derived from focus distance where the platform exposes it; **omitted where it does not**, rather than estimated |
| Stability | Accelerometer variance over a short window |
| Blur advisory | Live Laplacian variance on downscaled preview frames |
| Low-light advisory | Live mean luminance |
| Capture lock | The shutter disables while a blocking condition holds, with the reason stated |
| Manual versus automatic | Manual by default. Automatic capture only after the live signals have been calibrated in the field; an auto-shutter that fires on a bad frame is worse than no auto-shutter |

**Explicitly out of scope, permanently:** gallery selection. The product is
camera-only by design, and phase 1 removes the copy that currently implies
otherwise.

**Risks carried into that spec:** camera lifecycle across backgrounding and
permission revocation; iOS parity; widget-test difficulty (a camera preview is
not testable in the widget harness, so the frame-analysis logic must be
extracted behind a seam that is); frame throughput on low-end devices; battery.

## 5. Acceptance criteria, phase 1

- `guide_shown_before_first_camera` — the capture guide appears before the
  camera on the first capture and not on subsequent ones; it remains reachable
  from the analysis screen.
- `no_empty_capture_screen` — `/capture` never renders without an image;
  reaching it without one re-enters the camera or returns home.
- `no_gallery_copy` — no string in the capture flow implies image selection
  from a gallery.
- `quality_blocks_name_every_defect` — a blocking verdict lists **every** failing
  criterion from the report, not the first, and offers both retake and
  record-anyway.
- `quality_failure_is_not_a_block` — an `unvalidated` verdict lets classification
  run and carries the advisory that the check did not run.
- `quality_flags_persist` — a record saved through the override stores which
  criteria failed, and reopening it shows them.
- `guide_matches_roi` — any framing guidance drawn by the interface describes the
  largest centred square, matching SPEC 0030's ROI.
- `no_simulated_target_detection` — no code path infers target presence or
  count from image statistics.
- `protocol_rules_are_not_silently_dropped` — the capture guide states every rule
  the dataset is collected under, or the collection protocol was changed by a
  recorded joint decision.
