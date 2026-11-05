# SPEC: chore(assets): remove the font files no style uses

## Problem

`pubspec.yaml` declares three font families, and the app sets one:

- `AppTypography` sets every style in `InterVariable` (`lib/core/theme/app_typography.dart`), and nothing else in `lib/` names a font family.
- `Manrope` (`Manrope-Bold.ttf`, `Manrope-ExtraBold.ttf`, 190 KB) was retired by SPEC 0201, whose Scope left the files in place.
- `Inter` (`Inter-Regular.ttf`, `Inter-Medium.ttf`, `Inter-SemiBold.ttf`, 976 KB) are the static faces SPEC 0201 replaced with the variable font, because they lack the `cv11` single-storey "a" the design sets.

Flutter bundles every declared font into each build, so about 1.2 MB of fonts ship in every APK and iOS build with no style reading them. `registerFontLicenses` registers the Inter OFL and nothing for Manrope, so Manrope also ships with no license entry. The only reader of the static Inter faces is a test, `analysis_tile_test.dart`, which loads them next to the variable font to measure glyph widths.

## Design Decision

- Remove the `Manrope` and `Inter` families from `pubspec.yaml`, and delete their five `.ttf` files.
- Keep `InterVariable.ttf` and `Inter-OFL.txt`. The OFL covers the variable font too, and `registerFontLicenses` keeps registering it under `Inter`, which is the typeface's name.
- `analysis_tile_test.dart` loads only `InterVariable.ttf`, under the family `InterVariable`. That is the face the app draws with, so the fit check measures what a device renders.
- A new guard, `test/core/theme/bundled_fonts_test.dart`:
  - `every_bundled_font_family_is_the_one_the_styles_set`: the families `pubspec.yaml` declares are exactly the family `AppTypography` sets.
  - `every_font_file_is_declared_and_every_declared_file_exists`: the font files under `assets/fonts/` are exactly the ones `pubspec.yaml` declares, so an orphaned file and a dangling declaration both fail.

## Alternatives Considered

- **Keep the files for a future display face.** Rejected: SPEC 0201 rejected a second typeface, and a file with no caller is an asset ahead of its need. Git history keeps them.
- **Add a Manrope license entry instead.** Rejected: it would license a font nothing draws.

## Scope

- Includes:
  - the `fonts:` block of `pubspec.yaml`;
  - deleting `Manrope-Bold.ttf`, `Manrope-ExtraBold.ttf`, `Inter-Regular.ttf`, `Inter-Medium.ttf` and `Inter-SemiBold.ttf`;
  - `analysis_tile_test.dart`'s font loading;
  - the new guard.
- Does NOT include:
  - any change to `AppTypography`, any style, size, weight or feature;
  - `InterVariable.ttf`, `Inter-OFL.txt` or `registerFontLicenses`;
  - any other asset.

## Acceptance Criteria

- `every_bundled_font_family_is_the_one_the_styles_set` fails on `main` and passes after the change.
- `every_font_file_is_declared_and_every_declared_file_exists` passes before and after.
- `analysis_tile_test.dart`, `font_licenses_test.dart`, `app_typography_test.dart` and `shared_chrome_test.dart` pass.
- `flutter analyze` reports no issues.
- `flutter test` shows no failures beyond those this machine has on `main`.
- `mf check` passes.

## Reproducibility

Flutter 3.44.1 / Dart 3.12.1 in CI. Run `flutter test test/core/theme/bundled_fonts_test.dart test/core/widgets/analysis_tile_test.dart test/font_licenses_test.dart`, then `flutter test`, `flutter analyze` and `mf check`.

## Risks and Assumptions

- **A screen falls back to a system font.** Only if a style names `Manrope` or `Inter`. None does: `AppTypography._family` is the only family in `lib/`, and the guard pins the declared families to it.
- **The fit check moves.** `analysis_tile_test.dart` loaded the static faces into the `InterVariable` family as well, so a weight could resolve to a static face. Loading only the variable font measures the face the app draws, which may move a width by a fraction of a pixel. The test's scenarios have margin for that, and the run is the check.
