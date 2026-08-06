# Design System

## 1. The circular source of truth, and how to cut it

The design system's readme states that it is "derived directly from the app's
Flutter source of truth, not from screenshots". Specs 0024, 0027 and 0029 treat
the design system as the authority and align the app to it. Each declares the
other canonical. While that holds, every divergence is an argument with no
tie-breaker.

**Proposed split:**

| Layer | Authority | Lives in |
| --- | --- | --- |
| **Values** — colour hexes, type sizes, spacing steps, radii, durations, curves | `lib/core/theme/` | The app |
| **Rules** — colour discipline, the soil scale restriction, pill buttons, sentence case, no emoji, motion restraint, voice | The design system | `readme.md` and `guidelines/` |
| **Composition** — screen layout references, component anatomy | The design system | `ui_kits/`, `components/` |

Values must compile and be testable, so they belong in Dart. Rules are prose
about intent and have no compilable form. Composition is the design system's
purpose.

## 2. Drift protection

Values existing in two places will diverge. A test comparing `tokens/*.css`
against the Dart token classes closes the loop mechanically.

**Obstacle:** `/VisioSoil Design System/` is excluded by `.gitignore:92`, so CI
cannot read it.

**Recommendation:** version only the four token files
(`tokens/colors.css`, `typography.css`, `spacing.css`, `motion.css`) as a test
fixture under `test/support/`, leaving the rest of the kit ignored. Four small
text files, no binary assets, and the test becomes runnable in CI.

Alternatives considered: vendoring the whole kit (drags fonts and JSX into the
repository for no test benefit); a manual review checklist (already failed —
the class-ordering contradiction in `SoilTextureColors` survived several
alignment specs); no test (accepts the drift).

**What the fixture proves, and what it does not.** A copied fixture makes the
copy canonical, not the kit. The test would prove that the Dart tokens match
`test/support/`, and nothing more: if the design system changes a value, the
ignored kit and the committed fixture diverge in silence and the test stays
green while the app is wrong. That is a smaller gap than having no test at all
— it catches the far more common direction, a Dart token edited by hand — but
calling it a design-system conformance test would overstate it.

Closing it needs one of two things, and the spec that implements this must pick
one rather than leave it implied. Either the four CSS files become canonical and
the kit is regenerated from them, which inverts today's direction of authority;
or the fixture carries a recorded provenance — the kit version or a content hash
it was taken from — and a check fails when the kit on disk no longer matches it,
which keeps the kit canonical at the cost of the check being runnable only where
the kit is present, so it guards the developer's machine rather than CI.

## 3. Token gaps

| Gap | Why it is needed | Proposal |
| --- | --- | --- |
| Neutral verdict pair | "Insufficient evidence" must not be red. Today only `primaryContainer`, `warningContainer` and `errorContainer` exist as band fills | Add a neutral container/on-container pair derived from `surfaceVariant` / `onSurfaceVariant`, verified for contrast |
| Minimum touch target | Nothing encodes 48 dp; several targets are below it | `AppSizing.minTouchTarget = 48.0` |
| Focus and pressed states | Not tokenised; press feedback is absent on `GestureDetector` rows | Press scale `0.98` for buttons, `0.92` for icon buttons, per the design system; a focus outline token |
| Dark scheme | No second `ColorScheme` | Full dark scheme; see §6 |
| High-contrast provision | Distinct from dark; not present | See §6 |

## 4. Component gaps

### 4.1 Missing entirely

| Component | Needed by | Note |
| --- | --- | --- |
| `TextureScale` | Ambiguous results, details evidence | Five-step ramp with one or two highlighted positions. Published by the design system, absent from the app |
| `VisioIconButton` | Preview, history, capture | Replaces the bespoke `_CircleIconButton`. **Its semantic label parameter is required**, so omitting it is a compile error rather than a review finding. Requiredness alone does not make the label meaningful — see the rule in §4.3 |
| `QualityNotice` | Quality verdict | New; no design-system counterpart yet |
| `VerdictHeader` | Result presentation | New; supersedes the current class-name row plus badge |

### 4.2 Present but private or duplicated

| Today | Action |
| --- | --- |
| `_ConfidenceBadge` (details) and `_ConfidenceChip` (home) | Promote to one shared `ConfidenceBadge`, matching the design system's published component |
| `_ConfidenceBanner` (details) | Promote to shared `ConfidenceBanner` |
| `_InfoRow` (details) and `_InfoRow` (preview) | Unify as `VisioInfoTile`; the preview copy disappears with the IA fix in `04-information-architecture.md` |
| `_StatCard` (home) | Align to the published `StatCard` |
| `_FilterChip` (history) | Align to the published `Chip` |
| `_CaptureButton` (home hero) | Either add a white-on-primary variant to `VisioButton` or keep it local and document the exception. Spec 0029 already flagged this |

