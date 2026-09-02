# Problems Ranked by Impact

Ranking criterion: what a defect costs the user. Anything that can lead an
agronomist to a wrong field decision outranks anything that merely annoys.
Anything that locks a user out outranks inconsistency.

## P0 — breaks trust or blocks access

### P0-1 A probabilistic inference is presented as a diagnosis

`InferenceResult` carries only the argmax and its probability. With four
classes, chance is twenty-five percent. A top-1 of 0.25 is chance exactly, and is
rendered exactly like a top-1 of 0.95: the class name in `headlineMedium`, the soil-scale colour, and a
badge. Only the badge tint differs.

There is no abstention. There is no notion of two candidates being close. The
full softmax vector exists inside the isolate and is discarded at
`inference_service.dart:247`.

**Cost** — an agronomist can act on noise that the interface presented as a
reading. This is a field-decision risk, not a presentation preference.

**Evidence** — `lib/core/services/inference_service.dart:243-250`,
`lib/models/confidence_level.dart:20-25`,
`lib/core/features/details/widgets/classification_header.dart:49-71`.

### P0-2 The retry affordance cannot succeed

No `.tflite` artifact is tracked; `assets/models/` holds `.gitkeep` and
`.gitignore` excludes both `*.tflite` and `spec.json`. `initialize()` therefore
sets `_modelUnavailable` and `classify()` returns null on every call. The
capture screen renders "Classificação falhou · tocar para repetir".

The user is offered an action that is structurally incapable of working, and
the state is labelled a *failure* when the truth is that the feature is not
present in this build.

**Cost** — repeated futile attempts, and an inaccurate mental model of the
product's reliability.

**Evidence** — `lib/core/services/inference_service.dart:113-117`,
`lib/core/features/capture/widgets/capture_image_preview.dart:144-153`.

### P0-3 Permissions are requested cold at splash

`_requestPermissions()` fires 1200 ms after launch and requests camera, then
location, with no priming and no stated reason. Location is optional to the
product but is requested with identical weight to camera.

A permanent denial at this moment is unrecoverable from inside the app; only
the capture screen implements the resume re-check, and the user has not reached
it yet.

**Cost** — a denial in the first three seconds of the first session
permanently degrades the product for a user who had not yet been told what it
does.

**Evidence** — `lib/core/features/splash/splash_screen.dart:52,61-94`.

### P0-4 Accessibility instrumentation is effectively absent

A repository-wide search for `Semantics`, `semanticLabel`, `MergeSemantics`,
`excludeSemantics` and `tooltip:` returns two results: the brand logo and the
home settings avatar.

Concretely:

- Icon-only buttons carry no label: the preview's back and info circle buttons,
  the history selection-mode close and delete, the search clear button.
- Tappable rows are `GestureDetector`: no ink response, no semantics, no
  enforced minimum target. The home last-analysis row and the history
  thumbnails are both affected.
- `textScaler` is never read, and `maxLines: 1` with ellipsis appears on the
  home record row, the capture chips, the history timestamp and the details
  timestamp. At 200 % scale these truncate content rather than reflow.
- `MediaQuery.disableAnimationsOf` is never read.
- Sample photographs carry no derived label.
- There is no dark theme and no high-contrast provision.

**Cost** — the product is unusable with a screen reader and degrades badly for
low-vision users, in a domain whose users work outdoors in variable light.

**Evidence** — repository-wide search; `lib/main.dart:19`.

## P1 — friction on the primary flow

### P1-1 A dead screen between the call to action and the camera

Tapping "Nova análise" on home pushes `/capture`, whose only content before a
photo exists is a grey placeholder and a "Câmera" button. The placeholder reads
"Selecione uma imagem" — promising image selection in an application that is
camera-only by design and will not add a gallery source.

**Cost** — an extra tap on the single most-used path, and a false expectation
stated in the interface's own words.

**Evidence** — `lib/core/features/capture/widgets/capture_image_preview.dart:54-58`,
`lib/core/features/capture/widgets/capture_actions.dart:26-33`.

### P1-2 No image quality validation

Any photograph becomes a record and is fed to the classifier. A blurred frame,
a frame of a wall, or a frame taken in darkness all produce a confident-looking
class with a percentage attached.

**Cost** — garbage in, authoritative-looking output out. Compounds P0-1.

### P1-3 Offline and sync state are invisible

`connectivityStatusProvider` is consulted in exactly one place: the management
tips section. There is no global indicator. The sync foundation — `sync_queue`,
`SyncEngine`, `RemoteSyncBackend`, per-record `syncStatus` — exists in full and
has no representation anywhere in the interface.

**Cost** — the user cannot tell whether their work is safe or pending.

