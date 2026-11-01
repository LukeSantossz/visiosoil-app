# SPEC: fix(settings): write the section headers in sentence case

## Problem

Ajustes is the only screen whose section headers are written in capitals.

- **What it draws.** `_SectionHeader` in `settings_screen.dart` shows six headers: "CONTA", "PREFERÊNCIAS", "CÂMERA E ANÁLISE", "DADOS E SINCRONIZAÇÃO", "ACESSIBILIDADE" and "SOBRE E AJUDA". They are 12 sp, weight 600, tracked 0.6, in `textTertiary`, after PNG 23 (SPEC 0204).
- **Why it is wrong.**
  - Capitals with wide tracking are one of the most common marks of a templated interface.
  - Every other screen labels its sections in sentence case.
  - Capitals are harder to read and do not add hierarchy that the weight and colour do not already give.
- **The visual review names it.** The unslop review of 2026-10-31 found it, as a follow-up.
- **Decision.** On 2026-10-31 the Developer chose sentence case.

## Design Decision

**The six headers are written in sentence case — "Conta", "Preferências", "Câmera e análise", "Dados e sincronização", "Acessibilidade", "Sobre e ajuda" — with no tracking.**

- `letterSpacing` goes from 0.6 to 0, because the tracking served the capitals.
- Size (12 sp), weight (600), colour (`textTertiary`), the 16 dp line (SPEC 0215) and the 16 dp inset stay.

## Alternatives Considered

- **Keep the capitals.** Rejected by the Developer: they mark the screen as templated.
- **Sentence case with the 0.6 tracking.** Rejected: tracked lowercase reads as spaced out.

## Scope

- Includes:
  - `lib/core/features/settings/settings_screen.dart`: the six titles and `_SectionHeader`'s tracking;
  - `test/features/settings/settings_screen_test.dart` and `test/features/settings/settings_appearance_test.dart`.
- Does NOT include:
  - the rows, their order or their copy;
  - the mock, PNG 23, which still draws capitals.

## Acceptance Criteria

- `test/features/settings/settings_screen_test.dart`:
  - `section_labels_match_the_mock`, amended: "Preferências" is 12 sp, weight 600, `letterSpacing` 0, in `textTertiary`;
  - `section_labels_are_in_sentence_case`: all six headers show in sentence case, and none of the capital forms shows;
  - `section_label_sits_on_a_16_dp_line` and the "Sobre e ajuda" ordering check read the new text.
- `test/features/settings/settings_appearance_test.dart`:
  - the "Preferências" check reads the new text.

## Reproducibility

Flutter 3.44.1, Dart 3.12.1. Run the two test files above, then `flutter test`, `flutter analyze` and `mf check`.

## Risks and Assumptions

- **Departs from the mock.** PNG 23 draws capitals. The Developer chose the review over the mock here, and the mock is not changed.
- **SPEC 0204 recorded the tracking.** This spec supersedes that one point, and SPEC 0204's other decisions stand.
