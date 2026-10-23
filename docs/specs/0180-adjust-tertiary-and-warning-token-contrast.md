# SPEC: fix(theme): adjust tertiary and warning token contrast

## Problem

Two tokens in `AppColors` fall short of the thresholds `docs/design/ux-2026/12-accessibility.md`
sets for their use: `tertiary` #6B7F5A carries white text at 4.37 : 1, short of
the 4.5 : 1 AA text threshold even though every caller (`onTertiary`, the brand
tile) draws white on it; and `warning` #C88A3D, used as an icon tint, clears
only 2.93 : 1 against white, short of the 3 : 1 non-text threshold WCAG sets
for a meaningful icon. Both were flagged in the accessibility audit (§2.2) and
left unresolved pending Designer-approved replacement values.

## Design Decision

Replace the two token values with Designer-approved ones that clear their
threshold, and add a dedicated text-only tint so a future caller never repeats
the icon tier's shortfall:

- `AppColors.tertiary`: #6B7F5A → #677A57. White on the new value is
  4.67 : 1 (was 4.37 : 1). `onTertiary` stays white; every reader of
  `AppColors.tertiary` or `AppPalette.light.tertiary` — including
  `AppPalette.brandTileEnd`'s default and the Android launch window's
  `launch_tile_end` — moves with it, since none of them hold their own copy of
  the hex. `AppPalette.dark.tertiary` (#B8CDA4) and `AppPalette.sun.tertiary`
  (#1F4D2E) are distinct values already tuned for their own theme and do not
  reuse #6B7F5A, so neither changes.
- `AppColors.warning`: #C88A3D → #B07A35. White on the new value is 3.70 : 1
  (was 2.93 : 1), and the token's own audited pairing — `warning` icon on
  `warningContainer` — rises from 2.51 : 1 to 3.15 : 1, clearing 3 : 1 for the
  first time (`docs/design/ux-2026/12-accessibility.md` §2.1). Repository-wide
  search of `lib/` found every caller of `palette.warning` /
  `AppColors.warning` drawing an icon or a border (`discFill`, `discInk`,
  `bannerBorder`'s `accent`), never a `TextStyle.color` — so no text usage
  needed migrating. `AppPalette.dark.warning` (#FEB968) and
  `AppPalette.sun.warning` (#4A3417) are distinct values and do not change.
- New token `AppColors.warningText` = #9E6B2C, darker than the icon tier so a
  future text caller clears 4.5 : 1 against white (4.57 : 1) without
  rediscovering the icon tier's shortfall. Added to `AppPalette` as
  `warningText`, defaulting to `AppColors.warningText` in every palette the
  same way `brand`/`onBrand`/`brandTileEnd`/`shadowBrand` default to their
  light-theme value in both themes — there is no current caller to decide a
  dark- or Sun-specific tone for.

## Alternatives Considered

- **Reuse `onWarningContainer` for text instead of a new `warningText` token.**
  Rejected: `onWarningContainer` is defined relative to `warningContainer`'s
  fill, not to a plain surface, and its contrast against `warningContainer`
  (6.63 : 1) says nothing about its contrast against a white or `surface`
  background a text caller might actually use.
- **Leave `warning` at #C88A3D and only add `warningText` for future text
  use.** Rejected: the icon tier itself is audited and failing today
  (`docs/design/ux-2026/12-accessibility.md` §2.2); leaving it unfixed would
  carry the known failure forward while only guarding against a hypothetical
  future one.
- **Omit `warningText` since no caller exists yet.** Rejected: the token is
  Designer-approved and the project already carries tokens ahead of their
  caller when the value itself is settled (e.g. `ClassificationVerdict`,
  `ImageQualityAnalyzer`) — adding it now avoids a future author guessing a
  text-safe shade under time pressure.

## Scope

- Includes:
  - `lib/core/theme/app_colors.dart`: `tertiary`, `warning` new values;
    new `warningText` constant.
  - `lib/core/theme/app_palette.dart`: new `warningText` field (default
    `AppColors.warningText`), threaded through `copyWith` and `lerp`.
  - `android/app/src/main/res/values/colors.xml`: `launch_tile_end` follows
    `AppColors.tertiary`.
  - `test/core/theme/token_contrast_test.dart`: new contrast assertions for
    `tertiary`, `warning` and `warningText`.
  - `test/core/theme/goldens/palette_light.png`: regenerated — the swatch
    widget renders `warning` directly.
  - `docs/design/ux-2026/12-accessibility.md`: the `warning`-on-
    `warningContainer` row moved from §2.2 (Failing) to §2.1 (Passing) with
    the new value and ratio; surrounding prose updated to past tense.
- Does NOT include:
  - Wiring `warningText` into any widget — no caller exists today (see Design
    Decision).
  - `docs/design/spec/SPEC.md` — Designer-owned, not touched by this spec.
  - Re-tuning `AppPalette.dark.tertiary`, `AppPalette.dark.warning`,
    `AppPalette.sun.tertiary` or `AppPalette.sun.warning` — none reuse the
    replaced hex values.

## Acceptance Criteria

- `warning` (icon) on `warningContainer` #FBEBD2 is at least 3:1 (3.15:1), the pair audited in `docs/design/ux-2026/12-accessibility.md`.

- `tertiary_carries_white_text_at_aa`: contrast of `Colors.white` against
  `AppColors.tertiary` is `>= 4.5`.
- `warning_icon_meets_the_non_text_threshold`: contrast of `Colors.white`
  against `AppColors.warning` is `>= 3`.
- `warning_text_meets_aa_on_its_own`: contrast of `Colors.white` against
  `AppColors.warningText` is `>= 4.5`.
- `no_text_tint_uses_the_old_icon_only_warning_value`: `AppColors.warningText`
  is not the icon tier's value (#B07A35).
- Every existing test in `test/core/theme/` still passes, including the
  regenerated `palette_light.png` golden.
- `test/android_launch_screen_test.dart`'s `launch_colours_are_the_splash_colours`
  still passes (it reads `AppColors.tertiary`, not a literal hex).

## Reproducibility

```sh
flutter test test/core/theme test/android_launch_screen_test.dart
flutter analyze && flutter test
```

Flutter 3.44.1, Dart 3.12.1.

## Risks and Assumptions

- Assumption: the Designer-approved replacement hexes (#677A57, #B07A35,
  #9E6B2C) are final; this spec does not re-derive them, only verifies they
  clear their respective thresholds.
- Assumption: no caller outside `lib/` (e.g. a native splash asset other than
  `android/app/src/main/res/values/colors.xml`) holds its own copy of
  #6B7F5A or #C88A3D; a repository-wide search found none.
- Risk: a future caller draws `palette.warning` or `AppColors.warning` as text
  instead of `warningText`, repeating the shortfall this spec fixes for the
  icon tier. No lint enforces the distinction; it relies on the doc comment on
  `warningText`.
- What would invalidate this spec: a Designer revision to any of the three
  hexes that no longer clears its threshold.
