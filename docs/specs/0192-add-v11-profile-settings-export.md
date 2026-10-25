# SPEC: feat(profile): add v11 profile settings and export

## Problem

The app lacks the v11 fourth Profile tab, grouped settings, and configurable CSV export.

## Design Decision

Add Profile using existing authentication and reactive local records, and reuse the base component library for statistics, theme selection and switches. Settings follows the QA decisions in v11 §16: a system/light/dark selector and a separate Sun override that remembers the underlying selection. Export shares selected CSV columns through ShareService; optional photographs are bundled in a ZIP. Counts and account identity come from real state; unavailable backup infrastructure must never claim a successful synchronization.

## Alternatives Considered

- Keep Settings as the account entry point: rejected because the approved navigation places it under Profile.
- Export every field unconditionally: rejected because location sharing must be an explicit choice.
- Render fabricated synchronization timestamps: rejected because no concrete sync backend exists.

## Scope

- Includes: the shared AccountCard with anonymous/linked identity and caller-owned actions; Profile, fourth-tab navigation, settings theme and vibration controls, export sheet and CSV sharing, tests in light/dark/Sun, and persistence required by the theme controls; a text-size selector applying 1.15 times the system scale; and the minimal SegmentedControl fixes required for a visible Sun selection and wrapping at 200% text scale.
- Does NOT include: v11 §11 features, a remote synchronization backend, classifier changes, or shared widget redesign.

## Acceptance Criteria

- Profile renders anonymous, linked, loading, error and offline states using actual account and record data in all three themes.
- Navigation exposes Início, Histórico, Dicas and Perfil; Profile opens Settings and the capture guide.
- Theme selection supports Sistema, Claro and Escuro with a separate Sun override; disabling Sun restores the underlying selection.
- Vibration uses SettingsSwitchTile with the existing persisted preference and haptic behavior.
- Export always includes class and confidence; timestamp and approximate location are included only when selected, with valid CSV escaping and neutralized spreadsheet formulas.
- Export failures remain visible and sharing cleans temporary artifacts.

## Reproducibility

Flutter 3.44.1 / Dart 3.12.1. Run `dart run build_runner build --delete-conflicting-outputs`, `flutter analyze`, and `flutter test` with `$HOME/flutter/bin` on PATH.

## Risks and Assumptions

- Camera guide, gallery saving and Wi-Fi synchronization controls remain disabled where this branch has no optional implementation; mandatory capture guidance remains enabled. Units and language display the supported fixed choices.
- The existing sync backend remains unavailable; sync controls must be disabled rather than imply backup protection.
- Photographs may be absent locally; requesting a photo archive must report missing files rather than silently omit them.
- Existing settings tests must follow intentional copy and control changes while retaining authentication and deletion coverage.

## Reference

Approved implementation brief and `/workspace/visiosoil-mocks/spec-dev/SPEC.md`, §§3.10, 3.11, 14.6 and 16; PNGs 21–24 and 35–36.
