# Libraries and Frameworks Evaluated

## 1. Standing rule

Every new dependency must state: the problem it solves, the benefit, the bundle
impact, compatibility, maintenance status, licence, risk, and the alternative
without a dependency. If the no-dependency alternative is adequate, it wins.

## 2. Headline result

**Phase 1 requires no new dependency.** Every capability this dossier specifies
for roadmap specs 1 through 13, and for spec 15, is reachable with the SDK and
packages already in `pubspec.yaml`. Only spec 14 introduces one.

One new dependency is recommended, for phase 2 only: `camera`.

## 3. Needs mapped to existing capability

| Need | Solution | Already present |
| --- | --- | --- |
| Image quality analysis | Delivered by SPEC 0030 on `image` 4.3 — decode, greyscale, resize, pixel access | Yes, used by `InferenceService` preprocessing |
| Haptics | `flutter/services` `HapticFeedback` | SDK |
| Componentisation | Plain widgets under `lib/core/widgets/` | Yes |
| Gestures | `InkWell`, `GestureDetector`, `InteractiveViewer` | SDK |
| Animation | `AnimatedSwitcher`, `AnimatedSize`, `AnimationController`, `AppMotion` tokens | SDK plus existing tokens |
| Accessibility | `Semantics`, `MergeSemantics`, `SemanticsService`, `MediaQuery` | SDK |
| State | `flutter_riverpod` 3.3 | Yes |
| Bottom sheets, modals, dialogs | `showModalBottomSheet`, `showDialog`, themed in `AppTheme` | SDK |
| Toasts | `SnackBar`, themed | SDK |
| Navigation | `go_router` 17.1 | Yes |
| Data visualisation | `TextureScale` is a five-segment bar | SDK |
| Skeletons | Placeholder containers plus `AnimatedSwitcher` | SDK |
| GenUI | A pure Dart function over a compiled registry | No dependency by design |

## 4. Evaluated and rejected

### `shimmer`

- **Problem it would solve** — animated loading placeholders.
- **Rejected because** the design system permits exactly one looping animation,
  the spinner, and prohibits decorative motion. A travelling highlight is both.
- **Alternative** — static placeholder blocks with a crossfade to content.

### `flutter_animate`

- **Problem it would solve** — terser animation authoring.
- **Rejected because** it is convenience, not capability. Everything in
  `09-microinteractions.md` is expressible with the SDK. Its ergonomics
  encourage chained decorative effects, which the design system forbids, and it
  would add a second motion vocabulary alongside `AppMotion`.
- **Alternative** — one shared `StaggeredReveal` widget.

### `lottie`

- **Problem it would solve** — richer illustration in onboarding and empty
  states.
- **Deferred, not rejected.** The design system's motion guidelines describe its
  CSS demos as built "no espírito Lottie, prontos para trocar por `.json` reais
  quando existirem". No such assets exist. Adding the runtime before the assets
  is adding weight for nothing.
- **Revisit when** real Lottie assets are produced.

### `fl_chart` / `syncfusion_flutter_charts`

- **Problem they would solve** — data visualisation.
- **Rejected because** the only visualisation in the product is a five-segment
  ramp with highlights. A charting library for that is disproportionate, and
  neither would inherit the design system's colour discipline without
  configuration exceeding the widget it replaces.

### `google_ml_kit` / `tflite` image-labelling helpers

- **Problem they would solve** — target detection, to enable the "no target" and
  "multiple targets" states.
- **Rejected — and the decision has since been taken elsewhere.** ADR 0009
  rejects segmentation, detection and background subtraction for phase one, on
  the grounds that both a mask campaign and a bounding-box campaign require a
  dataset that does not yet exist, and each adds a second artifact to version
  and verify. It defers rather than discards them, to be reconsidered only if
  telemetry shows framing is the dominant failure mode. See
  `06-capture-experience.md` §3.
- **Alternative** — leave the states dormant behind a hypothetical contract.

### `flutter_localizations` / `intl`

- **Problem they would solve** — externalised copy.
- **Out of scope.** Issue #38 already declined centralising UI copy while the
  product is single-locale. This dossier adds a substantial amount of new copy
  and does not change that decision, but it does raise the eventual cost — noted
  so the trade-off is visible rather than accidental.

## 5. Recommended, phase 2 only: `camera`

| Criterion | Assessment |
| --- | --- |
| **Problem** | There is no in-app preview surface, so no live framing guide, region of interest, stability, blur or low-light assistance is possible. `image_picker` returns a file and nothing else |
| **Benefit** | Unlocks the entire assisted-capture experience the design system has already drawn, and permits cropping to a region of interest before inference |
| **Bundle** | Platform camera bindings on both targets; modest Dart surface. Material relative to a lean app, acceptable for a camera-centric product |
| **Compatibility** | First-party, maintained by the Flutter team, same publisher as `image_picker` |
| **Maintenance** | Actively maintained; the most widely used camera package for Flutter |
| **Licence** | BSD-3-Clause, consistent with the existing dependency set |
| **Risks** | Camera lifecycle across backgrounding and permission revocation; iOS parity, and CI has an iOS build job but no iOS device tests; a preview is not testable in the widget harness; frame-analysis throughput on low-end hardware; battery |
| **Alternative without it** | Phase 1 — pre-capture guidance and post-capture validation. Genuinely useful, and it is what this dossier sequences first, precisely so the dependency decision can be taken with phase 1 evidence in hand |
| **Testability mitigation** | Frame analysis must be extracted behind a seam taking raw bytes, so the logic is unit-testable without a camera. This is the same seam phase 1's quality gate already needs, which is a further argument for phase 1 first |

## 6. Watch list

| Package | Why it is on the list |
| --- | --- |
| `sensors_plus` | Would supply accelerometer variance for the phase 2 stability indicator. Evaluate with phase 2, not before |
| `lottie` | See §4 |
| `flutter_localizations` | When a second locale becomes real |
