# SPEC: fix(a11y): give the tips disclaimer's icon a colour that reads on its banner

## Problem

The management tips disclaimer draws its info icon in `warning` on `warningContainer`, a 2.51 : 1 pair below the 3 : 1 a meaningful icon needs (`docs/design/ux-2026/12-accessibility.md` §2.2), while the confidence banner beside it already uses `onWarningContainer` at 6.63 : 1.

## Scope

- Includes:
  - `lib/core/features/details/management_tips_section.dart`: `_DisclaimerBanner`'s icon takes `palette.onWarningContainer`, as `_ConfidenceBanner`'s does.
  - `test/features/details/management_tips_section_test.dart`: the test below.
- Does NOT include:
  - The banner's border, `warning` at 30 % alpha, which is decoration and carries no meaning the icon and text do not.
  - The banner's text colour, `onSurface`, which already passes.
  - The other low-contrast findings in §2.2, the card borders and the page against the surface. Those are roadmap item 11's high-contrast mode.

## Acceptance Criteria

- `disclaimer_icon_reads_on_its_banner`: the disclaimer's info icon is `onWarningContainer`, and against `warningContainer` it reaches at least 3 : 1, in the light palette and in the dark one.
- The existing tests pass unchanged.
