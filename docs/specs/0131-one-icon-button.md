# SPEC: refactor(a11y): build every icon-only button from one component that requires its label

## Problem

The app's six icon-only buttons are built three ways, so nothing but review keeps their labels:
- raw `IconButton`s with a tooltip, in history and its search;
- the preview's private `_CircleIconButton`;
- a styled `IconButton` over details' photograph.

The design system asks for one `VisioIconButton` whose label is a required parameter (`docs/design/ux-2026/05-design-system.md` §4.1). Its component rule (§4.3) adds two guarantees beyond the signature:
- an assert that refuses an empty label;
- a semantics test proving the label reaches the screen reader.

The accessibility criteria rely on it (`12-accessibility.md` §3.1). Roadmap item 9 lists it among the missing components, and item 3 front-loads it.

On `main`:

| Site | Today |
| --- | --- |
| `details/details_screen.dart`, back over the photograph | `IconButton`, white on `Colors.black45`, tooltip "Voltar" |
| `preview/image_preview_screen.dart`, close | `_CircleIconButton`, white on `Colors.black45`, tooltip "Fechar" |
| `history/history_screen.dart`, cancel selection | `IconButton`, tooltip "Cancelar seleção" |
| `history/history_screen.dart`, delete selected | `IconButton` in the error colour, tooltip "Excluir selecionados" |
| `history/history_screen.dart`, start selection | `IconButton`, tooltip "Selecionar registros" |
| `history/widgets/history_filter_bar.dart`, clear search | `IconButton`, 20 dp icon, tooltip "Limpar busca" |

## Design Decision

**`VisioIconButton` in `lib/core/widgets/visio_icon_button.dart`.**
- **Required:** `label`, `icon` and `onPressed`. `onPressed` may be null, which disables the button.
- **Optional:** `color`, `iconSize` and `overPhoto`.
- It renders an `IconButton` whose `tooltip` is `label`. Flutter uses the tooltip as the button's semantic label, which is how SPEC 0118 labelled these buttons, so the reading does not change.
- **`overPhoto: true`** draws the scrim the two photo buttons share: a white icon on `Colors.black45`. The two copies of that style become one.
- **The constructor asserts `label.trim().isNotEmpty`.** An assert that calls `trim()` cannot run in a `const` constructor, so the constructor is not `const`. These are six buttons; losing `const` costs nothing measurable.

**The six sites use it**, with their labels, icons, colours and sizes unchanged. `_CircleIconButton` is deleted. Details' back button loses a comment that SPEC 0119 made false ("the app registers no pt-BR Material localizations").

**The home's settings avatar is not an icon button.** It is a 40 dp outlined circle in the style of an avatar, and it already carries a label. Its 40 dp target is below 48 dp, which the all-screens check of roadmap item 3 will take up. It is out of this spec.

## Alternatives Considered

- **Keep `IconButton` and add a lint or a scan for `tooltip`.** Rejected: the design system asks for a compile error, not a check that can be silenced.
- **A `const` constructor with `label.length > 0`.** Rejected: the rule names whitespace as the case to stop, and `"  "` has a length.
- **Separate widgets for plain and over-photo buttons.** Rejected: one flag covers the only difference, the scrim.

## Scope

- Includes:
  - `lib/core/widgets/visio_icon_button.dart`.
  - The six sites above.
  - `test/core/widgets/visio_icon_button_test.dart`.
  - The source scan in `test/core/widgets/shared_components_test.dart`.
- Does NOT include:
  - The home's settings avatar.
  - The press-scale animation (item 12).
  - Buttons with text, which are `VisioButton`.

## Acceptance Criteria

- `label_reaches_semantics`: a `VisioIconButton` labelled "Fechar" renders a button node labelled "Fechar", with a tap action.
- `empty_label_is_refused`: constructing one with the label `"  "` fails its assert.
- `over_photo_draws_the_scrim`: with `overPhoto`, the button's background is `Colors.black45` and its icon is white.
- `icon_buttons_are_shared`: no file under `lib/` constructs an `IconButton(` except `core/widgets/visio_icon_button.dart`.
- The existing tests pass unchanged, including SPEC 0118's tooltip checks and SPEC 0107's check of the scrim over details' photograph.

## Reproducibility

`flutter test test/core/widgets/ test/features/`

Flutter 3.44.1, Dart 3.12.1.

## Risks and Assumptions

- The scan matches `IconButton(` at a word boundary, so `VisioIconButton(` and `IconButton.styleFrom(` do not count. A future `IconButton.filled(` would not be caught. The app has none.
