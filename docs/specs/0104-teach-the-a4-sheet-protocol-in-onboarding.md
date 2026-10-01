# SPEC: fix(onboarding): teach the A4-sheet capture protocol the measurer reads

## Problem

The onboarding tells the user to place a coin beside the sample and to centre the soil in a viewfinder the system camera does not have. A user who follows it takes photographs the A4-sheet reader refuses (#282, ADR 0017, SPEC 0091).

## Scope

- Includes:
  - `lib/core/features/onboarding/onboarding_screen.dart`: the three steps are rewritten from the capture protocol ADR 0017 records, one step per point. Each step's icon changes to fit its new title.
    1. **"Folha A4":** "Use uma folha A4 branca, sem nada escrito, sobre uma superfície mais escura que o papel. Não coloque mais nada sobre ela."
    2. **"Amostra":** "Espalhe o solo em um círculo de 8 a 10 cm no meio da folha."
    3. **"Foto":** "Fotografe de cima, com a folha inteira no quadro e uma margem em volta, em luz difusa e sem flash."
  - `test/features/onboarding/onboarding_screen_test.dart`: pins the new copy.
- Does NOT include:
  - The home screen's promise and the capture screen's retry, which #281 covers.
  - Showing the reader's refusal causes on the capture screen.
  - An illustration of the protocol. The steps keep their icons.
  - The step count, the navigation and the completion behaviour.

## Acceptance Criteria

- `no_step_mentions_a_coin_or_a_viewfinder`: no step's text contains "moeda" or "visor".
- `the_steps_teach_the_sheet_protocol_in_order`: paging through the onboarding shows the three titles and texts above, in that order.
