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

### 2.2 After: the quality gate

Runs on the returned still, in the existing isolate pattern, using the `image`
package which is **already a dependency**. No new package.

| Signal | Method | Purpose |
| --- | --- | --- |
| Sharpness | Variance of the Laplacian over a downscaled greyscale copy | Detect motion blur and focus failure |
| Exposure | Mean luminance plus the fraction of pixels clipped at either end | Detect underexposure, overexposure, harsh shadow |
| Resolution | Shorter side in pixels | Detect an image below the model's input requirements |

**Three verdicts:**

| Verdict | Behaviour |
| --- | --- |
| **Ok** | Proceed to classification silently |
| **Advisory** | Proceed to classification; attach the advisory to the result and to the saved record |
| **Blocking** | Do not classify. Name the defect. Offer retake as primary, "registrar assim mesmo" as secondary |

**The blocking threshold is deliberately conservative.** A false block costs
more than a flagged bad analysis: it refuses work the user actually did, in a
field, on a sample they may not be able to revisit. When the two error types
must be traded off, prefer to admit a marginal image and flag it.

**All thresholds ship as hypotheses.** None is derived from data. They must be
calibrated against the ML terminal's validation set, and the calibration
procedure — sweep thresholds against known-good and known-bad captures,
choose the point where the false-block rate approaches zero — belongs in the
implementing spec.

### 2.3 Failure of the gate itself

If quality analysis throws or times out, the image is treated as
**unvalidated**, not as invalid. Classification proceeds with an advisory noting
that the check did not run. A crashed checker must never block a valid sample.

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
- `quality_blocks_name_the_defect` — a blocking verdict states which check
  failed, and offers both retake and record-anyway.
- `quality_failure_is_not_a_block` — when the quality analysis itself throws,
  classification still runs and the result carries an unvalidated advisory.
- `no_simulated_target_detection` — no code path infers target presence or
  count from image statistics.
