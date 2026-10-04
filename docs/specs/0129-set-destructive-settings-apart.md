# SPEC: fix(settings): draw the destructive settings as destructive buttons, not tiles

## Problem

"Apagar todos os dados" and "Excluir conta" are settings tiles like every other, set apart only by red text, so the two irreversible actions share the visual family of the harmless ones.

The audit records it for "Apagar todos os dados" (`docs/design/ux-2026/01-current-state.md`, Settings), and the roadmap names the criterion `destructive_is_visually_distinct` (`docs/design/ux-2026/13-roadmap.md` §4). "Excluir conta", added by SPEC 0113, is built the same way.

## Design Decision

**Both become the app's destructive button:** `VisioButton(variant: VisioButtonVariant.destructive, icon: …)`, expanded to the row's width, in place of a `_SettingsTile`. That is how details already draws "Excluir registro". It is a text button in the error colour, with no tile container, border or surface, so it no longer looks like a setting. The icons, labels, confirmations and positions stay as they are.

**They keep their sections.** "Excluir conta" stays in CONTA under "Sair", and "Apagar todos os dados" stays in DADOS. Moving them into one danger zone would separate the account's deletion from the account.

## Alternatives Considered

- **A tile with an error-tinted surface and border.** Rejected: it is still a tile, so it stays in the tiles' family, only louder. The app already has a destructive pattern.
- **A single "Zona de perigo" section with both actions.** Rejected as above. It would also move "Excluir conta" away from the account it deletes.

## Scope

- Includes:
  - `lib/core/features/settings/settings_screen.dart`: the two actions as destructive `VisioButton`s. `_SettingsTile`'s `iconColor` and `titleColor` parameters, which only these two tiles set, go with them.
  - `test/features/settings/settings_screen_test.dart`: the test below.
- Does NOT include:
  - The confirmations' copy or behaviour (SPEC 0018, SPEC 0113).
  - Any other tile.

## Acceptance Criteria

- `destructive_is_visually_distinct`: "Apagar todos os dados" and, signed in, "Excluir conta" are each a destructive `VisioButton`, and neither sits inside a `_SettingsTile`.
- The existing tests pass. Three account-deletion tests tapped the confirm with `find.widgetWithText(TextButton, 'Excluir conta')`. Once the action is a `TextButton` too, that finder matches two widgets, so it is scoped to the `AlertDialog`. What the tests check is unchanged.
