# SPEC: feat(theme): offer a high-contrast mode that draws every card's edge

## Problem

A card's only boundary is a hairline in `outlineVariant` at 50 % alpha, 1.28 : 1 against the surface. Low-vision users, and anyone in direct sunlight, cannot see where a card ends (`docs/design/ux-2026/12-accessibility.md` §2.2, "the most serious visual finding in the audit").

Meeting the 3 : 1 a component boundary needs takes `outline` (4.39 : 1), "a visible change to the product's texture". So the audit routes it through a high-contrast mode, not a global change (§2.2; `docs/design/ux-2026/05-design-system.md` §6). Roadmap item 11 carries it. The dark-theme half of item 11 shipped as SPEC 0107. This spec is its high-contrast half, first slice.

The hairline is written out at five sites:

| Site | Alpha |
| --- | --- |
| `details/management_tips_section.dart`, a tip card | 50 % |
| `details/widgets/info_section.dart`, the info card | 50 % |
| `home/widgets/last_analysis_section.dart`, the record row | 50 % |
| `home/widgets/stats_grid.dart`, a stat card | 40 % |
| `settings/settings_screen.dart`, `_SettingsTile` | 50 % |

## Design Decision

**The palette gets a card border role.** `AppPalette` gains `highContrast`, a `bool` that defaults to `false`, and a getter `cardBorder`:
- outside high contrast: `outlineVariant` at 50 %;
- in high contrast: `outline`, solid.

The five sites read `context.palette.cardBorder`. Outside high contrast nothing changes, except the stat cards' border, which moves from 40 % to 50 % to match the other four.

**Two more palettes, `AppPalette.lightHighContrast` and `AppPalette.darkHighContrast`.** Each is its base palette with `highContrast: true`. They come from a `copyWith({bool? highContrast})`, which replaces today's empty `copyWith`. `AppTheme` gains `lightHighContrast` and `darkHighContrast`, built the same way as `light` and `dark`.

**A setting turns it on.** Settings' APARÊNCIA section gains a switch, "Alto contraste", with the subtitle "Bordas mais fortes, para ler sob o sol". It is persisted next to the theme mode:
- `AppearanceStore` gains `readHighContrast` and `writeHighContrast`, under the key `appearance.highContrast`;
- it is read before the first frame, as SPEC 0107 reads the theme mode, so the app never starts in the wrong look.

`main.dart` passes the high-contrast themes as `theme` and `darkTheme` while the setting is on. The switch makes `AppHaptics.selection()` (SPEC 0126).

**The platform's signal turns it on too.** `MaterialApp` also gets `highContrastTheme` and `highContrastDarkTheme`. Flutter uses them when the platform reports high contrast, which today is iOS. Android sends Flutter no high-contrast signal, which is why the setting exists.

**This slice draws edges only.** The design system's high contrast also names heavier type and solid versions of the other translucent decoration, and the page's surface is 1.03 : 1 against its background. Those are later slices. The edge is the one the audit calls the most serious.

## Alternatives Considered

- **Raise every border to `outline` for everyone.** Rejected by the audit itself: it changes the product's texture, which the design system calls "flat and quiet".
- **Follow only the platform signal.** Rejected: Android, the release target, does not send one to Flutter.
- **Four full `AppPalette` constants for the high-contrast pair.** Rejected: about 40 duplicated colour lines each, for one changed role. `copyWith` keeps the base palettes as the one source.

## Scope

- Includes:
  - `lib/core/theme/app_palette.dart`: `highContrast`, `cardBorder`, `copyWith`, `lerp`, and the two high-contrast palettes.
  - `lib/core/theme/app_theme.dart`: the two high-contrast themes.
  - The five border sites.
  - `lib/core/services/appearance_store.dart`, `lib/providers/appearance_provider.dart` and `lib/main.dart`: the setting, its persistence and its restore.
  - `lib/core/features/settings/settings_screen.dart`: the switch.
  - Tests for each criterion, and a round trip of the stored choice with its fallback when the store cannot be read. The three test fakes of `AppearanceStore` gain the two new methods.
- Does NOT include:
  - Heavier type weights, other translucent decoration, and the page-against-surface contrast (later slices of item 11).
  - The native launch screen, which keeps SPEC 0107's light and dark.
  - Any colour value of the existing palettes.

## Acceptance Criteria

- `card_border_meets_3_to_1_in_high_contrast`: `cardBorder` against `surface` is at least 3 : 1 in both high-contrast palettes.
- `default_card_border_is_unchanged`: in `light` and `dark`, `cardBorder` is `outlineVariant` at 50 %.
- `card_borders_use_the_role`: no file under `lib/` builds a border from `outlineVariant.withValues(alpha:`.
- `high_contrast_is_a_setting`: turning on "Alto contraste" in settings gives the app the high-contrast palette at once, and writes it to the store. Turning it off restores the default.
- `high_contrast_survives_a_restart`: with the store holding `true`, the app's first frame already has the high-contrast palette.
- `platform_signal_is_honoured`: with the platform reporting high contrast and the setting off, the app has the high-contrast palette.
- The existing tests pass, with two changes:
  - the three `AppearanceStore` fakes are extended;
  - the three settings tests that tap "Apagar todos os dados" now scroll to it first, since the new switch moves it below the test view's fold.

## Reproducibility

`flutter test test/core/theme/ test/features/settings/ test/app_appearance_test.dart`

Flutter 3.44.1, Dart 3.12.1.

## Risks and Assumptions

- `outline` on the dark surface is a dark-palette pair that SPEC 0107 already checks at 3 : 1, so the dark high-contrast palette inherits a passing border.
- Whether 4.39 : 1 reads in direct sunlight on a real phone is left to a look outdoors.
