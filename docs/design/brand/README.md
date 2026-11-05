# Brand files

The README cover and the logo files (SPEC 0258). Each SVG is the source and each PNG is exported from it. The mark in every file is drawn at `VisioSoilMarkGeometry`'s numbers (SPEC 0255), and `test/standards/brand_assets_test.dart` pins it there.

| File | Size | Use |
|---|---|---|
| [`readme-cover.svg`](readme-cover.svg) | 1280 × 400 | The README cover. It carries its own background, so it reads the same in light and dark themes |
| [`readme-cover.png`](readme-cover.png) | 2560 × 800 | The cover where SVG does not render |
| [`logo-mark.svg`](logo-mark.svg), [`.png`](logo-mark.png) | 48 units, 512 × 512 | The mark alone in primary, on light backgrounds |
| [`app-tile.svg`](app-tile.svg), [`.png`](app-tile.png) | 48 units, 512 × 512 | The white mark at 80 % on the primary tile, as the launcher draws it. Works on any background |
| [`logo-lockup-light.svg`](logo-lockup-light.svg), [`.png`](logo-lockup-light.png) | 228 × 64, 912 × 256 | Tile and wordmark, for light backgrounds |
| [`logo-lockup-dark.svg`](logo-lockup-dark.svg), [`.png`](logo-lockup-dark.png) | 228 × 64, 912 × 256 | Tile and wordmark, for dark backgrounds |

## Colours

All are app tokens from `lib/core/theme/`.

| Role | HEX |
|---|---|
| Primary, the tile and the mark | `#4A7C59` |
| Primary container, the cover's right panel | `#CCE8D4` |
| On primary container, the wordmark on light | `#0D2818` |
| Surface, the cover's left side | `#FCFDF8` |
| On surface variant, the cover's two lines | `#43483E` |
| Outline variant, the pills' border | `#C3C8BB` |
| Dark background, the phone's screen | `#121411` |
| On dark, the wordmark on dark and the phone's text | `#E2E3DD` |
| Clay and medium soil, the soil disc | `#7A4E2D`, `#9C7B4F` |

## Type

Inter, from the app's own `assets/fonts/InterVariable.ttf`, with the features the app sets (`cv11`, `ss01`): the wordmark at weight 700, the cover's lines at 400, the pills and the chips at 500.

## How they were made

- The text is converted to outlines, because an SVG shown through `<img>` cannot load a font. HarfBuzz (`uharfbuzz` 0.57.0) shaped each line from `InterVariable.ttf` at its weight, with `opsz` set to the size between 14 and 32, and `fontTools` 4.68.0 wrote the glyphs as paths. Changing a line of text means outlining it again.
- The PNGs were rendered from the SVGs by headless Chrome on a transparent background, at device scale factor 2 for the cover, 4 for the lockups and 512/48 for the square files.
- The cover's phone is a drawing of the guided camera, not a screenshot: its chips (Luz, Distância, Foco), the A4 sheet with its corner brackets, a soil disc about 9 cm across on that sheet, and the guidance line "Pronto. Segure firme.". A change to the camera's chips or guidance should update it.
