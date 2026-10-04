# SPEC: refactor(ui): show every record load failure with the shared error state

## Problem

A record that fails to load, or no longer exists, is shown three ways: the shared `ErrorState`, a hand-built not-found column on details, and two hand-built views on a black canvas in the preview.

The audit counts five error presentations (`docs/design/ux-2026/03-problems.md` P2-1). Roadmap item 9 closes them under `one_error_presentation`: "all recoverable errors use one component; the black canvas variants are gone" (`docs/design/ux-2026/13-roadmap.md` §4, cross-cutting). SPEC 0123 was item 9's first slice, and left preview's two views to this one.

On `main`, after SPEC 0123:

| View | Presentation |
| --- | --- |
| history grid, management tips, details' load error | `ErrorState` |
| home's data error (`HomeDataError`) | `ErrorState`, with the home's padding |
| details, record not found | its own column: an icon and a line of text |
| preview, load error | its own column on black, with a transparent raw `AppBar`, a white outlined retry and a "Voltar" text button |
| preview, record not found | its own column on black, with a transparent raw `AppBar` and a "Voltar" text button |

## Design Decision

**The three hand-built views become an `ErrorState` under a `VisioAppBar`, on the theme's background:**

| View | Becomes |
| --- | --- |
| details, not found | `VisioAppBar(title: 'Detalhes')` over `ErrorState(message: 'Registro não encontrado')` |
| preview, load error | `VisioAppBar()` over `ErrorState(message: 'Não foi possível carregar o registro.', onRetry: …)` |
| preview, not found | `VisioAppBar()` over `ErrorState(message: 'Registro não encontrado')` |

The messages are the ones each view shows today. A not-found view has no retry, as today: there is nothing to retry.

**The preview's "Voltar" text buttons go.** The `VisioAppBar` brings the back arrow that every pushed screen has, labelled "Voltar" since SPEC 0119, so a second "Voltar" on the same view would repeat it. The preview is only reached by `context.push` from history, so there is always a route to return to.

**The preview's loading view keeps its black canvas.** It is the viewer's own background while the photograph arrives, not an error presentation, and roadmap item 10 decides the viewer's look.

**The router's `RouteErrorView` is left as it is.** It answers a location that does not exist, with a way home, and has nothing to retry. It is the router's fallback, not a record's error.

**SPEC 0123's app bar scan loses its last exception.** With preview's raw `AppBar`s gone, `VisioAppBar` is the only file that builds one.

## Alternatives Considered

- **Give `ErrorState` a dark variant for the preview.** Rejected: the audit traces the black variants to the preview's canvas (P2-1, P2-3), and asks for them to go, not to be standardised.
- **Keep the "Voltar" button inside `ErrorState`, as an optional second action.** Rejected: it grows the shared component for a duplicate of the app bar's back arrow.
- **Fold `RouteErrorView` into `ErrorState` too.** Rejected: it has a title, a description and a home action that `ErrorState` does not, and widening `ErrorState` for one caller standardises nothing.

## Scope

- Includes:
  - `lib/core/features/details/details_screen.dart`: the not-found view.
  - `lib/core/features/preview/image_preview_screen.dart`: the load-error and not-found views.
  - `test/core/widgets/shared_components_test.dart`: the app bar scan without its exception.
  - The tests below, in the details and preview test files.
- Does NOT include:
  - The preview's content and loading views (roadmap item 10).
  - `RouteErrorView`.
  - `ErrorState`'s own look or API, and any message text.
  - Empty states (`EmptyState`), which are not errors.

## Acceptance Criteria

- `one_error_presentation`: details' not-found view, and preview's load-error and not-found views, each render an `ErrorState` under a `VisioAppBar`, on a `Scaffold` with the theme's background rather than black.
- `app_bar_is_shared`: no file under `lib/` constructs an `AppBar(` except `core/widgets/visio_app_bar.dart`.
- `retry_still_reloads`: tapping "Tentar novamente" on the preview's load error asks for the record again.
- The existing tests pass unchanged.

## Reproducibility

`flutter test test/core/widgets/ test/features/details/ test/features/preview/`

Flutter 3.44.1, Dart 3.12.1.

## Risks and Assumptions

- A user who reaches the preview's error now sees a light screen between history and a black viewer. That is the audit's intent: an error is not part of the photograph.
- The preview's back arrow relies on there being a route to pop. History pushes the preview, so there always is.
