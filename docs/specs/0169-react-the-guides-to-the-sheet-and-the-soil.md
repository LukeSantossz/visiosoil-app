# SPEC: feat(capture): react each guide to the sheet and the soil, and warn when the sheet leaves the screen

## Problem

On the guided camera (SPEC 0165, SPEC 0166, SPEC 0167), the sheet outline's four corner brackets and the soil target are drawn in fixed white whatever the live reader sees, so the agronomist cannot tell at a glance which corner is out of place, which way to move the phone, or by which side the sheet has left the screen, because only the banner's one sentence says what is wrong.

## Design Decision

**Each guide shows its own state.** The four corner brackets and the soil target each take one of four states, drawn in the colour named for it. The banner stays: the guides show *where* the problem is, and the banner says *what* to do.

| State | Colour (`AppPalette`) | When it is used |
|---|---|---|
| `idle` | white, as today | no live reading is shown: before the first one, after the reader failed, in `tiltUnavailable` with no reading |
| `placed` | `primaryContainer` | the guide's own condition holds |
| `near` | `warningContainer` | the guide's own condition is close to holding |
| `off` | `errorContainer` | the guide's own condition is far from holding, or cannot be judged because the sheet is cropped |

The container roles are the ones the banner already uses (SPEC 0165), drawn as strokes on the dimmed preview. Each stroke gets a 1 px dark outline (`Colors.black54`) so it stays visible on a pale surface. A guide that is not `placed` also draws a translucent halo of its own colour at the guide's vertex, so its state is never told by colour alone. The banner sentence and the arrows below carry the same information in other forms.

**The reading carries the sheet's corners.** `LiveSheetFound` gains the four `SheetCorners` points `findSheet` already computes, in read-frame pixels. They are sendable as they are: plain doubles in a record list. `readSheet` stops discarding them. The still's path is untouched, since `InferenceService` never reads a `LiveReading`.

**Corners are mapped from the read frame to the overlay.** The preview is drawn at `CaptureCamera.previewSize` and fitted to the screen with `BoxFit.cover` (SPEC 0165). The read frame is the preview stream turned to portrait and reduced (SPEC 0166). So a corner at (x, y) in a read frame of size (w, h) is placed:

1. normalised: (x / w, y / h);
2. on the preview: times `previewSize`;
3. on the screen: scaled by `s = max(screenW / previewW, screenH / previewH)` and offset by half the overflow on each axis, which is what `BoxFit.cover` does;
4. on the overlay: minus the `SafeArea` padding, because `CaptureGuideOverlay` is laid out inside it.

This is correct only if the stream and the preview share a field of view. **When the read frame's aspect ratio differs from `previewSize`'s by more than 2 %**, the corners are not mapped, every bracket stays `idle`, and the banner works as in SPEC 0166. Showing a corner in the wrong place would be worse than showing none.

**Each detected corner is assigned to one bracket** by its position on the overlay: top-left is the corner with the least x + y, bottom-right the one with the most, top-right the one with the most x − y, and bottom-left the one with the least x − y. The ordering of `SheetCorners` is not used for this, because it follows the sheet's edges, not the screen.

**A bracket's state is its corner's distance to the bracket's vertex**, in overlay logical pixels, measured against the outline's width `W`:

| Distance | State |
|---|---|
| ≤ 0.06 W | `placed` |
| ≤ 0.15 W | `near` |
| more | `off` |

The two fractions are first values, to be tuned in the field session. They are constants in one place, named for what they are.

**Arrows.** A bracket that is `near` or `off` draws an arrow from its vertex. The arrow points along the dominant axis of the sheet's **mean** corner displacement from the brackets, the direction to move the phone, as in the approved mockup. Moving the phone toward the side the sheet has drifted to brings the sheet back. Arrows are drawn only when that mean displacement exceeds 0.06 W, so the misalignment is mostly a shift. When the sheet is mostly too small, too large or turned, a shift does not fix it, so no arrow is drawn, and the banner (below) names the fix.

**The soil target's state follows the soil rows** that SPEC 0166 already defines, so the target never disagrees with the banner or the trigger:

| Reading | State |
|---|---|
| no reading, sheet not found, or sheet cropped | `idle`, drawn dashed |
| `soilNotMeasured` | `idle`, drawn dashed |
| `smallSoil` (fewer than `min_patches` patches) | `near` |
| the disc holds `min_patches` patches | `placed` |

