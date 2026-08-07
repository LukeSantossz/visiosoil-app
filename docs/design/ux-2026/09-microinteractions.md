# Microinteractions

## 1. The constraint, stated first

The design system has already settled the motion voice, and this strategy
obeys it rather than proposing around it:

> Animation: restrained and functional. ~120–180 ms ease transitions on
> colour/border; press states scale to .98 (buttons) / .92 (icon buttons); the
> only looping animation is the loading spinner. No bounces, no decorative
> motion.

`AppMotion` already tokenises the durations and curves. It is referenced in
exactly three places in the entire app. The gap is not that the app needs a
motion system — it has one — but that almost nothing uses it.

## 2. Governing rules

1. **Motion explains a state change or it does not exist.** Nothing animates to
   be pleasant.
2. **Every animation reads `MediaQuery.disableAnimationsOf` and collapses to
   zero duration.** Motion that ignores this is an accessibility barrier, not a
   flourish.
3. **Haptics confirm, they do not decorate.** One tier per event class, never
   `heavyImpact`.
4. **No animation delays an action.** Feedback may animate; the action fires
   immediately.

## 3. The catalogue

| Moment | Response | Token | Rationale |
| --- | --- | --- | --- |
| Touch recognised | Ink response plus press scale — `0.98` buttons, `0.92` icon buttons — and `HapticFeedback.selectionClick()` | `instant` 90 ms | Today the home record row and history thumbnails are `GestureDetector`: a tap produces no feedback whatsoever until the next screen appears |
| Camera opening | `lightImpact()` on shutter return | — | Confirms the app received the photograph |
| Image accepted | The photograph appears already in place on the analysis screen | `base` 220 ms fade | The absence of an intermediate empty state is itself the feedback |
| **Image rejected** | The photograph **desaturates**; the defect badge fades in | `fast` 140 ms | No shake — the design system forbids bounces, and desaturation *is* the message: this image is not being used |
| Processing phase change | Crossfade of the phase label | `base` 220 ms | Swapping one spinner for another reads as a stall; a changing label reads as progress |
| **Verdict arrival** | Staggered reveal of header, badge, banner, evidence, actions | `reveal` 640 ms, `emphasized` | The one moment that earns motion. The design system already specifies the exact choreography (delays 0 / 50 / 100 / 170 / 240 / 310 ms) in `DetailScreen.jsx`. The actions are **built and hit-testable from the first frame**; only their opacity and offset animate — see §3.1 |
| Verdict arrival | `mediumImpact()` | — | The user may be looking at the sample, not the phone |
| Expanding sources or details | `AnimatedSize` | `base` 220 ms | Preserves the reading position |
| Chip or tab selection | Colour and border transition | `fast` 140 ms | Matches the design system's stated 120–180 ms band |
| Error correction | The error region collapses as the corrected content enters | `base` 220 ms | Shows that the correction landed |

### 3.1 The reveal animates appearance, never availability

The verdict reveal is the one place in this catalogue where a choreography could
quietly cost the user something, so the rule is stated rather than left to the
implementer.

The staggered entrance includes the actions, and the last of them starts at
310 ms into a 640 ms sequence. If that stagger is built the obvious way — mount
each element when its delay elapses — then for the first third of a second after
a result arrives the retake and save buttons do not exist, and a tap during the
animation lands on nothing. The user who is fastest to act is the one punished,
and the failure is invisible in review because a tap that hits no widget looks
exactly like a tap that was never made.

So: **every element of the result, actions included, is built on the first frame
of the reveal.** Only opacity and offset are animated, and an element at zero
opacity still hit-tests. The choreography changes how the result appears; it
never changes what is available. This is what `verdict_reveal_is_not_blocking`
means, and it is why that criterion is phrased over interactivity rather than
over the animation's duration.

The same rule applies wherever `reveal` is used with a stagger. It is the reason
the design system's delays can be adopted verbatim without adopting a web
implementation's mounting behaviour along with them.

## 4. What is deliberately excluded

| Excluded | Why |
| --- | --- |
| Shake on rejection | The design system forbids bounces; desaturation carries the meaning without implying user error |
| Skeleton shimmer | A travelling highlight is decorative motion, and it loops — both prohibited. Static placeholder blocks with a crossfade to content instead |
| Confidence gauge animating up | Animating a number implies measurement in progress. The number was computed instantly; animating it fabricates a process |
| Page transition choreography | Platform defaults are correct and predictable |
| Hero image shared-element transition between history and details | Attractive, but the thumbnail and the hero crop differently; the mismatch reads as a glitch |
| Any looping animation but the spinner | Design system rule |

## 5. Haptics tiers

| Tier | Events |
| --- | --- |
| `selectionClick` | Chip, tab, filter, list selection |
| `lightImpact` | Shutter return, save confirmed |
| `mediumImpact` | Verdict arrival, blocking quality verdict |
| `heavyImpact` | **Never.** Nothing in this product is that important |

Haptics come from `flutter/services`, part of the SDK. No dependency.

Haptics must also respect the platform's own setting; on Android
`HapticFeedback` already honours system haptic preferences, and no additional
gate is required beyond not calling it in a loop.

## 6. Implementation shape

A single `StaggeredReveal` widget wrapping an ordered child list, reading
`AppMotion.reveal`, `AppMotion.emphasized`, and the reduce-motion flag. Used by
the analysis screen and the details screen. One widget, one place where the
reduce-motion check lives, no per-screen animation controllers.

Press feedback arrives by converting `GestureDetector` call sites to `InkWell`
or a shared tappable wrapper — which is the same change required by
`12-accessibility.md`, and should ship in that spec rather than this one.

## 7. Acceptance criteria

- `reduce_motion_respected` — with animations disabled at the platform level,
  every animation in the catalogue completes in zero duration and no content is
  hidden as a result.
- `press_feedback_everywhere` — every tappable surface produces visible feedback
  on touch down.
- `no_looping_animation` — no animation other than the loading spinner repeats.
- `rejection_desaturates` — a blocking quality verdict desaturates the
  photograph rather than moving it.
- `verdict_reveal_is_not_blocking` — the actions on the result are interactive
  before the reveal finishes.
