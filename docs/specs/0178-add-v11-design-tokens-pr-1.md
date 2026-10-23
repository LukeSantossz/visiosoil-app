# SPEC: feat(theme): add design tokens for Redesign v11 PR 1

## Problem

The v11 redesign requires new design system tokens (AppPalette.sun for outdoor field use, AppDensity, AppRadius.xs, Inter font features, and typography tokens) before screens can adopt the new visual language, and the existing tokens must remain unchanged so existing screens do not break.

## Scope

- Includes:
  - `AppPalette`: new tokens (`primaryText`, `textTertiary`, `divider`, `selected`, `destructive`, `surfaceContainer`, `surfaceContainerHigh`), `sun` palette with AAA contrast (≥7:1), `isSun` flag for safe lerp detection.
  - `AppDensity` ThemeExtension: `standard` (48dp taps) and `sun` (56dp taps) variants.
  - `AppRadius.xs = 4.0` and `borderRadiusXs`.
  - `AppTypography`: Inter cv11/ss01 font features on body/label styles, `displaySmall` (new), `v11HeadlineMedium`, `v11TitleMedium`, `v11LabelLarge` as additive tokens.
  - `tabular()` helper for `tnum` feature.
  - Golden tests for 3 palettes (light, dark, sun).
  - Contrast tests verifying sun meets AAA (≥7:1 text, ≥3:1 icons), new v11 tokens meet AA.
  - Density, radius, and typography unit tests.
- Does NOT include:
  - Screen layout changes; existing screens continue using existing tokens unchanged.
  - Changes to existing style values (headlineMedium, titleMedium, labelLarge preserve original values).
  - textThemeFor sun scaling (deferred to screen adoption PRs).
  - Wiring sun palette into the app's theme switching (later PR).

## Acceptance Criteria

- `sun_is_high_contrast_and_light_brightness`: sun palette has `highContrast: true` and `Brightness.light`.
- `sun_has_isSun_flag`: only sun has `isSun: true`; light and dark are false.
- `isSun_survives_lerp`: a lerped palette past t=0.5 from light to sun has `isSun: true`.
- `sun_all_text_pairs_meet_7_to_1`: all sun text/background pairs have contrast ≥7:1.
- `sun_icon_pairs_meet_3_to_1`: all sun icon/background pairs have contrast ≥3:1.
- `light_new_text_tokens_meet_4_5_to_1`: new v11 text tokens on light surfaces have contrast ≥4.5:1.
- `dark_new_text_tokens_meet_4_5_to_1`: new v11 text tokens on dark surfaces have contrast ≥4.5:1.
- `existing_styles_unchanged`: headlineMedium, titleMedium, labelLarge retain original values.
- `v11_additive_tokens_have_spec_values`: v11HeadlineMedium, v11TitleMedium, v11LabelLarge match spec.
- `body_styles_have_cv11_and_ss01`: Inter font features present on body and label styles.
- `tabular_adds_tnum_feature`: tabular() helper adds tnum without removing existing features.
- `density_standard_and_sun_variants`: AppDensity.standard has 48dp taps, sun has 56dp.
- `radius_xs_is_4`: AppRadius.xs equals 4.0.
- `golden_palettes_render`: golden tests for light, dark, and sun palettes pass.
