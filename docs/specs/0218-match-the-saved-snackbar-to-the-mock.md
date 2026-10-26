# SPEC: fix(ui): match the "Salvo no histórico" snackbar to PNG 33

## Problem

The Developer asked on 2026-10-26 for "100% de fidelidade ao mock" ("100% fidelity to the mock"). Every PNG under `docs/design/spec/telas/` was checked against the specs that measure it. PNG 33 is the only one no spec measures. The result screen, its filled bookmark and the light haptic it shows are already built (SPEC 0197, SPEC 0202), so the gap is the snackbar.

The result screen was rendered with the saved snackbar at 390 × 844 dp with Inter, and compared with PNG 33:

- **No icon.**
  - The app's snackbar is text only.
  - PNG 33 leads with a check in a light green, then the text.
- **Margins.** Flutter's floating default is 15 dp at the sides and 10 dp above the footer. PNG 33 floats the snackbar:
  - 16 dp from each side;
  - 19 dp above the footer's top rule.
- **Text line.** The text's glyphs sit 1.5 dp lower than PNG 33's. Flutter gives a line's extra height mostly to the space above the glyphs, and the mock splits it evenly.

What already matches:

- the 48 dp height and the 8 dp corners;
- the `inverseSurface` fill;
- the text's size and colour.

## Design Decision

Measured on the 2× PNG 33, 2 px to the dp.

- **Margins.** Every theme's floating snackbar takes `insetPadding` `EdgeInsets.fromLTRB(16, 5, 16, 19)`.
  - The redesign's §1 defines one snackbar style, so the margins are set in the theme rather than in one call.
  - The 5 dp top is Flutter's default and is kept.
- **Text line.** The theme's snackbar text takes `TextLeadingDistribution.even`, which puts the glyphs within 0.5 dp of PNG 33's.
- **Icon.** "Salvo no histórico" leads with `LucideIcons.check`:
  - 20 dp;
  - in the palette's `inversePrimary`, which is the green PNG 33 draws (#B1D1B9);
  - 12 dp before the text.
  - On PNG 33 the check starts 32 dp from the screen's edge and the text starts at 64 dp.

## Alternatives Considered

- **Set the margins only on the saved snackbar.** Rejected. The redesign gives every snackbar one style, and PNG 33 is the only mock that draws one.
- **Add the check to every snackbar.** Rejected. The others report a failure or an undo, and a check would misstate them.

## Scope

- Includes:
  - the theme's snackbar margins and text leading;
  - the saved snackbar's icon;
  - their tests.
- Does NOT include the other snackbars' copy, nor Modo Sol's border on elevated surfaces.

## Acceptance Criteria

- `snackbar_margins_match_the_mock`: the light, dark, Modo Sol and high-contrast themes:
  - float the snackbar with `EdgeInsets.fromLTRB(16, 5, 16, 19)`;
  - set its text with even leading.
- `saved_snackbar_leads_with_a_check`: after the bookmark saves a draft, the "Salvo no histórico" snackbar shows:
  - a 20 dp `LucideIcons.check` in `inversePrimary`;
  - its text 12 dp after the icon.
- Existing tests pass.

## Reproducibility

Flutter 3.44.1, Dart 3.12.1. Run `flutter test`, `flutter analyze` and `mf check`.

## Risks and Assumptions

- The 19 dp gap is read from one mock. It is followed as drawn, as SPEC 0203 follows its own single readings.
- Every snackbar moves 9 dp higher and 1 dp inward, and its text about 1 dp higher. No test pins a snackbar's position.
