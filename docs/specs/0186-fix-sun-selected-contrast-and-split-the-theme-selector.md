# SPEC: fix(theme): fix Sol's selected-segment and badge contrast, split the theme selector

## Problem

Three divergences from the redesign surfaced in QA of #415 (`/tmp/qa.md`
items 1, 4, 5, 9, 10): in Modo Sol, the theme `SegmentedButton`'s selected
segment and the `ConfidenceBadge`'s pill both paint white-on-white and
disappear; in Claro/Escuro, the selected segment uses a brown
`secondaryContainer` instead of the mock's green `selected` token; and
Settings offers no way back to following the system once a theme is chosen,
while also keeping the legacy "Alto contraste" switch the redesign's
Configurações inventory (v11 §3.11) does not show.

## Design Decision

Fix the two contrast bugs in place, and replace SPEC 0182's three-way
Claro/Escuro/Modo Sol selector with the layout v11 §3.11's own screens show
(`23-configuracoes.png`): a Sistema | Claro | Escuro segmented control,
defaulting to Sistema, plus a separate Modo Sol switch that overrides
whichever of the three is chosen. The legacy "Alto contraste" switch
(SPEC 0130) is removed from Settings, since Modo Sol now covers that need and
the §3.11 screens never show both at once; the platform's own high-contrast
accessibility signal keeps working through `highContrastTheme`/
`highContrastDarkTheme`, which was never tied to that switch.

**Contrast fixes:**
- `AppTheme`'s shared `_build` (`lib/core/theme/app_theme.dart`) gains a
  `segmentedButtonTheme` whose selected segment paints `AppPalette.selected`
  (the mock's green token) instead of M3's default `secondaryContainer`,
  with `onPrimaryContainer` text — both reached through `backgroundColor`/
  `foregroundColor` `WidgetStateProperty`s that replicate the M3 default's
  disabled/unselected branches, since setting either property replaces the
  default's whole resolver rather than layering over one state.
- `AppTheme.sun`'s own `segmentedButtonTheme` override gets the same two
  properties, but with its own black-fill/white-text pair instead of
  `AppPalette.sun.selected` (white, identical to the unselected fill, which
  is the bug): the selected segment needs an explicit pair unrelated to that
  token to clear the Sol-wide >=7:1 floor (v11 §8).
- `ConfidenceBadge` (`lib/core/widgets/confidence_badge.dart`) adds a 2 dp
  black `Border` to its pill's `BoxDecoration` whenever
  `context.palette.isSun`, covering all three levels (primary/warning/error
  container) through the one `Container` they share, matching every other
  Sol surface's 2 dp black border in place of a shadow (v11 §1.1, §1.5).

**The theme selector split** (`lib/core/services/appearance_store.dart`,
`lib/providers/appearance_provider.dart`, `lib/main.dart`,
`lib/core/features/settings/settings_screen.dart`):
- `AppearanceStore` drops `AppThemeChoice` and its `readThemeChoice`/
  `writeThemeChoice` entirely, replacing them with two independent reads:
  `readBaseThemeMode()` returning Flutter's own `ThemeMode` (`system` is
  already the fourth option the old enum deliberately excluded) and
  `readSunMode()` returning a `bool`. `nightModeFor(base, {required sun})`
  replaces the old single-argument version: `sun` forces `ThemeMode.light`
  over any `base`, `base` otherwise.
- `restoreAppearance` replaces `restoreThemeChoice`, reading both and handing
  their combined `nightModeFor` to `NightModeSync` in one call, the same
  single-call-before-`runApp` shape as before.
- **Migration**, read lazily and independently by each of the two new reads,
  so one does not need the other to have run first:
  - `appearance.baseThemeMode` / `appearance.sunMode` (new keys) take
    precedence when present.
  - Else `appearance.themeChoice` (SPEC 0182): `light`/`dark` migrates to
    that base with Sol off; `sun` migrates to Sol on with the base left at
    `system` — Sol used to replace the base choice outright, and now
    overrides it instead, so the base most consistent with "no explicit
    Claro/Escuro was ever made" is `system`, not a guess at which of Claro/
    Escuro the chooser meant.
  - Else `appearance.themeMode` (SPEC 0107, pre-0182): `light`/`dark`
    migrates to that base; `system` or nothing stored stays at the
    `ThemeMode.system` default, same non-write-on-no-choice behaviour SPEC
    0182 established.
  - Each migration write lands under the new key, so a later read no longer
    depends on the legacy one.
- `readHighContrast`/`writeHighContrast` and `restoreHighContrast` are
  deleted from `AppearanceStore`, along with `highContrastProvider`,
  `HighContrastController` and `initialHighContrastProvider`: nothing else
  called them once the switch reading them is gone.
- **Providers**: `baseThemeModeProvider`/`BaseThemeModeController` and
  `sunModeProvider`/`SunModeController` replace `themeChoiceProvider`/
  `ThemeChoiceController`. Each controller's `select` persists its own value
  and re-derives `nightModeFor` by reading the other provider's current
  state, so either can change independently while the platform sync always
  sees the combined result.