**Evidence** — `lib/core/features/details/management_tips_section.dart:86-87`;
`syncStatus` is never read by any widget.

### P1-4 Save is gated on optional location

`isBusy` is `_state.isLocating || _state.isClassifying || _state.isSaving`, and
Save is disabled while it holds. Reverse geocoding has a twenty-second timeout.
Classification has fifteen. So the Save button remains disabled for up to twenty
seconds on account of a value the record does not require and can legitimately
store as null.

**Cost** — the user stares at a disabled primary action while holding a phone
over a soil sample in a field.

**Evidence** — `lib/core/features/capture/capture_screen.dart:359`,
`lib/core/features/capture/capture_screen.dart:56`.

## P2 — inconsistency and system debt

### P2-1 Five error presentations and four loading presentations

Errors: `ErrorState`, `HomeDataError`, `_DetailsErrorView`, `_PreviewErrorView`,
`_RecordNotFoundView`. Loading: `LoadingIndicator` plus three raw
`CircularProgressIndicator` sites.

Two of the error variants exist only because the preview screen uses a black
canvas, which is itself a consequence of P2-3.

### P2-2 `VisioAppBar` is used on one of five screens with an app bar

Capture uses it. History, details, settings and preview each construct a raw
`AppBar`. The standardised component standardises nothing.

### P2-3 Preview and details are two destinations for one entity

History opens `/preview` (photograph plus timestamp and location). Its info
button pushes `/details` (photograph plus timestamp, location and
classification). The information overlaps; the hierarchy is duplicated; the
preview's drag handle implies a sheet that does not move.

### P2-4 The design system is ahead of the app and diverges from it

Screens published with no counterpart: `CaptureGuideScreen`, `CaptureScreen`,
`RecommendationScreen`. Components published with no counterpart or with a
private local reimplementation: `TextureScale`, `InfoTile`, `IconButton`,
`Snackbar`, `StatCard`, `Chip`, `ConfidenceBadge`, `ConfidenceBanner`.

More seriously, the design system's `RecommendationScreen` composes structured
sections — water and drainage, indicated crops, preparation and correction —
while the implemented contract `ManagementTipsResult` carries a flat list of
`tips` with `citations` and `sources`. **This is a contract divergence between
the design terminal and the research agent terminal.** It is not this
terminal's to resolve unilaterally; see `05-design-system.md` §5.

### P2-5 Class ordering contradicts itself

`SoilTextureColors._colorMap` orders Siltosa before Media; `InferenceService._textureLabels`
orders Media before Siltosa. `SoilTextureColors.all` documents itself as
returning entries "in model output order". The getter has no consumers today,
so this is a latent trap rather than a live defect — but any future consumer
that trusts the doc comment will be wrong.

**Evidence** — `lib/core/theme/soil_texture_colors.dart:7-13,21-22`,
`lib/core/services/inference_service.dart:60-66`.

### P2-6 History cards omit the information users scan for

Thumbnail plus timestamp. Not the texture class, not the confidence. The filter
chips let the user filter *by* class, which the cards then do not display.

### P2-7 No dark theme, and no high-contrast provision

Two distinct needs, frequently conflated:

- **Dark theme** serves dawn and dusk work, and battery life.
- **High contrast and maximum luminance** serve direct sunlight.

Neither exists. `main.dart` passes `theme:` only.

### P2-8 Destructive actions sit adjacent to confirmatory ones

Capture stacks Save and Discard eight pixels apart. Details stacks Share and
Delete sixteen pixels apart. Both destructive actions do carry confirmation
dialogs, which mitigates but does not remove the mis-tap.

## Summary table

| ID | Problem | Impact | Fixed by spec |
| --- | --- | --- | --- |
| P0-1 | Inference presented as diagnosis | Field-decision risk | 1, 2 |
| P0-2 | Retry that cannot succeed | Trust | 1, 2 |
| P0-3 | Cold permission requests | Access | 4 |
| P0-4 | Accessibility absent | Access | 3 |
| P1-1 | Dead screen before camera | Friction | 5 |
| P1-2 | No quality validation | Result integrity | 6 |
| P1-3 | Offline and sync invisible | Confidence in data | 8 |
| P1-4 | Save gated on location | Friction | 7 |
| P2-1 | Five error, four loading forms | Consistency | 9 |
| P2-2 | `VisioAppBar` unused | Consistency | 9 |
| P2-3 | Preview and details overlap | Structure | 10 |
| P2-4 | Design system divergence | Coordination | 9, coordination item |
| P2-5 | Class ordering contradiction | Latent defect | 1 |
| P2-6 | History cards under-informative | Findability | 9 |
| P2-7 | No dark or high-contrast theme | Field usability | 11 |
| P2-8 | Destructive adjacency | Safety | 3 |
