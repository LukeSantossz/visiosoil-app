# SPEC: feat(theme): add AppTheme.sun and a three-way theme selector

## Problem

`AppPalette.sun` exists (redesign v11 PR 1, SPEC 0178) but nothing builds a `ThemeData` from it, and Settings' theme row only offers Sistema | Claro | Escuro. Field use in direct sunlight needs a theme with 56 dp tap targets, 2 dp borders instead of shadows, and larger type — reachable only by an explicit choice, never by a default.

## Design Decision

Add `AppTheme.sun` and replace the Sistema/Claro/Escuro selector with the one the redesign specifies: Claro | Escuro | Modo Sol (v11 §3.11), backed by a theme choice that is either one of those three or absent (follow the system).

**`AppTheme.sun`** (`lib/core/theme/app_theme.dart`), built over `AppPalette.sun` (v11 §2):
- `materialTapTargetSize: padded`, `visualDensity: standard`, extensions `[AppPalette.sun, AppDensity.sun]`.
- Elevated/outlined/text button themes: `minimumSize: Size(64, 56)`; outlined buttons additionally carry a 2 dp black `side`. All three also carry their own `textStyle` at the sun-scaled `labelLarge` (17 sp) — each already sets an explicit `textStyle` in the base theme (light/dark/high-contrast), which shadows the ambient `TextTheme` those three themes would otherwise inherit from, so Sol must repeat the override at its own scaled size rather than leaving the base's unscaled one in place.
- `elevatedButtonTheme`, `floatingActionButtonTheme`, `snackBarTheme` and `dialogTheme`: `elevation: 0` (and the FAB's `focus`/`hover`/`highlight`/`disabledElevation`), the same no-shadow rule as the card (v11 §1.5).
- `segmentedButtonTheme`: padding sized so a segment's height clears 56 dp against the sun-scaled `labelLarge` (`SegmentedButton` never forwards `minimumSize` to its segments — only `padding` reaches their height calculation, confirmed by reading `segmented_button.dart`). Unlike the three button themes above, `segmentedButtonTheme` (and `FilledButton`, which has no theme override at all) carry no explicit `textStyle` here: neither sets one in the base theme either, so both already resolve the sun-scaled `labelLarge` through `Theme.textTheme.labelLarge` — adding one here would instead break `AnimatedTheme`'s interpolation against the other themes' unset style (a `TextStyle.inherit` mismatch assertion).
- `cardTheme`: `elevation: 0`, a 2 dp black `RoundedRectangleBorder.side` (v11 §1.5: Sol never draws a shadow).
- `chipTheme.side`, `switchTheme.trackOutlineColor`, and `iconButtonTheme.minimumSize`: the same 2 dp black / 56 dp treatment.
- `navigationBarTheme`: `height: 88`, black indicator, white icon when selected and black otherwise, and its own `labelTextStyle` at the sun-scaled `labelMedium` (14 sp) for the same shadowing reason as the three button themes above.

**`AppTypography.textThemeFor`** scales up for `palette.isSun` (v11 §1.2's parenthetical sizes): `titleMedium` 17/24, `bodyLarge` 18/27, `bodyMedium` 16/24, `bodySmall` 14/20, `labelLarge` 17, `labelMedium` 14. `displaySmall`, the headlines and `labelSmall` have no Sol variant in the table and are unchanged. Sol's `bodySmall` colour needs no special case: the palette's own `onSurfaceVariant` is already black.

**The theme choice** (`AppThemeChoice` in `lib/core/services/appearance_store.dart`): an enum of exactly `light`, `dark`, `sun` — no `system` member, because following the system is the *absence* of a choice, not one of the three the selector shows (decision 23/10/2026). `AppearanceStore.readThemeChoice()` returns `AppThemeChoice?`; `null` means no explicit choice was ever made.

- **Migration**: a store that has no value under the new key (`appearance.themeChoice`) falls back to the legacy `appearance.themeMode` key (SPEC 0107). An explicit legacy `light`/`dark` migrates to the equivalent `AppThemeChoice` and is written back under the new key; a legacy `system` (or nothing stored) still carries no explicit choice.
- `nightModeFor(AppThemeChoice? choice)` maps the choice to the `ThemeMode` the platform's night-mode channel understands: `light`→light, `dark`→dark, `sun`→light (Sol ignores `platformBrightness`), `null`→system.

**Providers** (`lib/providers/appearance_provider.dart`): `initialThemeChoiceProvider` (read before `runApp`) and `themeChoiceProvider`/`ThemeChoiceController` replace `initialThemeModeProvider`/`themeModeProvider`/`ThemeModeController`. `select(choice)` applies the state, persists it, and hands `nightModeFor(choice)` to `NightModeSync`.

**`VisioSoilApp`** (`lib/main.dart`): when the choice is `sun`, `theme` and `darkTheme` are both `AppTheme.sun` and `themeMode` is `nightModeFor(choice)` (always light) — bypassing the existing "Alto contraste" setting and the platform's own high-contrast signal entirely, since Sol already is its own fixed high-contrast theme. `highContrastTheme` and `highContrastDarkTheme` are `AppTheme.sun` too in that case (otherwise `AppTheme.lightHighContrast`/`darkHighContrast` as before): `MaterialApp` substitutes those two ahead of `theme`/`darkTheme` whenever the platform's own accessibility signal reports high contrast, at startup or when the signal changes during use, so leaving them as the legacy pair would let that signal knock Sol back out to SPEC 0130's theme. Otherwise the existing light/dark + "Alto contraste" wiring (SPEC 0130) is unchanged.

**Settings** (`_ThemeChoiceSelector`): a `SegmentedButton<AppThemeChoice>` with exactly three segments (Claro, Escuro, Modo Sol) and the caption "Alto contraste e letras maiores para o campo" (v11 §3.11). Its `selected` set shows the explicit choice, or — when none was made — whichever of Claro/Escuro the current brightness resolves to, purely for display; no value is persisted until the user taps a segment. `emptySelectionAllowed: true` lets that tap register even when the segment tapped is the one already shown selected (the resolved display value, with no explicit choice yet): `SegmentedButton` otherwise treats a tap on its current `selected` set as a no-op and never calls `onSelectionChanged` at all, which would silently drop the user's first explicit pick whenever it agrees with the system brightness. The handler reads an empty selection as "persist the segment shown selected" rather than as a deselection.

**List rows**: `_SettingsTile`'s container gets `constraints: BoxConstraints(minHeight: context.density.tap)` (48 standard, 56 Sol), the first production reader of `AppDensity` (added token-only in SPEC 0178).

## Alternatives Considered

- **Keep a "Sistema" segment alongside Sol.** Rejected: the redesign's segmented control (v11 §3.11) lists exactly three options, and decision 23/10/2026 states the system is followed only before any explicit choice — there is deliberately no way back to it from the selector.
- **Fold `AppThemeChoice.sun` into Flutter's `ThemeMode`.** Not possible: `ThemeMode` is a sealed framework enum. A separate `AppThemeChoice` is the only way to add a third, non-brightness-derived state.
- **Drop the legacy "Alto contraste" switch (SPEC 0130) now that Sol exists.** Deferred — see Risks and Assumptions; the Trello card and the redesign's PR-2 acceptance criteria scope this change to `AppTheme.sun` and the selector, not to retiring SPEC 0130.

## Scope

- Includes:
  - `lib/core/theme/app_theme.dart`: `AppTheme.sun`.
  - `lib/core/theme/app_typography.dart`: Sol's scaled sizes in `textThemeFor`.
  - `lib/core/services/appearance_store.dart`: `AppThemeChoice`, `nightModeFor`, `readThemeChoice`/`writeThemeChoice` with migration, `restoreThemeChoice`.
  - `lib/providers/appearance_provider.dart`: `initialThemeChoiceProvider`, `themeChoiceProvider`, `ThemeChoiceController`, replacing the `ThemeMode`-based equivalents.
  - `lib/main.dart`: restoring the choice before `runApp`; `sun` theme/themeMode wiring.
  - `lib/core/features/settings/settings_screen.dart`: `_ThemeChoiceSelector`; `_SettingsTile`'s density-driven minimum row height.
  - `lib/core/constants/app_strings.dart`: the selector's labels and caption.
  - `test/support/guidelines.dart`: `sunTapTargetGuideline` (56 dp).
  - Tests for each criterion below, and the existing appearance/settings/locale tests updated to the new provider and store shapes.
- Does NOT include:
  - §11's excluded items (fractions, top 3, talhão, the vibration indicator, the mock's fictional data) — none of them are touched by this change.
  - Retiring the "Alto contraste" switch or `AppTheme.lightHighContrast`/`darkHighContrast` (SPEC 0130): kept, orthogonal to Sol, unchanged for the `light`/`dark` choices.
  - Rewriting Settings' full section layout to v11 §3.11's exact grouping (Perfil, Preferências, etc.) — PR 12's scope.
  - Wiring `AppDensity` into any widget beyond `_SettingsTile`'s row height — PR 5's component library.
  - A list row's 64 dp Sol height from §1.3 (a dedicated list-row component): only the 56 dp generic tap target is applied here.

## Acceptance Criteria

- `first_boot_with_no_stored_choice_follows_the_system`: with no explicit choice, the first frame's brightness matches the platform's.
- `sol_never_turns_on_by_itself`: with no choice, or an explicit `light`/`dark` choice, `context.palette.isSun` is false.
- `sol_ignores_the_platform_brightness`: with an explicit `sun` choice, the theme's brightness is light and `isSun` is true even when the platform reports dark.
- `dark_first_boot_with_no_stored_choice_follows_the_system` / `live_light_to_dark_system_change_before_any_choice`: with no explicit choice, the brightness follows the platform both at the first frame and when the platform's own brightness changes live, before any choice is ever made.
- `sol_overrides_platform_high_contrast_at_startup` / `sol_overrides_platform_high_contrast_when_toggled_during_use`: with an explicit `sun` choice, the platform's own high-contrast accessibility signal (not just the "Alto contraste" setting) never swaps Sol for `AppTheme.lightHighContrast`/`darkHighContrast`, whether that signal is already on at the first frame or turned on while Sol is already running.
- `a_legacy_light_or_dark_choice_migrates` / `a_legacy_system_choice_does_not_migrate` / `a_legacy_choice_migration_writes_the_new_key`: `readThemeChoice()` on a store holding only the pre-Sol key returns the equivalent choice for `light`/`dark`, and `null` for `system` or nothing stored; the migrated value is actually written under the new key, not just reproduced from the legacy one on every read.
- `the_stored_choice_is_reapplied_at_start` / `sol_is_reapplied_at_start_as_light`: `restoreThemeChoice` hands `nightModeFor(choice)` to `NightModeSync`.
- `settings_switches_the_theme`: tapping Claro, Escuro or Modo Sol in Settings applies the brightness/palette at once, persists the choice, and hands the sync its night mode — with no restart.
- `tapping_the_resolved_segment_persists_it_when_no_choice_was_made`: before any explicit choice, tapping the segment already shown selected (the one the system brightness resolves to) persists that choice, rather than being swallowed as a no-op re-tap.
- `theme_selector_offers_only_three_options`: Settings shows Claro, Escuro and Modo Sol, and no "Sistema" segment.
- `sol_meets_the_56dp_tap_target_guideline`: Settings, rendered under `AppTheme.sun`, meets `sunTapTargetGuideline` (56 dp), a custom `MinimumTapTargetGuideline`.
- `AppTheme.sun` carries the sun palette and density extensions, padded tap targets, 64×56 button minimums, a 2 dp black outlined-button side, a borderless-shadow 2 dp-bordered card, and an 88 dp navigation bar with a black indicator and a white selected icon.
- Elevated/Outlined/TextButton render their label at the sun-scaled `labelLarge` (17 sp), as do FilledButton and SegmentedButton (through the ambient `TextTheme` rather than a theme-level override); the navigation bar's label renders at the sun-scaled `labelMedium` (14 sp); and the elevated button, FAB, snackbar and dialog all carry `elevation: 0`.
- `textThemeFor(AppPalette.sun)` returns the §1.2 parenthetical sizes for `titleMedium`, `bodyLarge`, `bodyMedium`, `bodySmall`, `labelLarge` and `labelMedium`; `light`/`dark` keep the base sizes.
- The existing appearance, settings and locale tests pass against the new `AppThemeChoice`-based provider and store shapes.

## Reproducibility

```sh
flutter test test/core/theme test/services/appearance_store_test.dart test/app_appearance_test.dart test/app_locale_test.dart test/features/settings
flutter analyze && flutter test && mf check
```

Flutter 3.44.1, Dart 3.12.1, `mf` v0.8.0.

## Risks and Assumptions

- Assumption: keeping the pre-existing "Alto contraste" switch (SPEC 0130) alongside Modo Sol, rather than retiring it now, is acceptable even though §0's divergence table frames Sol as superseding it — the Trello card and this PR's acceptance criteria scope only `AppTheme.sun` and the selector, and the switch's own copy/caption is untouched by the redesign's Settings inventory (§3.11) until that section's PR lands. If this reads as wrong scope, the question is: **should "Alto contraste" be removed from Settings now that Modo Sol exists, or left for the PR that rewrites Settings' full section layout (§3.11, PR 12)?** This spec takes the latter, safer option — nothing is removed.
- Assumption: a `SegmentedButton`'s rendered row height is driven by `style.padding` against its resolved label `textTheme`, not by `style.minimumSize` — confirmed by reading `segmented_button.dart`'s `_SegmentedButtonRenderWidget` layout, not by a public API guarantee; a future Flutter version could change this calculation.
- Risk: `_SettingsTile`'s new `minHeight` constraint is a minimal, single-widget application of `AppDensity` — it does not reach every tappable control in Settings by itself (icon buttons, switches) that already clear 56 dp through `AppTheme.sun`'s own button/icon-button themes; a future control added to Settings without going through `_SettingsTile`, a themed button, or a themed `Switch` could fall under 56 dp in Sol without failing any other suite's guideline check (only `sol_meets_the_56dp_tap_target_guideline` exercises it).
- What would invalidate this spec: a field report that Modo Sol's tap targets are not legible or reachable in direct sunlight despite meeting the 56 dp guideline, which would point to a problem the guideline's geometry check cannot catch (contrast under glare, glove use, one-handed reach).
