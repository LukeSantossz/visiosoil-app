# SPEC: fix(settings): match the settings rows and the Tema control to PNG 35 and 36

## Problem

The Developer asked on 2026-10-26 for "100% de fidelidade ao mock" ("100% fidelity to the mock"). Configurações was rendered in both themes and every line of ink compared with PNG 35 (light) and PNG 36 (Modo Sol). PNG 35 is PNG 23 with the Vibração row the app now has.

Light theme gaps, against PNG 35:

- **Tema row.** It is 64 dp tall; PNG 35 draws it at 56 dp. Every row below it sits 8 dp low.
- **Tema control.** Both segments take the widest label's width, at 14 sp. PNG 35 gives each segment its own label's width and sets the labels at 12.5 sp:
  - "Claro" is 58 dp wide.
  - "Escuro" is 68 dp wide.

Modo Sol gaps, against PNG 36:

- **Rows.**
  - A row is at least 64 dp tall. PNG 36 draws Unidades and Idioma at 54 dp under a 2 dp rule, and Conta, which has no rule above it, at 56 dp.
  - The title is 15 sp. PNG 36 sets it at 17 sp.
  - The icon is `primaryText`, a dark green. PNG 36 draws it in ink.
- **Tema row.** It is 72 dp tall, holding a 32 dp pill. PNG 36 draws a 60 dp row holding a 44 dp pill, with labels at 14.5 sp weight 600.
- **Section labels.** Each one sits on an 18.6 dp line. PNG 36 spaces them as light mode does, on a 16 dp line, so every card in the app sits 3 dp low.

## Design Decision

Each value below is read from the 2× PNG 35 and 36, 2 px to the dp.

- **A row's height.**
  - A settings row is at least 56 dp tall in every theme, counting the rule `SettingsGroup` draws above it.
  - This is how PNG 35 and 36 draw it:
    - **Light:** a first row is 56 dp and a later one 55 dp under its 1 dp rule.
    - **Modo Sol:** a later row is 54 dp under its 2 dp rule.
    - **Tall rows:** a row whose content is taller keeps its full height, with the rule added above it.
  - `SettingsGroup` tells each row the width of the rule above it.
- **A row's padding.**
  - The 8 dp vertical padding applies to the text only.
  - The trailing control is centred in the row's full height, so a control's own target is not padded a second time.
- **Modo Sol rows.**
  - The title is 17/20.
  - The icon is ink, `onSurface`, as Modo Sol draws every line.
- **The compact `SegmentedControl`.**
  - **Light:** the pill is 32 dp and the labels 12.5 sp at weight 500.
  - **Modo Sol:** the pill is 44 dp and the labels 14.5 sp at weight 600.
  - Each segment is its label's width plus 13 dp either side.
  - The control is the pill plus 8 dp above and below:
    - 48 dp in light, which is the light target;
    - 60 dp in Modo Sol, above its 56 dp target.
- **Section labels** sit on a 16 dp line in every theme. Their size and weight do not change.

## Alternatives Considered

- **Keep Modo Sol's 64 dp minimum.** Rejected. PNG 36 draws 54 dp rows, and each one is a single target, wider than 56 dp across the full row. The shortfall against the 56 dp target is the 2 dp rule.
- **Trim the compact control's target to fit a padded 56 dp row.** Rejected: that drops the target below 48 dp.

## Scope

- Includes:
  - `SettingsRowFrame` and `SettingsGroup`;
  - the compact `SegmentedControl`;
  - Configurações' section label;
  - their tests.
- Does NOT include:
  - the switches' on and off states, which are the user's settings;
  - the "selectionClick" badge, which annotates the mock's haptic;
  - PNG 24's export sheet.

## Acceptance Criteria

- `light_settings_rows_match_png_35`:
  - the Tema row is 56 dp;
  - a later chevron row is 55 dp under its 1 dp rule;
  - the "Claro" segment is narrower than "Escuro";
  - a label is 12.5 sp.
- `sun_settings_rows_match_png_36`:
  - a later chevron row is 54 dp under its 2 dp rule;
  - its title is 17 sp and its icon `onSurface`;
  - the Tema row is 60 dp, with a 44 dp pill and 14.5 sp labels at weight 600.
- `section_label_sits_on_a_16_dp_line`: in Modo Sol the label's line is 16 dp.
- Every compact segment's target is at least 48 dp tall, 56 dp in Modo Sol.
- Existing tests pass.

## Reproducibility

Flutter 3.44.1, Dart 3.12.1. Run `flutter test`, `flutter analyze` and `mf check`.

## Risks and Assumptions

- Perfil shares `SettingsGroup`, so its later rows also become 55 dp in light and 54 dp in Modo Sol. PNG 21 and 22 draw Perfil's rows the same way, which the render check confirms.
- "Tamanho do texto" uses the same compact control, so its segments take the new sizes. No mock draws it.
