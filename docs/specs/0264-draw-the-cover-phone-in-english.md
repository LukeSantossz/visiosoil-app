# SPEC: docs(brand): draw the cover's phone in English

## Problem

The README cover (SPEC 0258, `docs/design/brand/readme-cover.svg` and its PNG) mixes two languages. Its left side is English: the wordmark, the two lines and the three pills. Its phone draws the guided camera in the app's pt-BR: the chips "Luz", "Distância" and "Foco" and the guidance line "Pronto. Segure firme.". On 2026-11-07 the Developer pointed out that the cover should be English only. The README, like every document here, is English, and the cover introduces it.

Nothing records which words a cover path draws, because the text is outlined. A test cannot read the language off the glyphs, so a later edit can bring a Portuguese line back without any check noticing.

## Design Decision

- The phone draws the same screen in English:

  | Today (pt-BR) | After |
  |---|---|
  | Luz | Light |
  | Distância | Distance |
  | Foco | Focus |
  | Pronto. Segure firme. | Ready. Hold steady. |

  They are the English sense of the app's strings, not new copy. The app itself keeps its pt-BR strings; nothing under `lib/` changes.
- The new words are outlined as SPEC 0258 outlined the old ones: `assets/fonts/InterVariable.ttf`, shaped by HarfBuzz (`uharfbuzz` 0.57.0) with `cv11` and `ss01`, `opsz` set to the size between 14 and 32, and written as paths by `fontTools` 4.68.0. The chips stay at 12 px, weight 500, and the guidance line at 13 px, weight 500, as measured from the current paths.
- The chips keep their look, sized to the English words. Each pill is its text's advance plus 26, with the dot 10 and the text 18 after its left edge; that is 3 less than today on each pill, so the wider English words leave about 6 px between the row and the screen's edges. The pills stay 6 apart, and the row stays centred on the phone at x = 1020. The guidance line stays centred at x = 1020 on its current baseline.
- Every outlined text path in the cover carries a `data-text` attribute naming the words it draws. The left side's paths keep their glyphs and gain only the attribute.
- `readme-cover.png` is exported again from the SVG, at 2560 × 800, by headless Chromium at device scale factor 2 on a transparent background.
- `docs/design/brand/README.md` names the English words the phone draws.
- A new test in `test/standards/brand_assets_test.dart`, `cover_text_is_english`: every filled `<path>` of the cover carries `data-text`, the texts in document order are exactly the cover's ten lines, and none holds a character outside ASCII.

## Alternatives Considered

- **Keep the app's pt-BR on the phone.** It is what the agronomist sees, but it puts two languages in one English image, which the Developer rejected.
- **Pin the language by the paths' bytes.** A hash of each text path would catch any change, including a harmless one, and would still not say what the path reads. `data-text` names the words, so the test reads as the cover does.
- **Live `<text>` for the phone.** Rejected for the reason SPEC 0258 gives: an SVG shown through `<img>` cannot load a font.

## Scope

- Includes:
  - the four phone lines of `readme-cover.svg` and the chips' pills;
  - the `data-text` attribute on every text path of the cover;
  - `readme-cover.png`, exported again;
  - the phone's line in `docs/design/brand/README.md`;
  - the new test.
- Does NOT include:
  - any app string, screen, code or asset;
  - the logo files, the wordmark, the left side's text or the README's alt text, which are already English;
  - spec 0258, which records what was decided then;
  - the repository's GitHub avatar, social preview or settings.

## Acceptance Criteria

- `cover_text_is_english` fails before the change, because no cover path carries `data-text`, and passes after.
- The four tests of SPEC 0258 still pass, the PNG at 2560 × 800.
- No produced text holds U+2013 or U+2014.
- The rendered cover shows the English phone with the chips' text inside their pills. The Author checks this in the rendered PNG and the pull request records it.
- `flutter test` shows no failures beyond those this machine has on `main`, and `mf check` passes.

## Reproducibility

Flutter 3.44.1 / Dart 3.12.1 in CI. Run `flutter test test/standards/brand_assets_test.dart`, then `flutter test` and `mf check`. The outlining step needs `uharfbuzz` 0.57.0 and `fontTools` 4.68.0 in a scratch Python 3.12 environment; the script stays outside the repository, as SPEC 0258 decided.

## Risks and Assumptions

- **`data-text` can disagree with the glyphs.** The test reads the attribute, not the outline, so an edit that changes one and not the other passes. Accepted: the attribute is written by the same step that outlines the words, and a reader of the SVG sees both side by side.
- **The cover no longer matches the app word for word.** A reader who opens the app sees "Luz" where the cover says "Light". Accepted: the cover is a drawing of the screen, in the README's language.