- **`VisioSoilApp`** (`lib/main.dart`): `theme`/`darkTheme` are `AppTheme.sun`
  when `sunModeProvider` is on, else plain `AppTheme.light`/`AppTheme.dark` —
  no manual high-contrast swap-in, since that switch is gone.
  `highContrastTheme`/`highContrastDarkTheme` are `AppTheme.sun` when Sol is
  on, else `AppTheme.lightHighContrast`/`darkHighContrast` as before: the
  platform's own high-contrast signal still reaches those two params exactly
  as SPEC 0130 wired them, and Sol still must not be knocked out by that
  signal while it is the explicit override (SPEC 0182's acceptance
  criterion, unchanged). `themeMode` is `nightModeFor(base, sun: sunMode)`.
- **Settings**: `_ThemeChoiceSelector` becomes a plain
  `SegmentedButton<ThemeMode>` over `{system, light, dark}`, labelled
  Sistema | Claro | Escuro, with no `emptySelectionAllowed` workaround —
  unlike SPEC 0182's selector, the state here is always a real stored value
  (`ThemeMode.system` by default), never a merely-resolved display value, so
  a re-tap of the current selection has nothing hidden to persist. A new
  `_SunModeSwitch` (`SwitchListTile`) carries the "Modo Sol" title and the
  caption SPEC 0182 put under the segmented control ("Alto contraste e
  letras maiores para o campo"), which describes Sol specifically and reads
  better next to its own switch than next to Sistema/Claro/Escuro.
  `_HighContrastSwitch` is deleted.

## Alternatives Considered

- **Keep SPEC 0182's three-way Claro/Escuro/Modo Sol selector and only fix
  its selected-segment colour.** Rejected: that still leaves no way back to
  following the system once any segment is tapped (QA item 5), which is a
  second, separate divergence from v11 §3.11's own screens, not a contrast
  bug a colour fix touches.
- **Give Sol its own `selected` token value instead of a black/white
  override.** Rejected: `AppPalette.sun.selected` is white by design, pairing
  with every other white container in that palette (primaryContainer,
  warningContainer, errorContainer); changing it would fix the segmented
  button but break anything else that reads `selected` expecting the
  palette's one white-container convention.
- **Keep "Alto contraste" alongside Modo Sol, deferring its removal (as
  SPEC 0182 did).** Rejected now: the redesign's own Configurações mock
  (`23-configuracoes.png`, QA item 10) never shows both at once, and with
  Modo Sol split into its own switch the two read as the same control
  twice — SPEC 0182's deferral was scoped to leaving the base/Sol split
  for a later change, and this is that change.

## Scope

- Includes:
  - `lib/core/theme/app_theme.dart`: shared `segmentedButtonTheme` in
    `_build`; `AppTheme.sun`'s own selected black/white override.
  - `lib/core/widgets/confidence_badge.dart`: the Sol border.
  - `lib/core/services/appearance_store.dart`: `nightModeFor(base, {sun})`,
    `readBaseThemeMode`/`writeBaseThemeMode`, `readSunMode`/`writeSunMode`,
    `restoreAppearance`; removal of `AppThemeChoice`,
    `readThemeChoice`/`writeThemeChoice`, `restoreThemeChoice`,
    `readHighContrast`/`writeHighContrast`, `restoreHighContrast`.
  - `lib/providers/appearance_provider.dart`: `baseThemeModeProvider`,
    `sunModeProvider` and their controllers; removal of `themeChoiceProvider`
    and `highContrastProvider` and their controllers.
  - `lib/main.dart`: restoring base + Sol before `runApp`; the simplified
    theme wiring.
  - `lib/core/features/settings/settings_screen.dart`: the split
    `_ThemeChoiceSelector`/`_SunModeSwitch`; removal of
    `_HighContrastSwitch`.
  - `lib/core/constants/app_strings.dart`: `themeChoiceSystem`.
  - Tests for each criterion below, and the existing appearance/settings/
    locale tests updated to the new provider and store shapes.
- Does NOT include:
  - §11's excluded items (fractions, top 3, talhão, the vibration indicator,
    the mock's fictional data) — none of them are touched by this change.
  - `AppTheme.lightHighContrast`/`darkHighContrast` themselves, or the
    platform-signal wiring that selects them (SPEC 0130) — unchanged, only
    the manual switch that used to sit beside Modo Sol is removed.
  - Rewriting Settings' full section layout to v11 §3.11's exact grouping
    (Perfil, Preferências, etc.) — PR 12's scope, same as SPEC 0182.
  - The ConfidenceBar's low-contrast warning fill against
    `surfaceContainerHigh` (QA item 7) and the warning token/text contrast
    divergences (QA items 2, 3) — separate colour-token questions, not this
    change's selected-state or selector-layout bugs.

## Acceptance Criteria

- `the_selected_segment_uses_the_palette_selected_token`: in `AppTheme.light`
  and `AppTheme.dark`, the segmented button's selected background is
  `AppPalette.selected`, not `secondaryContainer`.
- `the_selected_segment_is_black_with_white_text`: in `AppTheme.sun`, the
  segmented button's selected background is black and its selected
  foreground is white; the unselected pair is neither.
- `in_sol_the_pill_carries_a_2dp_black_border`: `ConfidenceBadge` under
  `AppTheme.sun` draws a 2 dp black border at every confidence level (high,
  moderate, low); outside Sol it draws none.
- `settings_switches_the_base_theme`: tapping Sistema, Claro or Escuro
  applies the brightness at once, persists under the new base key, and hands
  the sync its `nightModeFor`.
- `modo_sol_overrides_the_base_theme_and_turning_it_off_restores_it`: with a
  base already chosen, turning Modo Sol on applies and persists Sol without
  changing the stored base; turning it off restores the base's own
  brightness, still persisted.
- `theme_selector_offers_only_three_base_options`: Settings shows Sistema,
  Claro and Escuro in the segmented control, and Modo Sol only as its own
  switch, never as a fourth segment.
- `there_is_no_alto_contraste_switch`: Settings shows no "Alto contraste"
  row; the platform's own high-contrast signal still swaps in
  `AppTheme.lightHighContrast`/`darkHighContrast` (SPEC 0130's existing
  acceptance criteria, re-run against the new wiring).
- `a_spec_0182_light_or_dark_choice_migrates_to_the_base` /
  `a_spec_0182_sun_choice_migrates_to_sun_mode_with_a_system_base`: a store
  holding only SPEC 0182's `appearance.themeChoice` key reads as the
  equivalent base with Sol off for `light`/`dark`, and as Sol on with a
  `system` base for `sun`.
- `an_oldest_legacy_light_or_dark_choice_migrates` /
  `an_oldest_legacy_system_choice_does_not_migrate`: a store holding only
  SPEC 0107's oldest `appearance.themeMode` key (and nothing newer) migrates
  `light`/`dark` to the base, and leaves `system` or nothing stored at the
  `ThemeMode.system` default.
- `sol_is_reapplied_at_start_as_light_over_any_base`: `restoreAppearance`
  hands the platform `ThemeMode.light` when Sol is on, regardless of the
  stored base.
- The existing SPEC 0182 appearance/settings/locale acceptance criteria that
  still apply unchanged under the new shapes (first boot follows the system,
  live system brightness changes, Sol ignoring the platform's brightness and
  its own high-contrast signal, the 56 dp Sol tap-target guideline) keep
  passing.

## Reproducibility

```sh
flutter test test/core/theme test/core/widgets/confidence_badge_test.dart \
  test/services/appearance_store_test.dart test/app_appearance_test.dart \
  test/app_locale_test.dart test/features/settings
flutter analyze && flutter test && mf check
```

Flutter 3.44.1, Dart 3.12.1, `mf` v0.8.0.

## Risks and Assumptions

- Assumption: pairing the selected segment's text with `onPrimaryContainer`
  (light/dark) is an acceptable reading of "use the existing palette
  `selected` token" — the mock's `--sel` row in v11 §1.1 names only a
  background, not a paired `on` colour, and `onPrimaryContainer` is the
  closest existing token family (both are the green/selected side of the
  palette) rather than a new one invented for this change.
- Assumption: removing "Alto contraste" now, rather than deferring it again
  as SPEC 0182 did, is the right call because the redesign's own
  Configurações screens (§3.11) never show it beside Modo Sol — if a reviewer
  disagrees, the switch and its store/provider plumbing are a straightforward
  revert, since nothing else in this change depends on their absence.
- Risk: a device with a SPEC 0182-era `appearance.themeChoice=sun` value
  migrates to `sun=true` with `base=system`, not to whichever of Claro/Escuro
  that device's platform brightness happened to resolve to at the time Sol
  was chosen — a user who chose Sol over an explicit Claro now gets Sistema
  underneath instead of Claro once they turn Sol off. SPEC 0182 itself did not
  preserve a pre-Sol base either (choosing Sol discarded whatever Claro/Escuro
  was active before it), so this migration does not regress a guarantee that
  existed; it is a new one-time default for that one migration path.
- What would invalidate this spec: a field report that Modo Sol's switch
  position is lost across a restart despite its own tap-target and contrast
  guidelines passing, which would point to a provider/store wiring gap this
  spec's guideline and round-trip tests do not reach (e.g. a platform restart
  path that skips `restoreAppearance`).

## PR 416 QA follow-up: Sun base components

QA items 1–3 extend the Sun contrast fixes to the merged base components.
Using `context.palette.isSun`, `SegmentedControl` paints its selected indicator
black and its selected label and icon white (21:1 contrast, above the 7:1 floor).
`StatusPill` draws a 2 dp black border for every status, including the pending
pill reused by `AnalysisTile`. `ConfidenceBadge` retains the same border in
both full and compact variants at every confidence level. Widget tests cover
these Sun states. Light and dark rendering and QA items 4–8 are outside scope.
