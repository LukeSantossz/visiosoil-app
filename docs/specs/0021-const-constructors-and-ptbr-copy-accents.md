# SPEC: fix(ui): add const constructors and correct pt-BR copy accentuation

## Problem
Three parameterless history-grid widgets lack `const` constructors (causing
avoidable rebuilds), and roughly twenty user-facing pt-BR strings are missing
accents and cedillas, rendering misspelled copy that is inconsistent with the
correctly accented strings elsewhere in the app (for example `'Câmera'` in
Settings versus `'Camera restrita'` on the capture permission screen).

## Scope
- Includes:
  - Add a `const` constructor to `_EmptyHistoryState`, `_EmptySearchState`, and
    `_GradientOverlay` in `lib/core/features/history/widgets/history_grid.dart`,
    and use `const` at each of their three call sites.
  - Correct the accentuation/spelling of the enumerated user-facing pt-BR
    strings (see "Affected strings" below) across eight UI files.
  - Add a guard test asserting, per fixed string, that the corrected accented
    form is present and the misspelled form is absent, and that the three
    widgets declare `const` constructors.
- Does NOT include:
  - Centralizing UI strings into `AppStrings` or any constants file (a real
    single-source-of-truth move is deferred to a dedicated flutter_localizations
    effort; centralizing now would be discarded when `.arb` catalogs arrive).
  - `flutter_localizations` / i18n adoption.
  - Changing English developer-facing log or exception strings (they are
    dev-facing and correctly English per the repository language rule).
  - Any wording or copy change beyond accentuation and spelling.
  - Enabling new lint rules (for example `prefer_const_constructors`) in
    `analysis_options.yaml`.

## Affected strings
Corrections are accentuation/spelling only; wording is unchanged.

- `lib/core/widgets/permission_denied_view.dart`
  - `Abrir Configuracoes` -> `Abrir Configurações`
- `lib/core/features/settings/settings_screen.dart`
  - `Configuracoes` -> `Configurações`
  - `Versao do app` -> `Versão do app`
  - `... serao removidos permanentemente.` -> `... serão removidos permanentemente.`
  - `Esta acao nao pode ser desfeita.` -> `Esta ação não pode ser desfeita.`
- `lib/core/features/capture/widgets/camera_permission_denied_view.dart`
  - `Camera restrita` -> `Câmera restrita`
  - `Acesso a camera necessario` -> `Acesso à câmera necessário`
  - `O acesso a camera esta restrito por configuracoes do dispositivo ...`
    -> `O acesso à câmera está restrito por configurações do dispositivo ...`
  - `... precisa de acesso a camera do dispositivo.`
    -> `... precisa de acesso à câmera do dispositivo.`
- `lib/core/features/details/widgets/classification_header.dart`
  - `Confianca baixa. Considere refazer a captura com melhor `
    -> `Confiança baixa. Considere refazer a captura com melhor `
  - `iluminacao e enquadramento.` -> `iluminação e enquadramento.`
  - `Confianca moderada. O resultado pode nao refletir a textura real.`
    -> `Confiança moderada. O resultado pode não refletir a textura real.`
- `lib/core/features/home/widgets/stats_grid.dart`
  - `Analises` -> `Análises`
  - `Confianca` -> `Confiança`
- `lib/core/features/history/widgets/history_filter_bar.dart`
  - `Buscar por endereco...` -> `Buscar por endereço...`
- `lib/core/features/history/widgets/history_grid.dart`
  - `Nao foi possivel carregar o historico.`
    -> `Não foi possível carregar o histórico.`
- `lib/core/features/splash/splash_screen.dart`
  - `Solicitando permissoes...` -> `Solicitando permissões...`
  - `Permissao de camera...` -> `Permissão de câmera...`
  - `Permissao de localizacao...` -> `Permissão de localização...`
  - `Analise de textura do solo` -> `Análise de textura do solo`

## Acceptance Criteria
- corrected_copy_present_and_misspelled_absent: for each file above, the guard
  test finds the corrected accented string and does not find the original
  misspelled string.
- const_constructors_declared: `_EmptyHistoryState`, `_EmptySearchState`, and
  `_GradientOverlay` declare `const` constructors, and all three call sites use
  `const`.
- analyze_clean: `flutter analyze` reports no new issues.
- existing_tests_green: `flutter test` passes, including the existing history
  widget render tests that build the empty-state widgets.
