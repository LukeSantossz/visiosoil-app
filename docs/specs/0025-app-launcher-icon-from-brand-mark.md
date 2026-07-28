# SPEC: feat(brand): use the VisioSoil mark as the app launcher icon

## Problem

The app ships Flutter's default placeholder launcher icons on Android (mipmap
`ic_launcher.png`) and iOS (`AppIcon.appiconset`). The design system's brand-logo
guideline defines the app "capa" as the official VisioSoil mark in white,
centered on the primary green tile (`--vs-primary: #4A7C59`), the mark occupying
about 60% of the tile.

## Design Decision

Reuse the exact geometry already painted by `VisioSoilLogo` as the single source
of truth for the icon, so the launcher icon and the in-app mark can never drift.
Expose the painter's draw routine as a top-level `paintVisioSoilMark(Canvas,
Size, Color)` in `visio_soil_logo.dart` and have `_VisioSoilLogoPainter.paint`
delegate to it (no behavior change to the widget).

Generate the icon source images with Flutter's own rasterizer
(`PictureRecorder` → `Picture.toImage` → PNG) rather than an external tool
(ImageMagick is unavailable on the dev machine), driving the same
`paintVisioSoilMark`. The generator is an environment-gated test
(`GENERATE_ICONS=1`) so it runs locally to (re)produce the committed PNGs and is
skipped in CI, keeping CI free of any headless-rasterizer dependency.

Produce and commit two source images:

- `assets/branding/app_icon.png` — 1024×1024, filled `#4A7C59`, white mark
  centered at 60% of the tile (iOS icon and legacy Android icon).
- `assets/branding/app_icon_foreground.png` — 1024×1024, transparent, white mark
  centered within the Android adaptive safe zone (~50% of the tile), paired with
  a solid `#4A7C59` background layer.

Wire `flutter_launcher_icons` (dev dependency) to fan those sources out into the
Android mipmaps + adaptive icon and the iOS `AppIcon` set, and commit the
generated artifacts (CI does not run the generator).

## Alternatives Considered

- **Draw the icon with the `image` package (pure Dart, no engine):** rejected —
  its stroked-ring and round-cap-line primitives do not match `Canvas` stroke
  semantics, so the icon would diverge subtly from the in-app mark; reusing the
  real painter via `toImage` reproduces it exactly.
- **Duplicate the mark geometry in a standalone generator:** rejected — two
  copies of the coordinates drift; delegating both the widget and the generator
  to one `paintVisioSoilMark` keeps a single source of truth.
- **Hand-author each icon size:** rejected — error-prone and unmaintainable
  versus generating from one 1024 master.

## Scope

- Includes:
  - Extract `paintVisioSoilMark(Canvas, Size, Color)` in `visio_soil_logo.dart`;
    `_VisioSoilLogoPainter.paint` delegates to it (no visual change).
  - An environment-gated generator test that writes
    `assets/branding/app_icon.png` and `assets/branding/app_icon_foreground.png`
    from `paintVisioSoilMark`.
  - `flutter_launcher_icons` dev dependency + config (`android: true`,
    `ios: true`, `image_path` = the green tile, `adaptive_icon_background:
    "#4A7C59"`, `adaptive_icon_foreground` = the transparent mark,
    `remove_alpha_ios: true`).
  - The regenerated, committed Android launcher icons (mipmaps + adaptive XML +
    foreground/background) and iOS `AppIcon` set.
  - A CI-safe guard test that decodes the committed `app_icon.png` and asserts it
    matches the design-system tile.
- Does NOT include:
  - Any change to the in-app `VisioSoilLogo` rendering or its call sites.
  - A new runtime asset (the two PNGs are generation inputs, not bundled assets).
  - Splash/onboarding artwork, notification icons, or the monochrome themed-icon
    layer (Android 13 `monochrome`).
  - Changing the app display name or bundle identifiers.

## Acceptance Criteria

- shared_paint_reused: `_VisioSoilLogoPainter.paint` and the icon generator both
  call `paintVisioSoilMark`; the widget still renders identically (existing
  `visio_soil_logo_test.dart` stays green).
- committed_icon_matches_ds: decoding `assets/branding/app_icon.png` yields a
  1024×1024 image whose corner pixel is `#4A7C59` and whose central region
  contains white pixels (the mark).
- adaptive_config_present: `pubspec.yaml` declares `flutter_launcher_icons` with
  `adaptive_icon_background: "#4A7C59"` and both source images.
- generated_icons_replaced: the committed Android adaptive resources
  (`mipmap-anydpi-v26/ic_launcher.xml` + foreground) and the iOS
  `Icon-App-1024x1024@1x.png` are the mark-on-green, not the Flutter default.
- analyze_clean: `flutter analyze` reports no new issues.
- build_green: CI `build` (Android release) and `build-ios` jobs pass.

Verification note: the rendered launcher icon on a device home screen is verified
by inspection on the Android emulator and iOS simulator, per the accepted
inspection precedent (specs 0007/0009/0024). The committed-PNG guard test proves
the source image's dimensions and design-system colors automatically; the
generator itself is not run in CI (it needs the local rasterizer).

## Reproducibility

- Toolchain: Flutter 3.44.1 / Dart 3.12.1 (pinned per `ci.yml`).
- Regenerate sources: `GENERATE_ICONS=1 flutter test test/tools/generate_app_icon_test.dart`.
- Regenerate platform icons: `dart run flutter_launcher_icons`.
- Verify: `flutter analyze && flutter test`, then `flutter build apk --release`.
- Tile spec source: the design system's `brand-logo.card.html`
  (`.mark { background: var(--vs-primary); color: #fff }`, `.mark svg { width:
  60% }`) and `tokens/colors.css` (`--vs-primary: #4A7C59`).

## Risks and Assumptions

- Assumption: `Picture.toImage` rasterizes under `flutter test` on the dev
  machine. Invalidated if it throws headless; mitigated because the generator is
  local-only and its output (the committed PNGs) is what CI and the guard test
  consume — CI never calls `toImage`.
- Assumption: a `flutter_launcher_icons` release resolves under Dart `^3.11.0`
  and does not force the SDK floor upward (mirroring the #153 constraint). The
  exact version is pinned at implementation and confirmed by `flutter pub get`
  leaving `environment.sdk` untouched.
- Assumption: the mark at 60% of the tile (full icon) and ~50% (adaptive
  foreground) reads well at small home-screen sizes; validated by inspection and
  adjustable via the two size constants if it reads too heavy or too small.
