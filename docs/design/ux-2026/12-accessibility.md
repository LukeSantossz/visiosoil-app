# Accessibility Criteria

Target: WCAG 2.2 level AA, adapted to mobile, plus the Material accessibility
guidance Flutter already implements.

## 1. Current position

A repository-wide search for `Semantics`, `semanticLabel`, `MergeSemantics`,
`excludeSemantics` and `tooltip:` returns two results: the brand logo, and the
home settings avatar added by spec 0029. `MediaQuery` is consulted once, for
device pixel ratio. `HapticFeedback` is never called. There is no dark theme and
no high-contrast provision.

The product is, in practice, unusable with a screen reader.

## 2. Measured contrast

Ratios below were computed from the token values in `app_colors.dart` using the
WCAG relative-luminance formula. They must be re-verified by an automated check
in the implementing spec rather than trusted from this document.

### 2.1 Passing

| Pair | Ratio | Requirement | Result |
| --- | --- | --- | --- |
| `onSurfaceVariant` #43483E on `surface` #FCFDF8 | 9.19 : 1 | 4.5 : 1 | Pass |
| `onWarningContainer` #6D4C1D on `warningContainer` #FBEBD2 | 6.63 : 1 | 4.5 : 1 | Pass |
| White on `primary` #4A7C59 | 4.86 : 1 | 4.5 : 1 | Pass |
| `outline` #73796D on `surface` | 4.39 : 1 | 3 : 1 (non-text) | Pass |
| White `labelSmall` on black-at-55 % over the brightest possible photograph | 4.74 : 1 | 4.5 : 1 | Pass, narrowly |

The last row corrects a suspicion raised during the audit. The capture screen's
overlay chips were flagged as unverified; computed against the worst case — a
fully white photograph behind the scrim — they pass. **The margin is 0.24, so
the scrim alpha of 0.55 is load-bearing.** Any future reduction breaks
compliance silently, which makes it a value that needs a documented minimum and
a test, not a magic number in a widget.

### 2.2 Failing

| Pair | Ratio | Requirement | Result |
| --- | --- | --- | --- |
| `outlineVariant` #C3C8BB **at 50 % alpha** on `surface` | **1.28 : 1** | 3 : 1 (component boundary) | **Fail** |
| `surface` #FCFDF8 against `background` #F8FAF5 | **1.03 : 1** | — | See below |
| `warning` #C88A3D icon on `warningContainer` #FBEBD2 | **2.51 : 1** | 3 : 1 (meaningful icon) | **Fail** |

The first two compound into the most serious visual finding in the audit. Cards
are separated from the page by a fill difference of 1.03 : 1 and a hairline
border at 1.28 : 1. For a low-vision user, or for any user in direct sunlight,
**cards have no perceivable boundary at all**. The pattern `Border.all(color:
AppColors.outlineVariant.withValues(alpha: 0.5))` appears on the home stat
cards, the home record row, the settings tiles and the tip cards.

The design system describes this as intentional — "flat and quiet, not floaty".
The intent is right; the execution puts the entire structural signal below
perceptibility. Raising the border to full `outlineVariant` gives 1.55 : 1,
still short. Meeting 3 : 1 requires `outline` #73796D as the border, at
4.39 : 1 — a visible change to the product's texture, and the reason this is
routed through the high-contrast theme in spec 11 rather than applied globally.

The third failure is also an inconsistency: `_ConfidenceBanner` tints its icon
with `level.foregroundColor` (`onWarningContainer`, 6.63 : 1) while
`_DisclaimerBanner` tints its icon with `AppColors.warning` (2.51 : 1). Two
banners, same container, different icon colour, one of them failing.

## 3. Criteria by category

### 3.1 Semantics

- Every icon-only control carries a label. Enforced structurally by making the
  label a **required** parameter of `VisioIconButton` (`05-design-system.md`
  §4.1).
- Every sample photograph carries a derived label: class, location, date.
- Record rows use `MergeSemantics` so a screen reader announces one item, not
  four fragments.
- Decorative imagery is marked `ExcludeSemantics`.
- Phase transitions and verdict arrival are announced via
  `SemanticsService.announce` (`07-processing-states.md` §6).

