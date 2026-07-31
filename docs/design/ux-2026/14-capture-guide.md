# Capture Guide — Open Decision

**Status: open. The content of the guide is being redefined by the product
owner.** This document holds the open question and the constraints any version
must satisfy. It deliberately proposes no step list and no copy.

An earlier draft of this file did propose both, and settled the protocol
question unilaterally. That draft was withdrawn before it was committed.

## 1. Why the guide is being rewritten at all

Three reasons, none of which depend on which content is chosen:

1. **Wrong moment.** The capture technique currently lives in onboarding
   (`onboarding_screen.dart:24-49`), shown once at first launch — when the user
   has the least intent to photograph anything — and afterwards only from
   Settings. It moves to the first capture, with on-demand access from the
   analysis screen and Settings (`02-user-journey.md` §3.4,
   `04-information-architecture.md` §3).
2. **The region of interest is now real.** SPEC 0030 defines the analysed region
   as the largest centred square. A user who fills the whole rectangle is
   filling a region larger than the one being measured.
3. **The design system's guide and the collection protocol disagree.** See §2.

## 2. The open question

The onboarding declares a capture protocol with five rules
(`onboarding_screen.dart:24-49`):

| Rule | Measured by anything today? |
| --- | --- |
| A coin beside the sample, for scale | No |
| Soil filling at least 70 % of the frame | No — ADR 0009 declines to measure it, since it needs foreground separation |
| Diffuse natural light | Indirectly, by SPEC 0030's exposure and specular metrics |
| No flash | Indirectly, by the specular metric |
| Top-down at roughly 20 cm | No |

The dataset is collected under all five, and ADR 0009's strategy is to **enforce
that protocol rather than compensate for its absence**. SPEC 0030's problem
statement is built on it.

The design system's `CaptureGuideScreen` has four steps and **contains neither
the coin nor the 70 % fill**.

Adopting the design-system guide as-is would therefore delete two protocol rules
from the only place the user ever reads them, while collection continues to
apply them — reopening the subpopulation gap ADR 0009 exists to close, through
the interface, invisibly.

### Options

1. **Restore both rules in the guide.** Faithful to the protocol. Makes the
   guide longer than the design system's, against
   `03-problems.md`'s own concern about cognitive load in the field. Can be
   taken by this terminal alone, because restoring a rule cannot widen the gap.
2. **Drop both from the guide and from collection.** Defensible only if neither
   rule is load-bearing. **Requires the ML terminal's agreement**, since it
   changes what they collect.
3. **Keep the coin, drop the fill.** The fill is unmeasurable by decision; the
   coin is what ADR 0009 names as the strongest argument for a future detector,
   since a detected coin yields real millimetres per pixel. **Also requires the
   ML terminal's agreement**, for the same reason as option 2.

This terminal states no recommendation. The asymmetry worth carrying into the
decision is that option 1 is unilateral and options 2 and 3 are not.

## 3. Constraints on any version

These hold regardless of which content is chosen, and are this terminal's to
assert.

### Content

- **The framing instruction must describe the centred square**, not "a guia" —
  phase 1 draws no guide — and not the full frame, which is not what gets
  analysed.
- **Any numeric rule the user cannot verify by eye should not appear as a
  number.** "At least 70 %" is not something a person estimates reliably; the
  numeric form belongs in the collection protocol and the criteria library,
  where it is actually checked.
- Brazilian Portuguese, sentence case, implied imperative, no emoji, per
  `05-design-system.md` §7.
- A prohibition states its reason. The current onboarding already does this for
  the flash, and it is the reason that rule survives.

### Behaviour

- Shown automatically before the first camera launch; not on subsequent ones.
- Reachable on demand from the analysis screen and from Settings, returning to
  the caller in each case.
- **Back never opens the camera.** Only the primary action does. Today's
  onboarding conflates the two: its completion path both marks the flag and
  navigates.
- **The seen-flag is independent of the onboarding-completed flag.** A user who
  completed onboarding before this ships has not seen the guide and must be
  shown it once.

### Layout and accessibility

- **The primary action is sticky**, not at the end of a static column. The
  design system's mockup places it at the end; four or more steps plus an
  illustration plus the avoid pair overflow a small screen at 100 % text scale
  and certainly at 200 %, so the content scrolls and the action must stay
  reachable without scrolling to the end.
- Each step is one semantic node via `MergeSemantics`; the step list announces
  its length.
- Decorative illustration excluded from semantics — which is only safe if
  everything it conveys is also in the step text.
- No motion. A read-once instructional surface has no state change to explain,
  and `09-microinteractions.md` permits motion only for that.

### Asset gap

An annotated photograph of a real sample — correct framing, coin in place,
right distance — would outperform any icon composition for every step. None
exists. Recorded as an asset request rather than left implicit, because the
choice between icons and a photograph changes the layout.

## 4. What this replaces

The three-step `PageView` onboarding covering framing, lighting and angle, with
its progress bar, its "Pular" button and its per-step full-screen illustrations.
Onboarding retains value framing and permission priming only
(`02-user-journey.md` §3.2).

## 5. Acceptance criteria

Content-dependent criteria are deferred until the content is defined. These are
content-independent and stand now:

- `guide_names_the_roi` — the framing instruction describes the centred square,
  matching SPEC 0030's region of interest.
- `guide_shown_before_first_camera` — shown automatically before the first
  camera launch and not on subsequent ones.
- `guide_flag_is_independent` — a user who completed the old onboarding is shown
  the guide once.
- `guide_reachable_on_demand` — reachable from the analysis screen and from
  Settings, returning to the caller.
- `back_does_not_open_camera` — only the primary action opens the camera.
- `guide_scrolls_at_200_percent` — at 200 % text scale the content scrolls with
  no clipping and the primary action remains reachable without scrolling to the
  end.
- `steps_are_single_semantic_nodes` — each step announces as one node; the list
  announces its length; the illustration is excluded.
- `protocol_rules_are_not_silently_dropped` — the guide states every rule the
  dataset is collected under, or the collection protocol was changed by a
  recorded joint decision.
- `onboarding_no_longer_teaches_capture` — no framing, lighting or angle content
  remains in the onboarding screen.
