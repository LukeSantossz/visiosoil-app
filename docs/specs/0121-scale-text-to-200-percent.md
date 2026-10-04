# SPEC: fix(a11y): keep every screen readable at 200 % text scale

## Problem

With the phone's font size at 200 %, seven layouts on `main` overflow on a 411 × 891 dp phone, so text is cut off or squeezed to one letter per line.

The audit asks that layouts survive a 200 % `textScaler` with no clipping and no overlap, and that an ellipsis is used only where the cut text is repeated elsewhere (`docs/design/ux-2026/12-accessibility.md` §3.3, roadmap criterion `scales_to_200_percent`). SPEC 0118 and SPEC 0120 took item 3's other slices and left this one.

A probe ran every widget test under `test/features/` at 200 % on a 411 × 891 dp view. It found these overflows:

| Site | What overflows |
| --- | --- |
| `core/widgets/visio_button.dart`, the icon and label row | the label runs past the button by up to 114 px, on capture, details and history's empty state |
| `home/widgets/hero_capture_card.dart`, the "ANÁLISE NO APARELHO" row | 144 px to the right |
| `home/widgets/last_analysis_section.dart`, the "Última análise" / "Ver tudo" row | 311 px to the right |
| `onboarding/onboarding_screen.dart`, the "Como capturar" / "Pular" row | 187 px to the right |
| `onboarding/onboarding_screen.dart`, a step's page | 264 px past the bottom |
| `history/widgets/history_filter_bar.dart`, the filter error row | the "Tentar novamente" button squeezes the message to one letter per line, which overflows the screen by 245 px |
| `settings/settings_screen.dart`, `_SettingsTile` | a trailing text or button squeezes the title the same way |

The squeezed cases share one cause. A `Row` gives its inflexible child its full natural width first. At 200 %, a trailing button or label is wider than the row, so the `Expanded` title beside it gets close to zero width.

## Design Decision

**A trailing item yields width instead of taking all of it.** Each case is fixed with the smallest change that removes the overflow:

| Site | Change |
| --- | --- |
| `VisioButton` | the label is `Flexible` with `textAlign: center`, so it wraps inside the button |
| hero card header | the label is `Flexible` and wraps |
| last-analysis header, onboarding header | the title is `Expanded`, and the text button keeps its own width |
| history filter error row | the "Tentar novamente" button is capped at half the row's width (`LayoutBuilder` and `ConstrainedBox`), so its label wraps instead of squeezing the message |
| `_SettingsTile` | the trailing widget is capped at half the row's width the same way, so the title keeps at least half of the row |
| onboarding step page | the column scrolls, inside a `LayoutBuilder` whose minimum height keeps it centred when it fits |

**Three cut texts are shown whole; two stay cut at one line.**

| Text | Decision | Why |
| --- | --- | --- |
| home row, texture class | no line limit | it is not repeated on the home screen |
| home row, place and date | no line limit | same |
| capture preview chips | no line limit | the address is not repeated on the capture screen |
| details header, compact date | stays `maxLines: 1` | the full date is repeated in the details info section, as the audit allows |
| history thumbnail, date | stays `maxLines: 1` | a third-of-the-width cell over a photograph cannot take a second line without covering the photo. The thumbnail's semantic label (SPEC 0118) reads the full date, and details shows it one tap away |

The history thumbnail is a stated exception to the audit's rule, not a silent one.

The approved draft gave the first three `maxLines: 2`. The PR's R3 review found that two lines still cut a long address, which the audit's rule does not allow for text shown once on a screen, so the limit was removed. The criteria now check the rendered text, not the `maxLines` value.

**The probe becomes a test per screen.** A test helper, `useLargeTextOnAPhone`, sets a 200 % text scale and a 411 × 891 dp view. Each screen's existing test file gains one test that pumps the screen the way the file already does. A layout overflow is a `FlutterError`, so the test fails on any overflow.

## Alternatives Considered

- **Make the trailing item `Flexible` beside the `Expanded` title.** Tried first and rejected: a row splits its free space between flex children by their flex, so the title would get only half the row even beside a small icon. At 100 % that wrapped titles that fit before, and pushed settings rows down. A cap applies only when the trailing item is wide.
- **Clamp the text scale, for example to 1.5.** Rejected: it overrides the user's own setting, which is the opposite of what the audit asks.
- **A run-wide `flutter_test_config.dart` that puts every widget test at 200 %.** Rejected: many tests tap widgets by position or check sizes at 100 %. A large-text run of all of them would test layout through tests written for other purposes. One focused test per screen is easier to read when it fails.
- **Golden tests at 100 %, 150 % and 200 %,** as the audit's test table suggests. Rejected for this slice: pixel goldens depend on fonts and platform, and CI renders on Linux while development here is on Windows, so the images would differ between the two. An overflow check catches the defect the audit names, without pixels.
- **Wrap every screen body in a scroll view.** Rejected: most overflows are horizontal, inside a row, and a vertical scroll does not fix them.

## Scope

- Includes:
  - The seven sites in the table above, and the three line limits removed.
  - `test/support/large_text.dart`: the helper.
  - One large-text test in each of the tests for home, onboarding, capture, details, history and settings, plus the two cut-text checks.
- Does NOT include:
  - Landscape layouts, and phones narrower than 411 dp.
  - Text scales above 200 %.
  - Splash and preview, where the probe found no overflow. They are covered only by the probe run recorded in the PR.
  - Golden tests.
  - Any copy change, or any change to the type scale.

## Acceptance Criteria

Each test runs at 200 % text scale on a 411 × 891 dp view. "Lays out" means it renders with no `FlutterError` overflow.

- `home_scales_to_200_percent`: the home screen with a last analysis lays out.
- `onboarding_scales_to_200_percent`: each of the three onboarding steps lays out.
- `capture_scales_to_200_percent`: capture's actions lay out before a photograph, and again with one.
- `details_scales_to_200_percent`: details with a classified record lays out.
- `history_scales_to_200_percent`: the history grid lays out, as do its empty state and its filter error row.
- `settings_scales_to_200_percent`: settings, signed in, lays out.
- `home_row_is_not_cut`: the home row shows a long address and its date whole, with no ellipsis.
- `capture_chip_is_not_cut`: a capture preview chip shows a long address whole, with no ellipsis.
- The existing tests pass unchanged.

## Reproducibility

`flutter test test/features/`

Flutter 3.44.1, Dart 3.12.1.

## Risks and Assumptions

- 411 × 891 dp is a common Android phone (1080 × 2340 px at 2.625). A narrower phone may still overflow at 200 %, which the Scope leaves out.
- A test environment font is not a device font. The overflow test proves the layout bends at that scale, not that every glyph fits on every device. A look on a device at the largest font size is left to the manual pass the audit asks for.
- Letting a button label wrap makes the button taller at large scales. That is the intended trade: two lines of a readable label instead of a clipped one.
- An uncapped capture chip can cover more of the photo when the address is long. The chips sit at the preview's edge, the photo has already been taken, and the address must be readable before it is saved.
