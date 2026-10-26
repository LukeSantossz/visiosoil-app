# SPEC: feat(capture): match the camera and the processing screen to the mocks

## Problem

The Developer asked on 2026-10-26 for "100% de fidelidade ao mock" ("100% fidelity to the mock"). Rendering the guided camera and the processing screen and comparing every line of ink with PNG 10 to 13 and 28 to 31 leaves these gaps.

### The camera (PNG 10, 11, 12, 28)

- **Top bar.**
  - The app draws a 54 % black band holding a back arrow, a 20 sp title and a Material info icon.
  - The mock draws no band. The preview runs to the top under a black scrim that fades out by 135 dp.
  - The bar holds a Lucide `x`, the title in `titleLarge`, and Lucide icons, laid out as `VisioAppBar` lays out every other screen.
- **Guidance.**
  - The app draws a 72 dp full-width banner tinted by tone, with an icon.
  - The mock draws a dark pill, black at 82 % and 28 dp tall, holding a 14 sp white sentence with no icon. It sits 12 dp above the frame.
- **Footer.**
  - The app's footer has 16 dp padding and quality chips at `labelLarge` and `bodySmall`.
  - The mock's footer is a black panel 215 dp tall from the bottom. Its chips are:
    - 51 dp tall, filled `#1C1C1C`, radius 8, with a 1 dp `#333333` edge;
    - led by a 16 dp Lucide `circleAlert` in the dark theme's `warning`, or a Lucide `check` in its `statusSent`;
    - labelled at 13 sp weight 600 in white, over a 12 sp value in `#BDBDBD`.
  - A ready chip's edge is `#3C5E46`, and a chip the shutter refused is 2 dp in `warning`.
- **Shutter.**
  - The app's is a 72 dp white disc in a 4 dp `primary` ring.
  - The mock's, while held, is a 4 dp `#666666` ring around a 4 dp gap and a 56 dp `#555555` disc.
  - Beside it, the camera switch is a 48 dp `#262626` disc holding a Lucide `refreshCw`, centred 64 dp from the right edge.
- **Caption.**
  - The app's line is 14 sp white.
  - The mock's is 12/16 in `#BDBDBD`, 12 dp under the shutter row and 28 dp above the screen's bottom.
- **Refusal card** (PNG 12).
  - The app's card sits inside the footer, on the theme's warning container.
  - The mock's floats 7 dp above the chips, 16 dp in from each side, on `#FFF4E2`, radius 12:
    - a 20 dp Lucide `circleAlert` in `#B26A00`;
    - the title at 14/19 weight 600 and the sentence at 13/17.5, both in `#3A2A10`.
  - The mock's sentence names the corrections in the chips' order and joins the last with "e". The app's names them in the order it found them, all joined by commas.

### Processing (PNG 13, 29, 30, 31; 38 in Modo Sol)

- **The triangle** sits 12.5 dp lower than the mock's.
- **The class chip.**
  - The app's chip is `titleMedium` on 8/4 padding.
  - The mock's is 12 sp weight 600 in `primaryText` on `selected`: 24 dp tall, 10 dp in from each side, radius 6.
- **The text.**
  - The app sets the title in `headlineMedium` (28 sp), the sentence in `bodyLarge`, and the disclaimer at full width.
  - The mock sets the title at 20 sp weight 600, the sentence at 14/20 in `onSurfaceVariant`, and the disclaimer at 12/16 in `textTertiary`.
  - The mock wraps the sentence and the disclaimer within 312 dp. That is the one width that breaks both lines where PNG 31 and PNG 38 break them.
  - The app also shows the phase line ("Classificando…") and a progress bar. The mock shows neither.
- **Modo Sol** (PNG 38).
  - The class chip has 14 sp weight 600 ink on white inside a 2 dp rule, so it is 28 dp tall.
  - The disclaimer and the triangle's labels stay at the light theme's 12 sp. The app's Modo Sol sets both at its enlarged 14 sp.
- **The lattice.**
  - The mock draws, behind the bar and the triangle, a large texture triangle ruled at 10 %:
    - its side is 346.4 dp and its apex is 130.25 dp left of the right edge, 41.6 dp above the screen's top;
    - its lines are 1 dp in `primary`, at the strength that gives `#D9E2D9` on the background;
    - the lines fade from full at 105 dp to nothing at 257 dp, the triangle's base.
  - The app draws none.

## Design Decision

Each value below is read from the 2× PNG, 2 px to the dp, as in SPEC 0210.

### The camera

- **Top bar.**
  - A `VisioAppBar` with a transparent background and white ink, over the preview.
  - A black scrim behind it fades from 90 % at the top to nothing at 135 dp.
  - Leading: Lucide `x`, labelled "Fechar".
  - Title: "Nova análise" in `titleLarge`.
  - Action: Lucide `info`, labelled "Como fotografar".
- **Guidance pill.**
  - Centred, 12 dp above the outline's top. The overlay reserves the bar and the pill above the outline, so the pill never covers the bar.
  - 14/20 white on black at 82 %, 12/4 padding, radius 8.
  - The tone stays in the chips and the brackets, which already show it.
- **Footer panel.**
  - Black, padded 16 dp on the sides and top and 28 dp at the bottom.
  - The chips; 20 dp; the 72 dp shutter row; 12 dp; the caption.
  - The overlay's bottom inset is the panel's height, so the outline stays above the panel.
- **`QualityChip`.**
  - 10/8 padding, with the measured fill, edges, icons and type above.
  - A refused chip's 2 dp edge takes 1 dp from the padding, so the chip stays 51 dp and the panel does not move.
  - "Ajustando…" keeps a Lucide `ellipsis` in `#BDBDBD`.
  - Modo Sol keeps its light card, as before.
