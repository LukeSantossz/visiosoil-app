# SPEC: refactor(ui): use the shared loading indicator and app bar on every screen

## Problem

The app ships a `LoadingIndicator` and a `VisioAppBar`, but five loading spinners and four app bars are built raw beside them, so the shared components standardise nothing.

The audit records both (`docs/design/ux-2026/03-problems.md` P2-1 and P2-2). Roadmap item 9 closes them under the criteria `one_loading_presentation` and `app_bar_is_shared` (`docs/design/ux-2026/13-roadmap.md` §4, cross-cutting). This is item 9's first slice.

On `main`:

| Kind | Site |
| --- | --- |
| raw `CircularProgressIndicator` | `preview/image_preview_screen.dart`, while the record loads |
| raw `CircularProgressIndicator` | `settings/settings_screen.dart`, the version tile while package info loads |
| raw `CircularProgressIndicator` | `settings/settings_screen.dart`, the account tile while auth loads |
| raw `CircularProgressIndicator` | `splash/splash_screen.dart`, under the name once it starts |
| raw `CircularProgressIndicator` | `core/widgets/visio_button.dart`, a loading button |
| raw `AppBar` | `history/history_screen.dart` |
| raw `AppBar` | `settings/settings_screen.dart` |
| raw `AppBar` | `details/details_screen.dart`, the error view and the not-found view |
| raw `AppBar` | `preview/image_preview_screen.dart`, the error view and the not-found view |

## Design Decision

**Every spinner is a `LoadingIndicator`, at the size and colour it has today.** `LoadingIndicator` already takes `size`, `strokeWidth` and `color`, so each site keeps its look:

| Site | Becomes |
| --- | --- |
| preview, loading | `LoadingIndicator()` |
| settings, version and account tiles | `LoadingIndicator(size: 16, strokeWidth: 2)` |
| splash | `LoadingIndicator(size: 24, strokeWidth: 2, color: palette.primary)` |
| `VisioButton` | `LoadingIndicator(size: 20, strokeWidth: 2, color: <the variant's colour>)` |

**The fixed-size box around each small spinner stays.** `LoadingIndicator` centres itself with a `Center`, which grows to fill loose constraints. In a settings tile's trailing slot, or inside a button, that would widen the slot or the button, so each keeps its `SizedBox` of the spinner's own size. `LoadingIndicator` itself does not change, because a screen body relies on that `Center` to put the spinner in the middle.

**History, settings and details' two fallback views use `VisioAppBar`.** It already takes `title`, `leading`, `actions` and `centerTitle`, which is all these bars use.

**Two app bars are left, each for a stated reason:**
- **Details' hero header** is a `SliverAppBar` that collapses over the photograph. `VisioAppBar` is a fixed-height bar, and a different kind of widget.
- **Preview's error and not-found views** draw a transparent bar on a black canvas. The audit traces these two views to the preview's black canvas (P2-1, P2-3). They are replaced, bar and all, by the next slice of item 9 (`one_error_presentation`), so changing their bar here would be undone by it.

## Alternatives Considered

- **Make `LoadingIndicator` shrink-wrap, with `Center(widthFactor: 1, heightFactor: 1)`.** Rejected: a screen body lays its child out with loose constraints, so every full-screen spinner that relies on the `Center` to sit in the middle would move to the top-left.
- **Add `backgroundColor` and `foregroundColor` to `VisioAppBar`, and convert preview's bars now.** Rejected: it grows the shared component's API for a variant the next slice removes.
- **Wrap details' `SliverAppBar` in a `VisioSliverAppBar`.** Rejected: a component with one caller standardises nothing.

## Scope

- Includes:
  - The five spinner sites and the four app bars named in the Design Decision.
  - `test/core/widgets/shared_components_test.dart`: a source scan for the two criteria, with the stated exceptions.
- Does NOT include:
  - Error presentations, and preview's black-canvas views (item 9, next slice).
  - Details' `SliverAppBar`.
  - Any change to `LoadingIndicator`'s or `VisioAppBar`'s own API or look.
  - Any change to a spinner's size or colour, or to an app bar's title or actions.

## Acceptance Criteria

- `one_loading_presentation`: no file under `lib/` constructs a `CircularProgressIndicator` except `core/widgets/loading_indicator.dart`.
- `app_bar_is_shared`: no file under `lib/` constructs an `AppBar(` except `core/widgets/visio_app_bar.dart` and the stated exception, `preview/image_preview_screen.dart`. A `SliverAppBar` is not an `AppBar(`.
- `spinners_keep_their_size`: the `LoadingIndicator` in a loading `VisioButton` lays out at 20 × 20 dp, and the one in the settings version tile, while package info loads, at 16 × 16 dp.
- The existing tests pass unchanged.

## Reproducibility

`flutter test test/core/widgets/ test/features/`

Flutter 3.44.1, Dart 3.12.1.

## Risks and Assumptions

- The source scan checks construction by name. A future site that builds a spinner through another widget, such as `RefreshProgressIndicator`, is not caught. The app has none today.
- Preview keeps a raw `AppBar` until the error slice lands. The scan names it as the only exception, so a new raw bar anywhere else fails.