No new judgement of the soil's position is introduced. The reader measures the disc wherever it lies on the sheet, and the still accepts it there. The target only shows what the reader already decides.

**Alignment joins the banner's rows, so "all green" means the same everywhere.** A new row, `sheetMisaligned`, is checked after row 4 (`tooCoarse`) and before row 5 (`soilNotMeasured`) of SPEC 0166's table, and holds when any bracket is `near` or `off`. It is amber, and its sentence names the dominant fix:

| Dominant misalignment | Sentence |
|---|---|
| shift (mean displacement over 0.06 W) | "Leve o celular para {a esquerda / a direita / cima / baixo}." |
| the sheet is smaller than the outline (its width under 0.85 of the outline's) | "Aproxime o celular da folha." |
| the sheet is larger than the outline (its width over 1.15 of the outline's) | "Afaste o celular da folha." |
| otherwise (turned) | "Gire o celular até a folha ficar reta no contorno." |

`guidanceFor` gains an `alignment` argument, computed by the screen from the mapped corners, the same way `tooCoarse` is passed today. With no mapping (aspect mismatch, or no corners), `alignment` is null and the row never holds, which is SPEC 0166's behaviour. Because SPEC 0167's trigger reads the banner's row, a misaligned sheet now closes the automatic capture's window. **The trigger fires only when every guide is green.** The manual shutter stays always enabled.

Amended in review: when the guides cannot be placed, because of an aspect mismatch, they stay white and SPEC 0167's trigger works as it does today. Blocking it there would switch automatic capture off for good on that device, over a check that only guards the guides' positions.

**The sheet leaving the screen is warned by its side.** The frame is portrait after SPEC 0166's rotation, so its sides point the same ways as the screen's. But the frame is wider than what the screen shows. `BoxFit.cover` crops it: a 720 × 1280 preview on a 390 × 844 screen scales by 0.659, so about 42 logical pixels of it on each side are off the screen. The sheet therefore leaves the screen before it leaves the frame, and "left the screen" has two sources:

1. **A whole sheet with a corner past the screen.** A reading is `LiveSheetFound`, but a mapped corner lies outside the screen's rectangle. Its sides are the sides that corner falls past. The screen treats it as cropped: the banner shows the cropped row and the warning shows. This needs no new detector, because it is geometry on the corners the reader returned. It is the usual case, and its side is exact.
2. **A sheet the reader refused as cropped.** `findSheet`'s result gains `croppedSides`, a set of frame sides (`left`, `top`, `right`, `bottom`), filled only when the refusal is `cropped`:
   - when a refined corner falls outside the frame: the side or sides it falls past;
   - when the sheet's region touches the frame's border and no quadrilateral is found: the borders its mask touches, ordered by the length of contact;
   - when the edge-step check refuses it: empty, because no side is known.

**No decision of `findSheet` changes.** It returns the same corners and the same refusals for every frame, and the sides are recorded beside them. The still's reader (`a4SheetMeasurer`) ignores the field.

`LiveSheetCropped` carries the sides through, and the cropped banner (SPEC 0166 row 3) gains its sentences:

| Sides | Banner | Warning card |
|---|---|---|
| one side, or two adjacent sides | "A folha saiu pela {esquerda / direita / parte de cima / parte de baixo}." (two adjacent sides name the first: the side the corner falls furthest past, or the one with the longest border contact) | "A folha saiu da tela" / "Leve o celular para {o mesmo lado}" |
| two opposite sides, or three or four | "A folha passa da tela. Afaste o celular." | "A folha saiu da tela" / "Afaste o celular da folha" |
| empty | "A folha está cortada. Afaste o celular." (today's) | "A folha saiu da tela" / "Afaste o celular da folha" |

While the reading is `sheetCropped`:

- each side in `croppedSides` gets a red gradient along that edge of the preview, `errorContainer` fading to transparent over 34 logical pixels;
- all four brackets are `off`, with no arrows;
- a **warning card** is drawn in the middle of the outline: `errorContainer` with `onErrorContainer` ink, `Icons.warning_amber_rounded`, a title and a line, as in the approved mockup.

The card replaces the soil target's label while it shows, and it disappears with the next reading that is not cropped. It goes through the debounce like every row (SPEC 0166), so one cropped frame does not flash it.

**Motion.** State changes switch colours without animation, so reduced motion needs no special case. The edge glow is static.

**Haptics.** Unchanged. The selection tick on entering green (SPEC 0166) stays the only one. A haptic on error would compete with it.

**The approved mockup** is the reference for the look. It was reviewed and approved by the Developer on 2026-10-18 and is not committed (a scratchpad HTML file). Its five states are a shifted sheet, a nearly placed sheet with a small soil patch, everything in place, a sheet leaving by the right, and a phone too close.

## Alternatives Considered

- **Colour only, no arrows.** Rejected by the Developer, who asked for both colour and direction.
- **Arrows pointing where the sheet must go**, instead of where the phone must go. Rejected. The user holds the phone, not the sheet, and the Developer asked for the direction to move the phone.
- **A per-corner colour that does not gate the automatic capture**, which keeps SPEC 0167's trigger as it is. Rejected: it would let the trigger fire while a guide shows amber. "All green" must mean the same on the guides, on the banner and in the trigger, which is what the Developer approved.
- **Judging the soil's position against the target**, for example amber when the disc is off-centre. Rejected: nothing downstream needs the disc centred. The reader finds it anywhere on the sheet, and a new rule would refuse photographs the still accepts.
- **Finding the cropped side outside `findSheet`**, by scanning the live frame's borders for paper. Rejected: it would be a second detector with its own threshold, which SPEC 0166's first decision forbids, and it could disagree with the reader that refused the sheet.

## Scope

- Includes:
  - `lib/core/services/descriptors/a4_sheet.dart`: `croppedSides` on `findSheet`'s result. No other change.
  - `lib/core/features/capture/guided_camera/live_reading.dart`: the corners on `LiveSheetFound`, and the sides on `LiveSheetCropped`.
  - A pure module in `lib/core/features/capture/guided_camera/` holding:
    - the mapping from read-frame to overlay coordinates;
    - the corner-to-bracket assignment;
    - the bracket and target states;
    - the arrows;
    - the alignment's dominant fix.
  - `capture_guidance.dart`: the `sheetMisaligned` row, its sentences, the cropped sentences, and the `alignment` argument.
  - `capture_guide_overlay.dart`: the coloured brackets and halos, the arrows, the soil target's states, the edge glow and the warning card.
  - `guided_camera_screen.dart`: computes the alignment from the shown reading, `_readSize`, `previewSize` and the layout, and passes the states to the overlay and the alignment to `guidanceFor`.
  - Tests for each criterion, and the guided camera's widget tests updated where the banner's rows change.
  - The phase status in `docs/design/ux-2026/06-capture-experience.md`, if it lists the guides.
- Does NOT include:
  - Any change to the still's reader decisions, the patch grid, the contract or `InferenceService`.
  - Any change to SPEC 0167's trigger rule itself: it already reads the banner's row.
  - The 0.06 / 0.15 / 0.85 / 1.15 thresholds' calibration, which is the field session's.
  - Haptics, sound, or animation of the guides.
  - The deferred SPEC 0167 minors: the ring under reduced motion, and the monotonic clock.
  - iOS-specific mapping work beyond the same formula. The aspect check is the safeguard.

## Acceptance Criteria

- `cropped_sides_name_the_borders_touched`: on synthetic frames from `ml/scripts/generate_sheet_fixtures.py`'s style, or built in the test, a sheet running off the right edge gives `croppedSides == {right}`, and one running off the top and the bottom gives `{top, bottom}`.
- `find_sheet_decides_as_before`: every existing `a4_sheet_test.dart` and `a4_sheet_photos_test.dart` case passes unchanged. A snapshot of every fixture's corners (to 1e-9 px) and refusal is taken on `main` before `croppedSides` is added and committed with the test, and after the change each fixture still equals its snapshot.
- `a_corner_past_the_screen_counts_as_leaving_it`: a `LiveSheetFound` whose mapped top-right corner lies 10 logical pixels past the screen's right edge reads as cropped by `right`: the right glow, the warning card and the banner "A folha saiu pela direita.".
- `corners_map_to_the_overlay`: for a read frame of 576 × 1024, a preview of 720 × 1280, a 390 × 844 screen and a safe-area top of 47, a frame corner lands where the cover fit puts it, within 0.5 logical pixel; with a read frame of 768 × 1024 (aspect off by more than 2 %), no corner is mapped.
- `corners_are_assigned_by_position`: four corners given in any of the four rotations of `SheetCorners` order are assigned to the same brackets.
- `bracket_states_follow_the_distance`: a corner at 0.05 W, 0.10 W and 0.20 W from its vertex is `placed`, `near` and `off`.
- `arrows_point_the_way_to_move_the_phone`: a sheet shifted right by 0.1 W draws right-pointing arrows on its non-`placed` brackets; a sheet scaled to 0.7 of the outline draws none.
- `misalignment_names_its_fix`: shifted right, smaller, larger and turned sheets read "Leve o celular para a direita.", "Aproxime o celular da folha.", "Afaste o celular da folha." and "Gire o celular até a folha ficar reta no contorno.".
- `the_misaligned_row_sits_between_scale_and_soil`: with a misaligned sheet and too little soil, the banner reads the misalignment; with a misaligned sheet that is too coarse, it reads "Aproxime o celular da folha." from row 4.
- `the_target_follows_the_soil_rows`: no soil gives a dashed `idle` target, too little soil `near`, and enough soil `placed`.
- `no_mapping_keeps_spec_0166`: with an aspect mismatch, a found sheet leaves every bracket `idle`, and the banner reads exactly what SPEC 0166 gives for the same reading and tilt. Amended in implementation: a cropped reading still names its frame sides, because a side needs no position on the screen. Only a reading with no sides reads SPEC 0166's sentence.
- `the_trigger_needs_every_guide_green`: with every SPEC 0167 condition met but one bracket `near`, the window does not open; once all four are `placed`, it opens.
- `a_cropped_sheet_warns_by_its_side`: a `LiveSheetCropped({right})` reading, held for two readings, shows the right-edge glow, the warning card "A folha saiu da tela" / "Leve o celular para a direita", the banner "A folha saiu pela direita." and four `off` brackets. `{left, right}` shows both glows and "Afaste o celular da folha". An empty set shows today's banner.
- `the_warning_clears_when_the_sheet_returns`: after a cropped reading, two found readings remove the card and the glow.
- On a device (Developer), recorded in the PR with the phone's model and OS: over a real A4 sheet, sliding the sheet off each side lights that side and names it, and a placed sheet turns all four brackets green within about a second.

## Reproducibility

```sh
flutter test test/services/a4_sheet_test.dart test/services/a4_sheet_photos_test.dart test/features/capture
flutter analyze && flutter test && mf check
flutter build apk --release
```

Flutter 3.44.1, Dart 3.12.1, `mf` v0.8.0.

## Risks and Assumptions

- **Assumption: the preview stream and the preview share a field of view.** CameraX binds both from the same session, but their aspect ratios can differ. The 2 % check turns a mismatch into SPEC 0166's behaviour instead of misplaced guides. The device check confirms it on the Developer's phone (2412DPC0AG, Android 16).
- **Risk: the thresholds are guesses.** If 0.06 W proves too tight, the trigger fires less often than it does today. The field session that already decides SPEC 0167's trigger decides these too, and they are constants in one place.
- **Risk: adding alignment to the rows makes automatic capture stricter.** A sheet that is whole and large enough, but off the outline, used to fire and now does not. This is the Developer's decision, so that "all green" means one thing everywhere.
- **Risk: a lit patch named as a side.** A region that touches the border can be a lit patch of surface joined to it, not the sheet cut by the frame (`a4_sheet.dart`'s own note, SPEC 0140). Then the mask's contact names the wrong side, and the warning points the wrong way. Two things bound this. First, a sheet usually leaves the screen first, and that case is named from its corners, exactly. Second, the next reading replaces the warning. The one real photograph refused as cropped (`a4_sheet_photos_test.dart`) has its sides recorded in the PR.
- **Risk: `croppedSides` touches the still's reader file.** Guarded by `find_sheet_decides_as_before`, which pins every fixture's corners and refusal.
- **What would invalidate this spec:** a change to the capture protocol's sheet, or SPEC 0167's trigger being switched off by its field session. The guides would stay useful without the trigger, but the gating decision would need revisiting.