- **Shutter.**
  - 72 dp, with a 4 dp ring, a 4 dp gap and a 56 dp disc.
  - Held: `#666666` and `#555555`. Enabled: white and white.
  - Its countdown ring, its press scale and its semantics are unchanged.
- **Camera switch.** A 48 dp `#262626` disc with a 24 dp Lucide `refreshCw`, centred 64 dp from the right edge. The shutter stays centred.
- **`CaptureAlert`.**
  - Positioned 7 dp above the chips, with 16 dp margins, in the measured colours and type.
  - The corrections are ordered light, distance, focus, and joined as Portuguese lists are: commas, and "e" before the last. The causes keep their order.

### Processing

- **The lattice.**
  - The result's `ResultLattice` (SPEC 0202) behind the capture screen's bar while it classifies: PNG 13 draws the same grid as PNG 14, within the half dp the two measurements differ by.
  - The bar turns transparent over it.
  - Modo Sol draws no lattice, as §1.5 draws no decoration and PNG 38 shows.
- **`ProcessingView`.**
  - The triangle 12.5 dp higher.
  - The chip, the title, the sentence and the disclaimer at the measured sizes, the sentence and the disclaimer within 312 dp.
  - In Modo Sol:
    - the chip is 14 sp in `onSurface` and its slot grows by the 2 dp rule above and below;
    - the disclaimer stays at 12/16.
- **`TextureTriangle`.** Its labels are 12 sp in every theme, as PNG 26 and 38 draw them.
  - The phase stays as a polite live region that reads aloud and draws nothing. The progress bar leaves.

### Kept on purpose

- **The flash button** (PNG 10's Lucide `zap`). The capture protocol forbids the flash (ADR 0017), and `PluginCaptureCamera` forces it off. A switch that turned it on would spoil the colour the classifier reads.
- **The gallery button** (PNG 10's Lucide `image`). Capture is camera-only by design, so no photograph is classified without the guided frame. The slot stays empty and the shutter stays centred.
- **The bookmark and share actions** on the processing bar (PNG 13). Nothing is saved yet, so neither has anything to act on. They appear on the result (PNG 32).
- **Values.**
  - The mock's "180 lx", "48 cm" and its sentences are example data.
  - The chips keep what the camera reads: "Baixa", "Boa", "Enquadrada".
  - The pill keeps SPEC 0166's sentences.
  - The class chip keeps the class the model returned.
- **The haptic chip** ("heavyImpact ×2") and "SIMULAÇÃO" are the mock's annotations, not screen content.

## Alternatives Considered

- **Fix the pill at PNG 10's 203 dp from the top.** Rejected: the app's outline is an A4 sheet fitted between the bar and the panel, not the mock's 255 dp square. A fixed pill would land inside the outline. The pill keeps the mock's relation to the frame, 12 dp above it, instead of its absolute place.
- **Draw the flash and gallery buttons disabled.** Rejected: a control that can never act is noise, and the semantics would announce it.

## Scope

- Includes:
  - `GuidedCameraScreen`'s top bar, pill, panel, shutter and switch;
  - `QualityChip` and `CaptureAlert`;
  - `ProcessingView`, `TextureTriangle`'s label size, and the capture screen's bar while it classifies;
  - their tests.
- Does NOT include:
  - `CaptureGuideOverlay`'s brackets, target and level, which SPEC 0169 sets;
  - the guidance sentences.

## Acceptance Criteria

- `camera_top_bar_matches_the_mock`:
  - the bar is transparent;
  - it leads with `LucideIcons.x` labelled "Fechar";
  - its title is `titleLarge`;
  - its action is `LucideIcons.info`.
- `guidance_pill_sits_above_the_outline`: the pill is 28 dp tall, its text is 14 sp white, and its bottom is 12 dp above the outline's top.
- `quality_chips_match_the_mock`:
  - a chip is 51 dp tall, filled `#1C1C1C`;
  - its label is 13 sp weight 600 and its value 12 sp in `#BDBDBD`;
  - a failed chip shows `LucideIcons.circleAlert`.
- `held_shutter_matches_the_mock`: a held shutter draws a `#555555` 56 dp disc inside a `#666666` ring 72 dp across.
- `switch_sits_64_dp_from_the_right`: the camera switch is a 48 dp disc centred 64 dp from the right edge, with `LucideIcons.refreshCw`.
- `refusal_card_floats_above_the_chips`: a held shutter tapped after a poor reading shows the card 7 dp above the chips, 16 dp in from each side, and the refused chip stays 51 dp.
- `the_pill_is_neutral_in_every_tone`: the pill keeps its black fill and white text whatever the tilt.
- `capture_alert_matches_the_mock`:
  - the refusal card's background is `#FFF4E2`;
  - its title is 14 sp weight 600;
  - its sentence lists the corrections light, distance, focus, joined with "e" before the last.
- `processing_matches_the_mock`:
  - the title is 20 sp;
  - the class chip's text is 12 sp weight 600;
  - no `LinearProgressIndicator` is drawn;
  - the phase is a live region with no visible text.
- `processing_draws_the_result_lattice`: the capture screen draws `ResultLattice` while it classifies.
- Existing tests pass, updated where they pinned the replaced measures.

## Reproducibility

Flutter 3.44.1, Dart 3.12.1. Run `flutter test`, `flutter analyze` and `mf check`.

## Risks and Assumptions

- The camera's colours are fixed, not theme roles, because the camera draws its own dark chrome in every theme, as it already drew `Colors.black` and `Colors.black54`.
- The pill's place differs from PNG 10's on the mock's own phone by the difference between the A4 outline and the mock's square. That difference is recorded above rather than hidden.
