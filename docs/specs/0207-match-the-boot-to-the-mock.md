# SPEC: feat(splash): match the boot to the redesign mock

## Problem

The Developer asked on 2026-10-26 that every screen follow the redesign v11 mocks "fielmente e estritamente" ("faithfully and strictly"). The boot (SPEC 0193) differs from PNG 01:

- **Background.** The boot is plain green under the falling grains. PNG 01 draws two clusters of contour lines in a faint white: around the top right, and around the bottom left. It also scatters small dots.
- **Wordmark.** "VisioSoil" is set at 28 sp, weight 800. The mock sets it at 32 sp, weight 700, with −0.025 em tracking.
- **Tagline.** "Análise de textura do solo" is 14 sp. The mock's is 16 sp.
- **"Pular".** It is the theme's 15 sp label. The mock's is 17 sp, weight 600, white.

## Design Decision

Measured on the 2× PNG 01.

- **Contours.** A static painter under the grains draws two sets of irregular closed rings, 1 dp white at 12 %:
  - 12 rings around a point at 77 % of the width and 17 % of the height;
  - 10 rings around a point at 10 % of the width and 90 % of the height;
  - 14 dots of 2 dp at white 15 %, placed by a fixed seed.

  Modo Sol draws neither, as it draws no decoration (§1.5). Reduced motion keeps them, since they do not move.
- **Wordmark.** `headlineLarge` (32/40, weight 650), resized to weight 700, white, tracking −0.8.
- **Tagline.** `bodyLarge` at 16/24, white.
- **"Pular".** 17 sp, weight 600, white, keeping its 48 dp target.
- The logo, its Hero, the grains, the timing and the skip behaviour are unchanged.

## Alternatives Considered

- **Trace the mock's exact contour paths.** Rejected: generated rings at the mock's density, tint and placement read the same, with no path data to maintain.

## Scope

- Includes: `SplashScreen`'s background painter and text styles.
- Does NOT include: the boot's motion (SPEC 0193).

## Acceptance Criteria

- `boot_draws_contours`:
  - the boot paints a contour layer in the light theme;
  - it paints none in Modo Sol.
- `boot_text_matches_the_mock`:
  - "VisioSoil" is 32 sp at weight 700;
  - "Análise de textura do solo" is 16 sp;
  - "Pular" is 17 sp at weight 600.
- Existing tests pass.

## Reproducibility

Flutter 3.44.1, Dart 3.12.1. Run `flutter test`, `flutter analyze` and `mf check`.

## Risks and Assumptions

- The contours are generated, so they match the mock's density and tint rather than its exact paths.
