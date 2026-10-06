# SPEC: feat(capture): show the capture guide before the first camera launch

## Problem

The protocol the A4-sheet reader needs, above all a soil circle of 8 to 10 cm, is taught only by the onboarding at first launch, so a user is never shown it when they are about to photograph, and the refusal that follows a small patch does not say what size it needs.

The onboarding (SPEC 0104) is shown once, when the user has the least intent to photograph anything, and afterwards only from Settings. On 2026-10-05 the first real session still produced soil patches of about 5 cm, and every photograph whose sheet was found stopped at `soilRegionTooSmall` ([the check](../ml/sheet-reader-real-photographs.md)). The small-disc study kept the floor of nine patches, which needs a disc of 58.5 mm, and named the remedy: a bigger soil patch, with the capture screen saying so as the next change ([the study](../ml/small-disc-study.md), SPEC 0141). `docs/design/ux-2026/14-capture-guide.md` already sets the behaviour such a guide must have, and leaves only its content open.

## Design Decision

**A capture-guide route, shown before the first camera launch.** A new route, `/capture-guide`, draws `CaptureGuideScreen`: an app bar titled "Como capturar", the protocol as three numbered steps, and one primary action pinned below the scrolling content. The behaviour is the one `14-capture-guide.md` §3 sets:

- **Before the first camera launch.** When the user taps "Câmera" on the capture screen and the camera permission is granted, the screen asks a new `CaptureGuideStore` whether the guide was seen. If not, it pushes the guide with its primary action reading "Abrir câmera". That action marks the guide seen and returns `true`, and only then does the capture screen open the camera. Leaving by the back button returns nothing, so the camera stays closed and the guide stays unseen.
- **On demand.** The capture screen's app bar carries a "Como capturar" icon button, and Settings' existing "Como capturar bem" row opens the guide instead of the onboarding. Opened this way, the primary action reads "Entendi", marks the guide seen and returns to the caller. It never opens the camera, because a photograph may already be on the capture screen.
- **Its own flag.** `CaptureGuideStore` persists `capture_guide_seen` in `shared_preferences`, apart from `onboarding_completed`, so a user who finished the onboarding before this ships is shown the guide once. A store that cannot be read or written never blocks the camera: an unreadable flag counts as seen, and a failed write still opens the camera.

**The content is the onboarding's protocol, from one source.** The three steps, their icons, titles and sentences, move from `onboarding_screen.dart` to `lib/core/constants/capture_protocol.dart`, and both screens read them there. The onboarding's text does not change by a character. This settles the open content question of `14-capture-guide.md` §2: the coin and the 70 % fill it weighs were replaced by the A4-sheet protocol of ADR 0017, which SPEC 0104 already teaches. Its `guide_names_the_roi` criterion is dropped for the same reason: the framing the reader needs is the whole sheet with a margin, not SPEC 0030's centred square.

**The `soilRegionTooSmall` chip names the size.** Its label becomes "Pouco solo na folha · espalhe um círculo de 8 a 10 cm e tire outra foto". It stays non-retryable. This amends one row of SPEC 0105's table. Both producers of the cause, a sheet with no soil on it and a soil disc too small for nine patches, have the same remedy.

The guide scrolls at 200 % text with its action still in view (SPEC 0121). Each step is one semantic node, the step list announces its length, and the icons carry no label of their own. It has no motion.

## Alternatives Considered

- **Draw the protocol in the empty capture screen's placeholder.** Rejected at the Gate in favour of the route. It needs no flag and no route, but it shows the protocol on every capture to a user who knows it, cannot be opened once a photograph is on screen, and leaves Settings pointing at the onboarding.
- **Show the guide before every camera launch.** Rejected. It adds a screen to every capture, and `14-capture-guide.md` §3 asks for the first launch only, with on-demand access after it.
- **Make the onboarding value framing only, as `14-capture-guide.md` §4 proposes.** Rejected for this change. The onboarding would need new copy on the app's value and on permissions, which is a product decision of its own. Keeping its protocol steps costs nothing once both screens read one source.
- **Open the camera from the on-demand guide too.** Rejected. Opened from a capture screen that already holds a photograph, a camera would replace it without asking, and opened from Settings it would leave Settings.
- **Keep the flag in `OnboardingStore`.** Rejected. The two flags answer different questions, and the store's name would no longer say what it holds.

