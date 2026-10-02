# SPEC: feat(theme): offer a dark theme and launch in the chosen one

## Problem

The app is light-only. `MaterialApp` sets `AppTheme.light` and no `darkTheme`. The UX dossier records the gap as P2-7: a dark theme serves work at dawn and dusk, and saves battery (`docs/design/ux-2026/05-design-system.md` §6).

Two things stand in the way:
- **Widgets read a fixed light palette.** 91 references in 15 widget files and `ConfidenceLevel` read `AppColors.*` constants directly. `AppTypography` also bakes the light text colours into the text theme. A second `ColorScheme` alone would leave most of the screen light.
- **The launch would flash.** SPEC 0089 made the Android launch window light in every system mode, because Flutter always painted light. Once the app can be dark, the launch has to follow the choice. Otherwise the first frames show the wrong colour (#245).

## Design Decision

**A palette as a theme extension.** `AppPalette extends ThemeExtension<AppPalette>` carries every colour role a widget reads, in two instances: `AppPalette.light` and `AppPalette.dark`.
- `AppPalette.light` holds today's `AppColors` values, unchanged.
- Widgets read `context.palette.<role>`.
- `context.palette` falls back to the instance matching `Theme.of(context).brightness`, so a test that pumps a bare `MaterialApp` still works.
- `AppTheme.light` and `AppTheme.dark` are built by one function from a palette, and so is the text theme. `ConfidenceLevel`'s colours take the palette as an argument.
- `AppColors` stays as the light token values. Only `lib/core/theme/` may read it, and a test enforces that.

**The dark values come from the light palette's own hues.** The light tokens sit on Material 3 tones: containers at T90 and T10–14, `inversePrimary` at T81, neutrals at T98/T99/T10, outline at T50/T80. Each dark role takes Material 3's dark tone from the same hue and chroma (`material_color_utilities` `TonalPalette`). The values are then fixed as constants:

| Role | Dark | Tone |
| --- | --- | --- |
| `primary` / `onPrimary` | `#B1D1B9` / `#1B3625` | 81 (today's `inversePrimary`) / 20 |
| `primaryContainer` / `onPrimaryContainer` | `#324D3B` / `#CBEAD2` | 30 / 90 |
| `secondary` / `onSecondary` | `#E4C192` / `#412C0A` | 80 / 20 |
| `secondaryContainer` / `onSecondaryContainer` | `#5A431E` / `#FFDDB1` | 30 / 90 |
| `tertiary` / `onTertiary` | `#B8CDA4` / `#243517` | 80 / 20 |
| `tertiaryContainer` / `onTertiaryContainer` | `#3A4C2C` / `#D4EABE` | 30 / 90 |
| `error` / `onError` / `errorContainer` / `onErrorContainer` | `#FFB4AB` / `#690005` / `#93000A` / `#FFDAD6` | Material 3 baseline |
| `warning` / `warningContainer` / `onWarningContainer` | `#FEB968` / `#604012` / `#FFDDB6` | 80 / 30 / 90 |
| `background` / `onBackground` | `#121411` / `#E2E3DD` | 6 / 90 |
| `surface` / `onSurface` | `#1E201D` / `#E2E3DD` | 12 / 90 |
| `surfaceVariant` / `onSurfaceVariant` | `#43483E` / `#C3C8BB` | 30 / 80 |
| `outline` / `outlineVariant` | `#8D9287` / `#43483E` | 60 / 30 |
| `inverseSurface` / `onInverseSurface` / `inversePrimary` | `#E2E3DD` / `#2F312D` / `#4A7C59` | 90 / 20 / the light primary |
| shadows | black at the light shadows' alphas | — |

**Brand surfaces do not change with the theme.** Two surfaces are the brand mark rather than a colour role: the splash tile and the home hero card. Both keep the brand green `#4A7C59` with white text in both themes. White on it is 4.86:1. This keeps the design system's rule that `primary` does not become a large fill in dark mode, because in dark mode `primary` is the pale `#B1D1B9`. The five soil colours are a data encoding and also stay the same.

**The choice is stored and applied before the first frame.**
- `AppearanceStore` persists `system`, `light` or `dark` under `appearance.themeMode` in `shared_preferences`. It has no default write: an absent or unknown value reads as `system`.
- `main()` reads it before `runApp`, so the first Flutter frame is already in the chosen theme.
- Settings gains an **"APARÊNCIA"** section with a three-way control: "Sistema", "Claro", "Escuro". A change applies at once and persists.

**The Android launch follows the choice on Android 12 and later.** Dart passes every choice, and the stored one at start, over a `visiosoil/appearance` method channel. `MainActivity` hands it to `UiModeManager.setApplicationNightMode` on API 31+:

| Choice | Mode | Effect |
| --- | --- | --- |
| `light` | `MODE_NIGHT_NO` | the app's night mode is forced off |
| `dark` | `MODE_NIGHT_YES` | the app's night mode is forced on |
| `system` | `MODE_NIGHT_AUTO` | no override; the app follows the system |

The system persists that mode per app and applies it to the splash screen it draws at the next cold launch.

A `values-night/colors.xml` overrides `launch_background` alone. Every launch style already takes its background from `@color/launch_background`, so in night mode three windows resolve the dark value without a night style:
- the launch window before Android 12;
- the Android 12+ splash;
- the window behind Flutter.

SPEC 0089's pin that no style names `Theme.Black` stands. The tile stays the brand's.

**The details header reads over any photo.** The device pass found one screen that leaned on a light-only effect. The details header draws its back arrow, and the status-bar icons, over the photograph in the theme's text colour. ADR 0017's protocol puts a white sheet at the top of every photograph, so in the dark theme both were pale on white. The light theme fails the same way over a dark photograph.

The fix copies the photo viewer's pattern and holds in both themes:
- the back button sits in a black 45% circle with a white icon;
- the photograph starts below the status bar, so the status-bar icons sit on the theme's surface.

**Status-bar icons follow the theme.** `MaterialApp.builder` wraps the app in an `AnnotatedRegion<SystemUiOverlayStyle>` that sets only the icon brightness. An `AppBar` still sets its own. This spec changes no bar colour; that is #304's.

## Alternatives Considered

- **Read the stored choice in Kotlin before the window is themed**, as #245 proposed. Rejected:
  - On Android 12+, `setApplicationNightMode` is the platform's mechanism for exactly this, and it needs no coupling to `shared_preferences`' key prefix.
  - On Android 11 and earlier, the system draws the starting window before any app code runs. App code can only hide it with `windowDisablePreview`, and that trades the flash for a launch that shows nothing.
- **Swap `AppColors` constants for `Theme.of(context).colorScheme` roles in widgets.** Rejected: `ColorScheme` has no warning, shadow or brand roles. Widgets would then read colours from two places, and the extension keeps one.
- **Lighten the soil scale for dark surfaces**, which the design system permits. Rejected for now. The scale fails 3:1 against the background at its light end in the light theme (Arenosa 1.87:1) and at its dark end in the dark theme (Muito Argilosa 1.73:1). Moving one end moves the problem rather than fixing it. The class name always sits beside the dot, so the colour is never the only signal.
- **Ship the high-contrast mode with it.** Rejected: the design system treats sunlight contrast as a separate need with its own token changes, the borders among them.
- **Wait for the UX roadmap's specs 3 and 9.** The roadmap places the dark theme after those. Rejected by the Developer, who asked for the dark theme now. The token layer this spec adds is what those specs would also build on.

## Scope

- Includes:
  - `lib/core/theme/`:
    - `app_palette.dart`, holding `AppPalette`, its two instances and `context.palette`;
    - `AppTheme.dark` beside `AppTheme.light`, from one builder;
    - `AppTypography`'s text theme built from the palette.
  - Every `AppColors.*` read outside `lib/core/theme/` moves to `context.palette`. That covers 15 widget files and `ConfidenceLevel`. `SoilTextureColors` lives in `lib/core/theme/` and is unchanged.
  - The appearance store and controller:
    - `lib/core/services/appearance_store.dart`: `AppearanceStore` and its `SharedPreferences` implementation, plus `NightModeSync` with its Android channel implementation and a no-op elsewhere;
    - `lib/providers/appearance_provider.dart`.
  - `main.dart`: read the choice before `runApp`, then set `theme`, `darkTheme`, `themeMode` and the status-bar `AnnotatedRegion`.
  - Settings: the "APARÊNCIA" section.
  - The details header: the back button's scrim and the photograph's top inset, found by the device pass.
  - Android:
    - `MainActivity.kt`'s channel;
    - `values-night/colors.xml`;
    - the SPEC 0089 comments that call the app light-only.
  - Tests for every criterion below. `confidence_level_test` and the launch-screen pins are updated.
- Does NOT include:
  - The high-contrast mode, or any change to the light palette's values, including its recorded contrast failures (`12-accessibility.md` §2.2).
  - Edge to edge and the bar colours (#304).
  - The iOS launch screen, which follows the system. SPEC 0089 leaves it so, and a fix belongs to another toolchain.
  - The share image, which `share_content_builder` draws light by design.
  - The photo viewer and the capture overlays. Both are black over a photograph in either theme.

## Acceptance Criteria

- `dark_text_pairs_meet_aa`: in `AppPalette.dark`, every text pair is at least 4.5:1. The pairs are each on-colour over its colour, plus `onSurfaceVariant` over `surface` and over `background`. `primary`, `error` and `warning` over `surface`, and `outline` over `surface`, are at least 3:1.
- `light_palette_is_unchanged`: `AppPalette.light` equals today's `AppColors` value for every role.
- `brand_surfaces_hold_in_both_themes`: the splash tile and the hero card render the brand green with white content, under the light theme and under the dark one.
- `no_widget_reads_the_fixed_palette`: no file under `lib/` outside `lib/core/theme/` names `AppColors`.
- `the_choice_round_trips`: `AppearanceStore` reads `system` when nothing, or an unknown value, is stored. Writing `dark` and reading back gives `dark`, and the same holds for `light` and `system`.
- `settings_switches_the_theme`: tapping "Escuro" in Settings makes the app's theme dark, persists `dark`, and sends `dark` to `NightModeSync`. "Claro" and "Sistema" do the same for their modes.
- `the_first_frame_is_in_the_stored_theme`: started with `dark` stored, the first frame's theme is dark.
- `the_details_header_reads_over_any_photo`: in both themes, the details header's back button has a black 45% background and a white icon, and the photograph's top edge is at or below the status bar.
- `status_bar_icons_follow_the_theme`: under the dark theme the region asks for light icons, and under the light theme for dark ones.
- `the_launch_follows_night_resources`:
  - `values-night/colors.xml` declares `launch_background`, equal to `AppPalette.dark.background`, and no other colour;
  - every launch style still takes its background from `@color/launch_background`;
  - no styles file is qualified for night, so the tile and SPEC 0089's pins hold in both modes.
- `the_channel_matches_on_both_sides`: `MainActivity.kt` handles the channel name and method that `NightModeSync` sends. It maps `light`, `dark` and `system` to `MODE_NIGHT_NO`, `MODE_NIGHT_YES` and `MODE_NIGHT_AUTO`, and only on API 31+.
- `the_launch_matches_on_a_device`: frame sampling of a cold launch, by the screenrecord method SPEC 0089 used:
  - **API 34 and 36:** with `dark` chosen on a light system, no launch frame is light. With `light` chosen on a dark system, no launch frame is dark. With `system`, the launch follows the system.
  - **API 30:** with `system`, the launch follows the system. The record states what a non-system choice shows there.

## Reproducibility

`flutter test test/core/theme/ test/services/appearance_store_test.dart test/features/settings/ test/features/home/ test/features/splash/ test/app_appearance_test.dart test/android_night_mode_test.dart test/standards/no_fixed_palette_test.dart test/android_launch_screen_test.dart test/models/confidence_level_test.dart`

Device check: a release APK on the API 30, 34 and 36 emulators, with `adb shell screenrecord`, then frame extraction with `ffmpeg` and pixel sampling of the background at a fixed point.

Flutter 3.44.1, Dart 3.12.1.

## Risks and Assumptions

- **Android 11 and earlier keep a short mismatch.** When the choice differs from the system's, the system-drawn starting window follows the system until Flutter's first frame. No app code runs before that window, so this spec records the mismatch rather than hiding the window.
- **`setApplicationNightMode` overrides the app's night mode.** `MediaQuery.platformBrightness` then reports the app's mode, not the system's. With a non-system choice, `themeMode` is explicit and ignores it, and with `system` the override is cleared, so nothing reads the difference.
- **The activity keeps running across a night-mode change**, because the manifest's `configChanges` already lists `uiMode`, so a change in Settings does not recreate it.
- The soil scale's dark-end contrast is a known limit, recorded under Alternatives.
- Screens are restyled by token substitution, not redesigned. A screen whose layout leaned on a light-only effect, such as a white button on a light card, is caught only by the device pass.
