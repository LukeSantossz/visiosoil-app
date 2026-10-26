# SPEC: fix(history): match the offline card to PNG 18

## Problem

The Developer asked on 2026-10-26 for "100% de fidelidade ao mock" ("100% fidelity to the mock"). Rendering Histórico offline and comparing it with PNG 18 shows the "Sem conexão" card differs. The list above and below it lands within 1 dp.

| | App | PNG 18 |
|---|---|---|
| Card margins | 20 dp | 16 dp |
| Card height | 181 dp | 201.5 dp |
| Drawing | Material's 48 dp `wifi_off` in `primaryText` | A phone outline holding four soil grains and a home bar, beside a Wi-Fi of two arcs and a dot, struck through in `error` |
| Title | `titleMedium`, 16 sp weight 600 | 15/20 at weight 400 in `onSurface` |
| Body | The default 14 sp | 13/18.5 in `onSurfaceVariant` |

## Design Decision

Measured on the 2× PNG 18, zoomed to 8 px to the dp.

- **Card:**
  - 16 dp from each side and 8 dp above the list, on `surface` with radius 16;
  - padding 43 dp above, 20 dp on the sides and 23.5 dp below.
- **Drawing.** An `_OfflineArt` painter on a 64 × 50 dp canvas, centred. Strokes are `primaryText`, except the slash.
  - The phone is a 27.5 × 47.75 dp rounded rectangle, radius 4, stroke 1.25, with its top left at (2.6, 0.75).
  - Four grains sit at (12.4, 19.75) r 2, (19.5, 21.9) r 1.4, (15.5, 27.9) r 1.25 and (21, 28.9) r 0.75.
  - The home bar is a 7.8 dp line at y 43.9, from x 12.6, 0.75 dp in `textTertiary`.
  - The Wi-Fi has two arcs of radius 19.5 and 11.5 about (52, 27), each 1 dp, spanning ±38° and ±45° about the vertical, and a 1.4 dp dot at (52, 25).
  - The slash is a 1 dp line in `error`, from (40.75, 2.6) to (63, 29.1).
- **Text:**
  - "Sem conexão" at 15/20, weight 400, `onSurface`, 23.5 dp under the drawing;
  - the line 4.5 dp lower at 13/18.5 in `onSurfaceVariant`, centred.
- **Modo Sol** keeps its edge and draws the drawing in ink, as Modo Sol draws every line.

## Alternatives Considered

- **Keep Material's `wifi_off` icon.** Rejected: PNG 18 draws a phone beside the Wi-Fi to say the data stays on the device, which the icon alone does not say.

## Scope

- Includes `OfflineBanner` and its tests.
- Does NOT include the pending count, which is data.

## Acceptance Criteria

- `offline_card_matches_the_mock`:
  - the card is 16 dp from each side;
  - it draws `_OfflineArt` (keyed `offline-art`), 64 × 50 dp;
  - the title is 15 sp at weight 400 in `onSurface`;
  - the line is 13 sp in `onSurfaceVariant`.
- Existing tests pass.

## Reproducibility

Flutter 3.44.1, Dart 3.12.1. Run `flutter test`, `flutter analyze` and `mf check`.

## Risks and Assumptions

- The arcs' angles are read from their chords and heights, so an arc's end can differ by a fraction of a dp.
