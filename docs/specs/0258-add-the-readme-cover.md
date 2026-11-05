# SPEC: docs(brand): add the readme cover and the logo files

## Problem

The README opens with badges and a title, and nothing shows what the app is. SPEC 0256 rewrote its text and left a cover out of its Scope. On 2026-11-04 the Developer compared three cover directions and chose the third, "Contemporary product: the guided camera": the app tile and wordmark beside a phone that shows the guided camera framing an A4 sheet.

The repository also holds no logo file a reader or a page can use. The mark exists as code (`VisioSoilMarkGeometry`, SPEC 0255) and as the launcher PNGs under `assets/branding/`, which are app assets sized for the launcher and bundled with the build.

## Design Decision

- New directory `docs/design/brand/`, under the `design/` entry `docs_layout_test.dart` already allows. Nothing under `docs/` is bundled into the app.
- Files, each SVG with a PNG exported from it:
  - `readme-cover.svg`, viewBox 1280 × 400, and `readme-cover.png`, 2560 × 800.
  - `logo-mark.svg` (the mark alone in primary `#4A7C59` on transparent) and `logo-mark.png`, 512 × 512.
  - `app-tile.svg` (the white mark at 80 % on a `#4A7C59` tile with rounded corners, as the launcher draws it) and `app-tile.png`, 512 × 512.
  - `logo-lockup-light.svg` and `logo-lockup-dark.svg`: the tile beside the wordmark, for light and dark backgrounds. Their PNGs are 4 times the viewBox.
  - `README.md`, listing the files, their colours and how they were made.
- The cover:
  - Left: the app tile, the wordmark "VisioSoil" in Inter Bold, two lines that say what the app does ("Photograph a soil sample on an A4 sheet." and "The phone estimates its texture class."), and three outline pills ("Guided camera", "4 texture classes", "Works offline").
  - Right, on a primary-container `#CCE8D4` panel: a flat phone with the guided camera. It shows the chips the camera shows (Luz, Distância, Foco, in the app's pt-BR), the sheet with corner brackets in A4 proportion, a soil disc about 9 cm across on that sheet as the capture guide asks (8 to 10 cm), the guidance line "Pronto. Segure firme." and the shutter.
  - Colours are the app's tokens. The cover carries its own background, so it reads the same in GitHub's light and dark themes, with transparent rounded corners and a hairline border so its edge shows on a white page.
  - It states no accuracy, no metric and no result. ADR 0026 holds those back until real photographs are classified.
- All text is converted to outlines from the app's own `assets/fonts/InterVariable.ttf`, shaped by HarfBuzz with the features the app sets (`cv11`, `ss01`) at the weight each line uses. An SVG shown through `<img>` cannot load a font, so live text would fall back to whatever the reader's system has.
- No SVG links anything outside itself: no `<text>`, no `<image>`, no remote reference.
- The README shows the cover as its first element, above the badges, as an image with alt text that says what the cover says.
- `docs/README.md`'s `design/` row names `brand/`.
- A guard, `test/standards/brand_assets_test.dart`:
  - `readme_opens_with_the_cover`: the README's first line shows `docs/design/brand/readme-cover.svg` with non-empty alt text, and the file exists.
  - `brand_svgs_are_self_contained`: no SVG under `docs/design/brand/` holds `<text`, `<image`, `@font-face` or an `http` reference other than its XML namespaces.
  - `every_brand_svg_draws_the_app_mark`: each SVG's `mark` group holds the ring, the three grains and the handle at `VisioSoilMarkGeometry`'s numbers.
  - `every_brand_png_has_its_declared_size`: each PNG exists with the size above, read from its header.

## Alternatives Considered

- **Live text in the SVG with a font stack.** Rejected: the mock showed the reader's system fonts replacing the face, and the cover would differ on every machine.
- **The PNG in the README.** Rejected: the SVG stays sharp at any width and is a fraction of the size. The PNG is kept for places that do not render SVG.
- **Commit the script that outlines the text.** Rejected for now: it would add a Python tool with HarfBuzz outside `ml/` and `corpus/`, the only two Python builds the repository has. The SVGs are the source and can be edited by hand. Changing a line of text needs the outlining step again, and `docs/design/brand/README.md` records how.

## Scope

- Includes:
  - the files under `docs/design/brand/`;
  - the cover line at the top of `README.md`;
  - the `design/` row of `docs/README.md`;
  - the guard.
- Does NOT include:
  - any app asset, launcher icon, code, colour token or screen;
  - the repository's GitHub avatar, social preview, description or topics, which are public settings;
  - any other text of the README.

## Acceptance Criteria

- The four tests of `brand_assets_test.dart` fail before the files exist and pass after.
- `docs_layout_test.dart`, `docs_links_resolve_test.dart` and `readme_adr_index_test.dart` pass.
- No produced text holds U+2013 or U+2014.
- The README renders the cover on GitHub in the light and the dark theme. The Author checks this in a browser and the pull request records it.
- `flutter test` shows no failures beyond those this machine has on `main`, and `mf check` passes.

## Reproducibility

Flutter 3.44.1 / Dart 3.12.1 in CI. Run `flutter test test/standards/brand_assets_test.dart test/standards`, then `flutter test` and `mf check`. The outlines were made with `uharfbuzz` 0.57.0 and `fontTools` 4.68.0 from `InterVariable.ttf`, and the PNGs were rendered from the SVGs by headless Chrome at device scale factor 2 (cover) and 4 (logos).

## Risks and Assumptions

- **The cover goes stale.** It draws the guided camera, so a change to the camera's chips or guidance should update it. The cover is a drawing, not a screenshot, which makes the drift a judgement rather than a test failure.
- **A reader's dark theme.** The cover keeps its light background in both themes, by design, so it looks like a card. The hairline border is what shows its edge on GitHub's white page.
- **Assumption:** "Works offline" is true of the analysis and the tips. Sign-in and geocoding use the network, and the cover does not claim otherwise.