Current violations: preview back and info buttons; history selection close and
delete; search clear; all history thumbnails; the home record row; every capture
overlay chip.

### 3.2 Targets and spacing

- Minimum 48 dp on every interactive target.
- Minimum 8 dp between adjacent targets; **minimum 24 dp between a confirmatory
  and a destructive action**, or the destructive action moves to an overflow.

Current violations: capture stacks Save and Discard 8 dp apart; details stacks
Share and Delete 16 dp apart. Both carry confirmation dialogs, which reduces the
cost of a mis-tap but does not prevent one. The history grid's 24 dp selection
checkbox is below the minimum, though it is not independently tappable.

### 3.3 Text scaling

- Layouts survive `textScaler` up to 200 % with no clipping and no overlap.
- `maxLines` with ellipsis is permitted only where the truncated content is
  duplicated elsewhere on the screen.

Current violations: the home record row (`maxLines: 1` on class, place and
timestamp), capture chips, history timestamps, the details timestamp. At 200 %
the home hero headline and the stat card values will also overflow their
containers.

### 3.4 Motion

- Every animation reads `MediaQuery.disableAnimationsOf` and collapses to zero.
- No content is revealed only by animation, so a disabled animation never hides
  anything.

### 3.5 Colour independence

- No state is conveyed by colour alone. Every verdict band carries an icon and
  a text label as well as a tint.

This is nearly true today and becomes a rule. It is also the reason the
insufficient-evidence state can safely drop the red: the icon and the words
carry the meaning, so the colour never had to.

### 3.6 Thumb zone

- The primary action sits in the lower third on every screen that has one.
- Destructive actions are never in the lower third adjacent to a primary.
- Navigation and back affordances stay reachable one-handed on a 6.7-inch
  device.

The current details screen places Share and Delete at the bottom of a long
scroll, which is the correct zone for Share and the wrong one for Delete.

### 3.7 Focus and input

- A visible focus indicator on every interactive element, for hardware keyboard
  and switch access.
- Logical traversal order, verified per screen.
- No interaction that requires a gesture without a discrete alternative. The
  history long-press selection currently has no alternative and no affordance.

## 4. Verification

| Check | How |
| --- | --- |
| Contrast | Automated test over the token pairs, replacing the manual computation in §2 |
| Semantic labels | Widget tests asserting `SemanticsFinder` results per screen |
| Target size | `meetsGuideline(androidTapTargetGuideline)` and `iOSTapTargetGuideline` in widget tests |
| Text scaling | Golden or layout tests at 100 %, 150 %, 200 % |
| Reduce motion | Widget tests with `disableAnimations: true` asserting zero-duration completion |
| Screen reader | Manual pass with TalkBack, per screen, recorded in the implementing spec |

Flutter ships `meetsGuideline` with `textContrastGuideline`,
`androidTapTargetGuideline`, `iOSTapTargetGuideline` and `labeledTapTargetGuideline`.
None is currently used anywhere in the 62 test files. Adopting them is the
cheapest single accessibility improvement available and belongs in spec 3.

## 5. Acceptance criteria

- `no_unlabelled_icon_button` — no interactive icon-only widget lacks a
  semantic label, asserted by `labeledTapTargetGuideline` per screen.
- `tap_targets_meet_guideline` — every screen passes both platform tap-target
  guidelines.
- `text_contrast_meets_guideline` — every screen passes `textContrastGuideline`.
- `token_contrast_verified` — an automated test asserts the ratios in §2, and
  the three failures are either fixed or recorded as accepted with a rationale.
- `scrim_alpha_has_a_floor` — the photo-overlay scrim alpha is a named token
  with a test asserting the resulting worst-case contrast.
- `scales_to_200_percent` — every screen renders without clipping or overlap at
  200 % text scale.
- `reduce_motion_zero_duration` — with animations disabled, no animation runs
  and no content is hidden.
- `destructive_separated` — no destructive action sits within 24 dp of a
  primary action.
- `long_press_has_alternative` — history selection mode is reachable without a
  long press.
