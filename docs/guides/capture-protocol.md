# Capture Protocol

How to take a soil photograph VisioSoil can classify. Follow every step. The app
reads the scale from the A4 sheet, and a photograph whose sheet or soil it
cannot read is refused by name rather than guessed at
([ADR 0017](adr/0017-scale-is-read-by-a-classical-operator-on-a-known-circle.md)).
It does not check every step: the soil's dryness and preparation, the light, the
focus and the circle's upper size are yours to get right, and a photograph that
misses one may still be read.

A pt-BR version is [`capture-protocol.pt-BR.md`](capture-protocol.pt-BR.md).
This file is its source, and the two state the same steps and limits.

**No real photograph has been classified yet.** The code enforces two of the
limits below, 2299 px and 63 mm. They say what the app will read, not how
accurate the reading is on field photographs
([`docs/ml/sheet-reader-real-photographs.md`](ml/sheet-reader-real-photographs.md)).

## 1. What you need

- **A bare white A4 sheet** (210 × 297 mm): flat, unfolded, with nothing written
  or printed on it.
- **A surface clearly darker than the paper**: dark wood, a dark board or cloth.
  A pale table is the most common reason the sheet is not found.
- **Air-dried, sieved soil**, crumbled, with no clods, roots or stones. It is the
  only material the model was trained on. Moist field soil can be photographed,
  but its reading is outside the model's evidence
  ([ADR 0014](adr/0014-petri-dish-capture-protocol-and-the-unresolved-scale-reference.md)).
- **A phone camera set to its highest resolution.**

## 2. Prepare the sample

1. Lay the sheet flat on the dark surface. Put nothing else on it: no second
   sheet, label, coin or container.
2. Spread the soil directly on the paper in **a round, even patch 8 to 10 cm
   across**, in the middle of the sheet. The patch must be **at least 63 mm**
   across, or the app refuses it as too small.
3. Keep the layer even and without gaps, so no paper shows inside the circle.

## 3. Frame and shoot

1. Hold the phone **directly above** the sheet, parallel to it.
2. Keep **the whole sheet in the frame**, all four corners visible, with a
   margin of the surface on every side.
3. Turn the phone so **the sheet's long side runs along the frame's long side**,
   and come as close as the margin allows. The sheet's 297 mm side must span
   **at least 2299 px** in the photograph. On a 12 MP camera (4000 × 3000), that
   is at least 57.5 % of the frame's long side. Do not use digital zoom: move closer
   instead.
4. Use **diffuse light**: shade, an overcast sky, or even room light. **No flash**,
   no patch of direct sun, and no shadow across the sheet, including the phone's
   own.
5. Hold still and let the camera focus on the soil.

## 4. Checklist before the shot

- [ ] Bare white A4 sheet, flat, on a darker surface
- [ ] Nothing on the sheet but the soil
- [ ] Dry, sieved soil in an even circle of 8 to 10 cm, centred
- [ ] Phone above the sheet, parallel to it, at its highest resolution
- [ ] Whole sheet in view, four corners, a margin all round, long sides aligned
- [ ] Diffuse light, no flash, no shadow on the sheet

## 5. When the app refuses the photograph

The capture preview names the cause in a chip. Each one below asks for another
photograph; change what the last column says before taking it.

| The app shows | Cause | What to change |
|---|---|---|
| Folha A4 não encontrada · tire outra foto | `sheetNotFound` | Use a darker surface, and keep the whole sheet in the frame. The sheet must be neither tiny in the frame nor fill almost all of it. |
| Folha cortada no quadro · tire outra foto | `sheetCropped` | Step back until all four corners show, with a margin. |
| Aproxime o celular da folha · tire outra foto | `photographTooCoarse` | The sheet spans fewer than 2299 px. Set the camera to its highest resolution, align the long sides and come closer. |
| Pouco solo na folha · espalhe um círculo de 8 a 10 cm e tire outra foto | `soilRegionTooSmall` | Spread more soil, into a circle of 8 to 10 cm. |
| Amostra fora da área lida · tire outra foto | `soilRegionOutsideFrame` | Centre the soil circle on the sheet, away from its edges. |
| Foto ilegível · tire outra foto | `imageMissing`, `imageUndecodable` | Take the photograph again. |
| Não foi possível analisar esta foto · tire outra foto | `outputInvalid` | Take the photograph again, following every step above. |

A chip that says *tocar para tentar de novo* is not about the photograph: tap it
to run the same one again. *Análise indisponível nesta versão* means the
installed build carries no usable classifier, and no photograph fixes it.

## Where the limits come from

- The three steps the app teaches: `lib/core/constants/capture_protocol.dart`,
  and the protocol decided on 2026-09-29 in ADR 0017's amendment.
- **2299 px**: the sheet's 297 mm divided by the contract's canonical
  0.1292 mm/px (`assets/models/spec.json`). A coarser photograph would have to
  be upsampled, inventing grain that was never photographed
  (`lib/core/services/descriptors/patch_grid.dart`).
- **63 mm**: the nine patches ADR 0018 requires, 20.7 mm each and half a
  patch apart, need a disc of 58.5 mm, and the reader measures that disc 2 mm inside the soil's
  edge (`soilMarginMm` in `lib/core/services/descriptors/a4_sheet.dart`). The
  8 to 10 cm circle mirrors the 90 mm dish the model was trained on.
- **The surface and the framing**: the sheet reader's contrast and frame-fraction
  limits in `a4_sheet.dart`, and the faults the 2026-10-05 session showed.

`test/standards/capture_protocol_doc_test.dart` recomputes both figures from the
contract and fails if this document no longer states them (SPEC 0164).
