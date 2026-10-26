# SPEC: feat(theme): match the shared chrome to the redesign mocks

## Problem

The Developer asked on 2026-10-26 that every screen follow the redesign v11 mocks (`docs/design/spec/telas/`) strictly. Three parts of the chrome every screen shares differ from all of them:

- **Typeface.** Headlines and the app bar title are set in Manrope. The mocks set every text in Inter (§1.2).
- **App bar.** The title is centred. The mocks place it at the left, 60 dp from the edge after the back arrow, or 16 dp without one, in Inter 600 at about 20 sp.
- **Icons.** The app draws Material icons. The mocks draw Lucide icons (§5).

## Design Decision

- **Typography.** Every `AppTypography` style uses the bundled InterVariable, and Manrope is retired.
  - The mocks set Inter's single-storey "a" (`cv11`), which the bundled static Inter files do not carry. They are also rendered at an optical size equal to the font size, as a browser does.
  - Each style therefore sets the `opsz` axis to its size, clamped to 14–32, and its weight through `fontWeight`, which the engine maps to the `wght` axis.
  - Only a weight between the named ones (650) names `wght` itself, and `AppTypography.weighted` sets such a weight on a derived style.
  - Measured against the mocks this way, text widths match within 1 %.
  - `headlineLarge` and `headlineSmall` move to Inter at weight 650, 32/40 and 22/28, with tracking −0.025 em.
  - `titleLarge`, the app bar title, becomes Inter 600 20/28 with tracking −0.025 em, measured from the mocks' "Resultado" and "Histórico".
  - `titleSmall` becomes Inter 600 14/20.
- **App bar.**
  - `VisioAppBar` and the theme's `AppBarTheme` place the title at the start.
  - The title spacing is 4 dp after a leading widget or an implied back button, which puts the title 60 dp from the edge. Without one it is 16 dp.
  - The back button draws Lucide's `arrowLeft`, through the theme's `ActionIconThemeData`, so every pushed route gets it.
  - The bar is 64 dp tall and drawn over the screen's own background, with no surface band or tint, as in the mocks.
- **Icons.** The `lucide_icons_flutter` package is added. This change converts the icons every screen shares:
  - the back arrow;
  - the bottom bar and rail destinations: `house`, `history`, `lightbulb` and `user`.

  Each screen's own icons move to Lucide in that screen's fidelity change.

## Alternatives Considered

- **Export only the SVGs the mocks use into an app font.** Rejected for now: the package already ships the font, release builds tree-shake unused glyphs, and a hand-built font needs its own build step.
- **Keep Manrope for display sizes.** Rejected: §1.2 names Inter for every role, and the mocks show no second typeface.

## Scope

- Includes:
  - `AppTypography`;
  - `AppTheme`'s app bar and back button;
  - `VisioAppBar`;
  - the main navigation icons;
  - the new dependency.
- Does NOT include:
  - Each screen's layout and its own icons. Those follow in one change per screen group: result, main tabs, onboarding, and camera.

## Acceptance Criteria

- `every_style_is_inter`: every style of `AppTypography.textThemeFor(AppPalette.light)` has an Inter family.
- `every_style_is_the_variable_inter_at_its_optical_size`: the styles are InterVariable, with `opsz` equal to their size.
- `app_bar_title_matches_the_mock`: `titleLarge` is 20 sp, weight 600.
- `app_bar_title_starts_left`:
  - a `VisioAppBar` title starts 16 dp from the left edge without a leading widget;
  - it starts 60 dp from the edge on a pushed route with the back button;
  - the bar is 64 dp tall;
  - the back button draws `LucideIcons.arrowLeft`.
- `main_navigation_draws_lucide`: the four destinations draw `LucideIcons.house`, `history`, `lightbulb` and `user`, in the bar and in the rail.
- Existing tests pass, updated only where they pinned a Material icon this change replaces, or a centred title.

## Reproducibility

Flutter 3.44.1, Dart 3.12.1. Run `flutter test`, `flutter analyze` and `mf check`.

## Risks and Assumptions

- The Developer asked on 2026-10-26 for the screens to follow the mocks "fielmente e estritamente".
- The sizes are read from the 2× mock PNGs and matched against Inter's metrics, so they can be a sub-pixel off.
