# SPEC: fix(theme): apply Inter typography to headlineMedium and titleMedium

## Problem

The redesign's §1.2 table puts `headlineMedium` and `titleMedium` in Inter
(28/36 weight 650 tracking −0.025em, and 16/22 weight 600), but
`AppTypography`'s `textTheme` still renders both in Manrope at the pre-redesign
weights and heights, with the Inter values sitting unused in additive
`v11HeadlineMedium`/`v11TitleMedium` tokens no screen reads; `bodySmall` and
`bodyMedium` also carry heights (1.4 and 1.45) that round away from the table's
16/12 and 20/14 (QA report item 6, `/tmp/qa.md`).

## Design Decision

`headlineMedium` and `titleMedium` become the Inter values directly —
`AppTypography.textThemeFor` already builds the app's `TextTheme` from these
two getters, so every screen that reads `Theme.of(context).textTheme.headlineMedium`
or `.titleMedium` picks up the change with no call-site edit. `bodySmall` and
`bodyMedium` keep their font and weight and only have their `height` corrected
to the table's exact ratios (16/12 and 20/14). The added OFL-licensed Inter v4.1 variable asset,
`assets/fonts/InterVariable.ttf` (879,708 bytes, measured with
`wc -c assets/fonts/InterVariable.ttf`), is registered as the separate
`InterVariable` family. `headlineMedium` uses that family with
`fontVariations: [FontVariation('wght', 650)]` for exact rendered weight 650,
while retaining `FontWeight.w600` as its semantic weight and the `cv11`/`ss01`
features. Other Inter styles keep the existing static assets. `v11HeadlineMedium` and
`v11TitleMedium` are removed rather than kept as aliases: both had zero
production callers (the only other reference was their own test), so keeping
them would be a token with no reader pointing at a value `headlineMedium`/
`titleMedium` now hold directly.

## Alternatives Considered

- **Keep `v11HeadlineMedium`/`v11TitleMedium` as aliases of the new
  `headlineMedium`/`titleMedium`.** Rejected: neither token has a production
  caller, so an alias would be dead weight with no reader to migrate off it
  later; a future screen that wants the Inter title style can read
  `Theme.of(context).textTheme.titleMedium` like every other screen does.
- **Approximate headline weight 650 with static Inter SemiBold.** Rejected:
  the static 600 outlines cannot render the table's exact 650; the variable
  asset supports the required weight axis.
- **Leave `bodySmall`/`bodyMedium` heights as the already-close 1.4/1.45.**
  Rejected: the QA report flags the mismatch against the table's exact 16/12
  and 20/14 ratios explicitly (item 6); the ratios are cheap to express exactly
  via `height: 16 / 12` / `height: 20 / 14` with no behavioural trade-off.

## Scope

- Includes:
  - `assets/fonts/InterVariable.ttf` and its `InterVariable` family registration
    in `pubspec.yaml`.
  - `lib/core/theme/app_typography.dart`: `headlineMedium` and `titleMedium`
    moved to Inter at the §1.2 values; `bodySmall`/`bodyMedium` heights
    corrected to 16/12 and 20/14; `v11HeadlineMedium`/`v11TitleMedium` removed.
  - `test/core/theme/app_typography_test.dart`: assertions updated to the new
    `headlineMedium`/`titleMedium` values and the corrected body heights; the
    removed tokens' tests dropped.
- Does NOT include:
  - Modo Sol's parenthetical sizes in `textThemeFor` (§1.2's Sol column):
    already correct per SPEC 0182 and untouched here.
  - `headlineLarge`, `headlineSmall`, `titleLarge`, `titleSmall`, `labelLarge`,
    `labelMedium`, `labelSmall` or `displaySmall`: none are named in the QA
    report item this spec answers.
  - `v11LabelLarge`: a separate additive token outside this item's scope.
  - Any screen widget: every reader goes through `Theme.of(context).textTheme`,
    so none needs its own edit.

## Acceptance Criteria

- `headlineMedium_has_spec_values`: `AppTypography.headlineMedium` is InterVariable,
  28 sp, semantic `FontWeight.w600`, `wght` variation 650, letter spacing ≈ −0.7, height ≈ 36/28, and carries
  the `cv11`/`ss01` font features.
- `titleMedium_has_spec_values`: `AppTypography.titleMedium` is Inter, 16 sp,
  `FontWeight.w600`, height ≈ 22/16, and carries the `cv11`/`ss01` font
  features.
- `bodyMedium_height_is_20_over_14` / `bodySmall_height_is_16_over_12`:
  `AppTypography.bodyMedium.height` ≈ 20/14 and `AppTypography.bodySmall.height`
  ≈ 16/12.
- `sun_sizes_up_titleMedium_bodyLarge_bodyMedium_bodySmall` /
  `light_and_dark_keep_the_base_sizes` (pre-existing, re-run unmodified):
  `textThemeFor`'s Modo Sol parenthetical sizes and the light/dark base sizes
  are unaffected by this change.
- `flutter analyze` reports no issues and `flutter test` passes in full.

## Reproducibility

```sh
export PATH="$HOME/flutter/bin:$PATH"
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter test test/core/theme/app_typography_test.dart
flutter analyze && flutter test && mf check
```

Flutter 3.44.1, Dart 3.12.1, `mf` v0.8.0.

## Risks and Assumptions

- Assumption: no screen depends on `headlineMedium`'s or `titleMedium`'s old
  Manrope metrics for a hand-tuned layout; every reader goes through
  `Theme.of(context).textTheme`, and no golden test outside
  `test/core/theme/app_palette_golden_test.dart` (which does not use
  `AppTypography`) renders either style, so no golden needed regenerating for
  this change.
- What would invalidate this spec: a screen found to size itself against
  `headlineMedium`'s or `titleMedium`'s previous Manrope line height rather
  than the ambient `TextTheme`, which would need its own follow-up fix.