### 4.3 Component API rule

Every interactive shared component takes a semantic label as a **required**
parameter, or derives one from content it already receives. No optional
accessibility parameters — an optional parameter is a parameter that will be
omitted.

Requiredness is only the first of three, and a spec that stops there ships a
guarantee it does not have. A required `String` still accepts `''`, and an empty
label is worse than a missing one: it silences the review that a missing
parameter would have triggered, and a screen reader announces the control with
no name. So each such component also carries:

- an `assert(label.trim().isNotEmpty)` in the constructor, which fails in debug
  and in every test run, where an empty label would otherwise pass unnoticed;
- one semantics test per component asserting the rendered node exposes the
  label, so the parameter is proven to reach `Semantics` rather than merely
  being accepted and dropped.

The compile error stops omission. The assert stops emptiness. The test stops the
parameter being accepted and discarded. None of the three substitutes for
another, and this rule is what the accessibility baseline spec implements — it
is not satisfied by the signature alone.

## 5. The recommendation contract divergence

**Coordination item. Not resolvable by this terminal alone.**

The design system's `RecommendationScreen` composes three structured sections:

| Section | Content |
| --- | --- |
| Água e drenagem | Prose about water retention and drainage |
| Culturas indicadas | A chip list of crops |
| Preparo e correção | Prose about preparation and correction |

plus a rationale block ("Por que estas sugestões") and a disclaimer.

The implemented contract is:

```dart
class ManagementTipsResult {
  final ManagementTipsStatus status;   // grounded | abstained
  final List<ManagementTip> tips;      // flat: text + citation indices
  final List<TipSource> sources;
  final String disclaimer;
  final String model;
  final DateTime retrievedAt;
}
```

A flat list of cited tips cannot render the design system's screen without the
app inventing the section assignment, which would be fabricating structure that
the agent did not produce.

**Three ways out, for the two terminals to choose between:**

1. **Extend the contract** — each tip gains an optional `category` from a closed
   enumeration (`water`, `crops`, `preparation`, `other`). The app groups by
   category and falls back to a flat list when the field is absent. Preserves
   the citation model intact. *This terminal's recommendation.*
2. **Retire the design-system screen** — accept the flat cited list as the real
   shape and update `RecommendationScreen` to match. Cheapest, but discards a
   genuinely better information structure.
3. **Group in the app by keyword** — rejected outright. It would attribute a
   structure to the agent's output that the agent never asserted, which is the
   same category of dishonesty as fabricating a class label.

Until this is settled, the app renders the flat list it actually receives.

## 6. Themes

Two distinct needs, routinely conflated. This dossier treats them separately.

**Dark theme** serves work at dawn and dusk, and battery life. It is a full
second `ColorScheme`. Constraints carried over from the light scheme:

- The soil scale is a data encoding, not chrome. The five browns must remain
  distinguishable from one another and from the background in both themes. They
  may be lightened for dark surfaces but their *ordering and separation* must
  survive.
- `primary` keeps its meaning: actions, links, success. It does not become a
  large fill in dark mode either.
- The verdict bands need dark equivalents of all four container pairs,
  contrast-verified independently.

**High contrast for sunlight** is not darkness. It is maximum luminance
contrast, heavier type weights, thicker borders, and the removal of low-alpha
decoration — the `withValues(alpha: 0.5)` hairlines that carry structure today
become solid. This can ship as a user preference or follow the platform
accessibility signal.

Sequenced as spec 11 in the roadmap. Both are large, and neither is worth doing
before the token layer has stopped moving.

## 7. Content rules

Adopted from the design system's content fundamentals, restated here because
they are acceptance criteria for every screen:

- Brazilian Portuguese, sentence case everywhere. Uppercase only for
  letter-spaced eyebrow labels.
- Technical but plain-spoken. No marketing register.
- Implied imperative, addressed to the user. No "nós".
- **Uncertainty is never hidden.** Every non-conclusive result states its limit.
- Percentages: rounded in badges, one decimal in detail views.
- No emoji, ever.

Two additions this dossier makes:

- **Never name a defect generically when a specific name is available.** "Imagem
  desfocada" over "imagem inválida".
- **Never offer an action that cannot succeed.** A retry is offered only when a
  retry could change the outcome.
