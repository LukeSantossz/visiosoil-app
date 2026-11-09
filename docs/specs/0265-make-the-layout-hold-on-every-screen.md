# SPEC: fix(ui): make the layout hold on every screen and text size

## Problem

A layout audit of every screen on 2026-11-09 found three kinds of faults. Some screens overflow or overlap in landscape, on a 320 dp phone or at large text. The same thing goes by different names: "registro" and "análise", "Como capturar" and "Como fotografar". Sizes, spacing, radii, icons and colours sit off the theme's scales, and nothing stops new values from drifting away from them.

## Design Decision

The audit's findings are fixed in one change, grouped as below. Large text means a text scale of 1.3 or more, the threshold the app already uses (SPEC 0121). A short screen means an available height under 480 dp, which every phone in landscape is.

### 1. Layouts that break

- **Capture.** On a short screen or at large text, the capture body scrolls. The photo sits in a 4:3 box the width of the content, and the actions follow below it. Today's layout, with the photo filling what the actions leave, is kept on a tall screen at normal text.
- **Guided camera.** `GuidedCameraScreen.bottomInset` is fixed at 215 dp. The panel holding the chips, the shutter and the caption grows past that at large text, where the chips stack. The outline and the target are then drawn under the panel. The panel's laid-out height is measured after each layout, and the inset that `CaptureGuideLayout`, `alignSheet` and the pill's position read is the larger of that height and 215 dp. 215 dp stays the floor because the outline's size, and so the distance the user holds the phone from the sheet, follows the inset: a smaller panel must not move the sheet closer. To keep the panel near that floor, its text scale is capped at 1.3 and the chips stay in one row at every scale. The caption reads `labelMedium` from the theme instead of its own 12 sp `TextStyle`.
- **Settings, "Tamanho do texto".** At large text the segmented control moves below the row's title and spans its width, instead of sitting beside a title squeezed to a quarter of the row.
- **History filter chips.** The chip's minimum target is `context.density.tap`, so Modo Sol's 56 dp applies. Today it is 40 dp in both modes, Material's 48 dp less the compact density's 8.
- **Statistics rows.** `StatsRow` itself stacks its cells at large text. Home's statistics grid already stacks this way and Profile's row does not. The grid's own `Column` goes away, so both screens share one rule.
- **Onboarding panel.** The art panel is 200 dp tall whenever the screen is 640 dp tall or less, whatever its width. On a short screen it is not drawn, so the step's text and actions keep the screen.
- **Image preview.** The photo is as tall as the screen is wide, capped at 60 % of the screen's height. Today it can be taller than the whole screen in landscape.
- **Compare.** Each photo is half the width square, capped at 40 % of the screen's height. While loading, the screen keeps its app bar and title, so the user can go back.
- **Details.** The triangle moves above its explanation when its section is narrower than 328 dp (a 360 dp screen less its two 16 dp margins) or at large text, instead of leaving the text about 120 dp. `ResultLattice` places its apex at the same fraction of the width as on the 360 dp mock, instead of at a fixed 260 dp. The details body is not capped at 560 dp, because the result overview already lays itself out in two columns from 600 dp.
- **Error, permission and route-error views.** Their content scrolls, so a short screen or large text does not overflow.
- **History collection grid.** It drops to one column at large text.
- **Home.** "Ver todas" no longer shifts 8 dp to the right with `Transform.translate`. When the row wraps at large text, that shift pushed it past the page's edge. The label lines up with the edge through the button's own padding instead.
- **One content width.** A new `ContentWidth` widget caps content at `AppLayout.maxContentWidth`, 560 dp, and centres it. It replaces the four separate 560 literals (Home, Settings, History, guided camera) and wraps the screens that have no cap today: capture, the capture guide, compare, and the error and permission views.

### 2. One name for each thing

The user-facing copy changes as follows. Identifiers, comments and stored values do not change.

| Where | Today | After |
|---|---|---|
| Capture screen title | Nova captura | Nova análise |
| Capture screen help action, capture guide title, Settings tile | Como capturar, Como fotografar a amostra | Como fotografar |
| Profile | a "Como fotografar a amostra" tile | removed; the guide is reached from Settings, the capture screen and the guided camera |
| Every user-facing string that names a saved result | registro, registros | análise, análises |
| Delete confirmation, single and multiple | Registro excluído., registro(s) excluído(s) | Análise excluída, N análises excluídas |
| Delete button and dialog | Excluir registro, Excluir registros | Excluir análise, Excluir análises |
| Empty capture preview | Selecione uma imagem | Fotografe a amostra |

