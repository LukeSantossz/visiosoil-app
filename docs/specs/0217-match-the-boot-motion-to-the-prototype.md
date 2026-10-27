# SPEC: feat(splash): match the boot's motion to the prototype's "Peneira"

## Problem

On 2026-10-26 the Developer reported that the opening animation differs from the original plan. The approved prototype (`docs/design/prototipo-v11/app.html`, boot "v5", which "v6" fixes as the only boot: "boot: sempre Peneira") and PNG 01, its last frame, disagree with the boot SPEC 0193 built from §6.2's prose.

| | App (SPEC 0193) | Prototype and PNG 01 |
|---|---|---|
| Start | Already green | The app background, as the native launch window draws it. A green circle opens from the logo's lens to fill the screen in 420 ms. |
| Sieve | A round wire mesh in the upper half, with 20 grains that fall into it and stay on screen | A full-screen grid of white dots in the logo's three grain sizes. It ripples out from the lens, peaks at 22 %, and fades, leaving PNG 01's clean field. |
| Logo | 64 dp. It fades in whole at 250 ms. | 88 dp, its box 96 dp above the centre. It assembles: the three grains pop in, then the ring draws, then the handle. |
| Text | Rises with the logo | The name rises at 960 ms and the tagline at 1040 ms |
| "Pular" | Visible and white from the start | Fades in at 300 ms. It turns white with the green at 180 ms. |
| Hand-off | A Hero toward Home's app bar, where no logo is, so nothing flies | The boot slides up and away while Início rises 48 dp into place |

## Design Decision

The boot follows the prototype's "Peneira" timeline and geometry. PNG 01's measured type stays as SPEC 0207 set it. Times are from the boot's start, and easings are the `AppMotion` curves the prototype names.

- **Backdrop.** The boot starts on `background`. A layer of `bootBackground`, with SPEC 0207's contours on it, is revealed through a circle centred on the lens.
  - The circle grows from 0 to the screen's farthest corner over 0–420 ms, `emphasizedDecelerate`.
  - Modo Sol draws no contours.
- **Sieve.**
  - **Grid:** white dots on a 30 dp hexagonal grid, alternate rows offset by 15 dp, with radii 4.8, 3.4 and 2.2 dp by `(row + 2·column) mod 3`.
  - **The logo's space:** no dot falls inside the ellipse `hypot(0.8·dx, dy − 40) < 120` about the lens.
  - **Each dot:** it starts at 120 ms plus 380 ms times its distance from the lens over the farthest distance, and lasts 900 ms, eased `standard`.
  - **A dot's 900 ms:** it scales from 0 to full while fading to 22 % (to 35 % of the way), holds there (to 70 %), then scales to 40 % and fades out.
- **Mark** (88 dp; the column's top is 96 dp above the screen's centre):
  - **Grains:** each pops from 0 to full size and opacity over 300 ms, `emphasizedDecelerate`, at 420, 500 and 580 ms, largest first.
  - **Ring:** draws over 560–980 ms, `emphasized`, starting at its leftmost point and running through the bottom.
  - **Handle:** draws over 880–1060 ms, `standardDecelerate`.
- **Text.**
  - "VisioSoil" rises 8 dp and fades in over 960–1260 ms, 20 dp under the mark.
  - The tagline does the same over 1040–1340 ms, 4 dp under the name.
  - Both use `standardDecelerate`.
- **"Pular."**
  - It fades in over 300–500 ms and turns from `primaryText` to white over 180–380 ms.
  - It keeps its place, its type and its 48 dp target, and still ends the boot at once.
- **Hand-off.**
  - At 1400 ms the boot routes on, to Início or the onboarding, with a transition only the boot uses.
  - The boot's last frame, without the dots, slides up by the screen's height over 380 ms, `emphasizedAccelerate`.
  - From 60 ms in, the screen beneath rises from 48 dp below over 480 ms, `emphasizedDecelerate`.
  - "Pular" uses the same hand-off.
- **Reduced motion is unchanged:** the static logo fades in over 150 ms and routes on with no transition (§6.2, §6.5).
- The logo Hero and its tag are removed, since nothing receives them (SPEC 0203).

## Alternatives Considered

- **Keep SPEC 0193's mesh and falling grains, and only hide them at the end.** Rejected. The prototype is the approved motion, and PNG 01 is its last frame; the mesh and grains appear in neither.
- **Keep the Hero.** Rejected: Início draws no logo (PNG 08), so the Hero has no destination.

## Scope

- Includes:
  - `SplashScreen`, its painters and its hand-off transition;
  - the two routes' page builders, used only when the boot routes on;
  - removal of the logo Hero tag;
  - the boot's tests.
- Does NOT include:
  - the native launch window (SPEC 0089), which already draws the app background the boot starts from;
  - the prototype's status bar recolouring, which the system draws.

## Acceptance Criteria

- `boot_starts_on_the_background_and_opens_green`:
  - at 0 ms the boot shows `background` with no green;
  - by 420 ms the green layer covers the screen.
- `boot_sieve_dots_ripple_and_clear`:
  - at 600 ms the sieve paints dots;
  - at 1400 ms none is visible.
- `boot_mark_assembles`:
  - the mark is 88 dp, with its top 96 dp above the centre;
  - at 500 ms the ring is not yet drawn;
  - at 1100 ms the whole mark is drawn.
- `boot_text_rises_after_the_mark`: the name is transparent at 900 ms and opaque at 1300 ms.
- `boot_hands_off_by_sliding_up`:
  - at 1400 ms the boot routes on;
  - mid-transition the curtain is above its rest position;
  - the target sits below its rest position;
  - after 540 ms only the target remains.
- Existing guarantees hold:
  - routing commits by 1.6 s;
  - "Pular" routes at once;
  - first launch routes to the onboarding;
  - the boot never vibrates;
  - reduced motion runs one 150 ms fade;
  - Modo Sol draws no contours;
  - the accessibility guidelines pass.

## Reproducibility

Flutter 3.44.1, Dart 3.12.1. Run `flutter test`, `flutter analyze` and `mf check`.

## Risks and Assumptions

- The boot's visible end moves from 1.2 s to 1.94 s, counting the hand-off's 540 ms; routing still commits at 1.4 s. §6.2 gives "≈ 1,6 s" for the entrance, and the prototype it was written against ends at the same 1.94 s.
- The dot grid has about 400 dots on a phone. They are painted by one `CustomPainter` under a `RepaintBoundary`, never one widget per dot.