## Scope

- Includes:
  - `lib/core/constants/capture_protocol.dart`: the three protocol steps, moved from the onboarding.
  - `lib/core/features/onboarding/onboarding_screen.dart`: its steps read the shared list. No text, step count or navigation changes.
  - `lib/core/services/capture_guide_store.dart` and `lib/providers/capture_guide_store_provider.dart`, with a fake in `test/support/`.
  - `lib/core/features/capture/capture_guide_screen.dart`: the guide.
  - `lib/core/routes/app_router.dart`: the `/capture-guide` route.
  - `lib/core/features/capture/capture_screen.dart`: the guide before the first camera launch, and the "Como capturar" app-bar action.
  - `lib/core/features/settings/settings_screen.dart`: "Como capturar bem" opens the guide.
  - `lib/core/features/capture/widgets/classification_failure_chip.dart`: the `soilRegionTooSmall` label.
  - Tests for each criterion, and the existing capture tests given a guide already seen.
  - The route and provider counts in `docs/agents/project.md`, the generated `CLAUDE.md` and `AGENTS.md`, and the README; and the status line of `docs/design/ux-2026/14-capture-guide.md`.
- Does NOT include:
  - Rewriting the onboarding as value framing, or removing its protocol steps.
  - Skipping the empty capture screen, or any other part of `04-information-architecture.md` §3.
  - An illustration, a photograph of the protocol, or an "Evite" pair.
  - An in-app viewfinder or framing guide.
  - The patch floor, the grid, the sheet reader, or any other refusal's copy.

## Acceptance Criteria

- `guide_shown_before_first_camera`: with the guide unseen, the first tap on "Câmera" opens the guide and not the camera; "Abrir câmera" then opens the camera; a second capture opens the camera with no guide.
- `back_does_not_open_camera`: leaving the guide by back returns to the capture screen, the camera is not opened, and the guide stays unseen.
- `guide_flag_is_independent`: with `onboarding_completed` set and `capture_guide_seen` unset, the store reports the guide unseen; marking it seen sets only `capture_guide_seen`.
- `an_unreadable_flag_does_not_block_the_camera`: when the store throws on read, "Câmera" opens the camera; when it throws on write, "Abrir câmera" still opens it.
- `guide_reachable_on_demand`: the capture screen's "Como capturar" action and Settings' "Como capturar bem" each open the guide; its "Entendi" returns to the caller, marks the guide seen and opens no camera.
- `guide_teaches_the_onboarding_protocol`: the guide's steps show the onboarding steps' titles and sentences, in the same order.
- `guide_scrolls_at_200_percent`: at 200 % text on a phone, the guide lays out with no overflow, its primary action is on screen without scrolling, and its last step can be scrolled into view.
- `steps_are_single_semantic_nodes`: each step is one semantic node holding its number, title and sentence; the list announces "3 passos"; no icon has a label.
- `guide_meets_guidelines`: the guide passes Flutter's four accessibility guidelines in the light and dark themes.
- `the_small_soil_chip_names_the_size`: the `soilRegionTooSmall` chip reads "Pouco solo na folha · espalhe um círculo de 8 a 10 cm e tire outra foto" and is not retryable.
- The router registers `/capture-guide`, and the onboarding's existing tests pass unchanged.

## Reproducibility

```sh
flutter test test/features/capture test/features/onboarding test/features/settings test/routes test/services/capture_guide_store_test.dart
flutter analyze && flutter test && mf check
```

Flutter 3.44.1, Dart 3.12.1, `mf` v0.8.0.

## Risks and Assumptions

- **Assumption: a user reads a guide shown once, right before the camera.** Whether it changes the patch size is measured by the next photo session, not by this change. A user who still under-spreads the soil is told the size by the chip.
- **Risk: 8 to 10 cm is not measured by eye.** The sentence keeps the onboarding's number, which SPEC 0104 approved.
- **Risk: a user who backs out of the guide sees it again on the next tap.** That is intended: the guide is marked seen only by its primary action.
- **What would invalidate this spec:** a change to the capture protocol itself, or a product decision on `14-capture-guide.md` that moves the guide elsewhere.