The gender of the sentence follows the noun: for example, "Não foi possível carregar o registro." becomes "Não foi possível carregar a análise.". The capture screen's title is left-aligned, as on every other screen.

### 3. One scale for each value

- **Type.** Every font size in `lib/` is one of 11, 12, 14, 15, 16, 17, 18, 20, 22, 28, 32 and 40 sp: the sizes `AppTypography` defines, Modo Sol's included. An off-scale size snaps to the nearest one on the scale, and a tie goes to the larger. So 12.5 becomes 12, 13 becomes 14, 15.5 becomes 16, 24 becomes 22, and `pageTitle`'s 29 becomes 28. A snapped style keeps its line height in logical pixels. The exception is `share_content_builder.dart`, which draws the shared image, not the UI. `pageTitle` reads `headlineMedium` from the theme instead of resizing it.
- **Spacing.** Every `EdgeInsets` value, and every `SizedBox` that only makes a gap, is a multiple of 4 dp, or 1 or 2 dp for a hairline. An off-grid value snaps to the nearest multiple of 4, and a tie goes to the larger. So 10 becomes 12, 14 becomes 16, 6 becomes 8, 17 becomes 16, 169 becomes 168, 69 becomes 68, and 23.5 becomes 24. Where an `AppSpacing` token has that value, the token is used. Painters and their illustration geometry are out of this rule.
- **Radius.** Every corner radius outside `lib/core/theme/` is an `AppRadius` token. 3 becomes 4, 6 and 9 become 8, 10 becomes 12, and 14 becomes 16. Two kinds of radius are out of this rule: illustration painters (`_NoRecordsArt`, the onboarding art) and the confidence bar's 1.5/2 dp end caps, which belong to a bar 3 or 4 dp tall.
- **Icons.** Every Material `Icons.*` in `lib/` is replaced by its Lucide equivalent, the set the rest of the app already uses (43 distinct icons at 76 sites). For example, `error_outline` becomes `circleAlert`, `camera_alt` becomes `camera`, `refresh` becomes `refreshCw`, `warning_amber_rounded` becomes `triangleAlert`, `delete_outline` becomes `trash2`, `broken_image` becomes `imageOff`, `eco` becomes `leaf`, and `arrow_back` becomes `arrowLeft`. `confidence_level.dart`'s icons are included.
- **Colour.** A `Color(0x…)` literal appears only in `lib/core/theme/`, the Google brand widgets (`google_g_logo.dart`, `google_sign_in_button.dart`) and `share_content_builder.dart`. The guided camera's and the image preview's chrome colours (the private `_CameraInk`, the chips', shutter's and alert's hex values, and an icon button drawn over a photograph) move to a `CameraColors` class in the theme layer. `Colors.white` and `Colors.black` outside the camera, preview and splash surfaces, which are drawn over a photograph or the brand colour, read a palette role instead: Modo Sol's black edges read `onSurface`, its white text on black reads `background`, and the swipe-to-delete action's text and icon read a new `onDestructive` role. `Colors.transparent` stays everywhere. A colour inside a `CustomPainter` is illustration and out of this rule.

### 4. Guards

Each rule in section 3, and the single 560 dp width (a `maxWidth: 560` outside `AppLayout`), gets a source test under `test/standards/`, in the style of `no_fixed_palette_test.dart`. Each test strips comments, lists the offending `file:line`, and names the token to use. Without these guards, the next screen drifts again.

### What this supersedes

Some pixel values from earlier mock-fidelity specs move by up to 4 dp or 2 sp, and those specs stay as the record of what was decided then:

- SPEC 0202: Details at 169 dp.
- SPEC 0203: Home's 69 dp inset and its 17/43/25 gaps.
- SPEC 0206 and 0222: the onboarding panel's small-screen rule.
- SPEC 0212: the 17 dp tab gap.
- SPEC 0216: the 24 sp statistic.
- `pageTitle` at 29 sp.

The Developer chose the scale over the mocks' exact measurements on 2026-11-09.

## Alternatives Considered

- **One spec per screen.** Each would be easier to review, but there would be a dozen of them, and the shared rules (the scales, the guards, `ContentWidth`, the noun) would be split across them. The Developer asked for one.
- **Snap only radius and colour, and leave type and spacing at the mocks' values.** This keeps mock fidelity, but leaves most of the off-scale values in place and the guards with long exemption lists. Rejected by the Developer.
- **Keep the guide in Profile and drop it from Settings.** Settings is where the other how-the-app-works rows live. Profile is about the account and the collection.
- **A fixed, larger inset for the guided camera at large text.** A second constant would still be wrong on the next layout change. Measuring the panel follows it.

## Scope

- Includes:
  - the layout fixes in section 1;
  - the copy in section 2;
  - snapping every value in section 3, including `AppTypography.pageTitle`, and the guards in section 4;
  - `ContentWidth` and `AppLayout.maxContentWidth`;
  - `CameraColors`;
  - updating the existing tests that pin the old values or strings.
- Does NOT include:
  - new screens, new features, or changes to navigation or routes;
  - the shared image `share_content_builder.dart` draws;
  - painter and illustration geometry;
  - the README cover, the brand assets or the privacy pages;
  - stored data, the database schema, sync, the classifier or the corpus;
  - any identifier rename from "record" to "analysis";
  - iOS-specific layout.

## Acceptance Criteria

- A new layout matrix test pumps each screen it can build with fakes: Home, History, Details (classified and failed), Capture (empty and with a photo), Settings, Profile, every onboarding step, Image preview, Compare, the capture guide, and the error, permission and route-error views. The sizes are 320 × 568, 360 × 640 and 411 × 891 in portrait, plus 640 × 360 and 891 × 411 in landscape. The text scales are 1.0, 1.3 and 2.0. No combination raises a layout overflow or exception. Before the change the permission views fail it: the camera permission view in landscape at every text scale and on the small phone at 2.0, and the location permission view at 2.0 on the small phone and in landscape. The other screens pass it on `main`, so for them the matrix guards against regression, and their fixes in section 1 are checked by the tests below and on the device.
- Guided camera: at text scale 2.0 on 360 × 640, the outline's bottom edge is at or above the panel's top edge. This fails before the change, when the chips stacked.
- Settings: at text scale 1.3 the text-size control is laid out below its title and at least as wide as the title.
- History: in Modo Sol, a filter chip's hit target is at least 56 dp tall. In light mode it is at least 48 dp.
- Profile: at text scale 1.3 the three statistic cells are stacked.
- The copy in section 2 appears as written. No string literal in `lib/` (comments excluded) contains "registro". Profile has no guide tile, and Settings' tile reads "Como fotografar".
- The section 4 guards pass after the change, and each one fails on `main`.
- `flutter analyze` reports nothing new. `flutter test` shows no failures beyond those this machine has on `main`. `mf check` passes.
- The Author checks the release build on the phone, in portrait and in landscape, at normal and at the largest system text size, and the pull request records it.

## Reproducibility

Flutter 3.44.1 / Dart 3.12.1 in CI. Run `flutter test test/standards/`, the layout matrix test, `flutter test` and `mf check`. The matrix uses the bundled `InterVariable` font, not the default test font, because the default font is about 1.7 times as wide and would report overflows the app does not have.

## Risks and Assumptions

- **The change is large.** It touches about 50 files, and a regression can hide in it. Mitigated by the matrix test, the guards and the on-device check. Most files change under more than one section, so the commits cannot follow the sections; the pull request walks the change section by section instead.
- **The screens drift from the mocks by a few pixels.** Accepted by the Developer's choice of the scale.
- **"Análise" for a failed classification.** A record whose photograph was not classified is still called an "análise". Accepted: the attempt is the analysis, and the details screen says why it has no class.
- **The panel's text stops growing at 1.3.** At larger system text the chips and caption stay at 1.3 times their size. Accepted: the camera's three chips are short labels, and keeping the outline's size keeps the photographing distance the protocol relies on.
- **The measured inset can lag one frame.** On the first frame, and right after the text scale changes, the overlay uses the previous inset. Accepted: the next frame corrects it, and the shutter does not depend on the overlay's geometry.
- **Assumption:** every Lucide name the change uses exists in `lucide_icons_flutter` 4.0.1. The Author checked the ones listed above against the package.
