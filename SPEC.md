# SPEC: fix(router): add errorBuilder fallback for unknown routes and route-build failures

## Problem

`appRouter` (GoRouter) declares no `errorBuilder`, so an unmatched path (and any redirect or
parse error) falls through to go_router's default error screen — an untranslated English page,
inconsistent with the pt-BR UI. (A synchronous throw inside a `GoRoute.builder` surfaces via
Flutter's `ErrorWidget`, not go_router's `errorBuilder`, so it is out of this boundary's reach.)

## Design Decision

Add a `RouteErrorView` widget under `lib/core/widgets/` — a localized "Tela não encontrada"
`Scaffold` with a "Voltar ao início" button that invokes an injected `onGoHome` callback — and
wire `appRouter`'s `errorBuilder: (context, state) => RouteErrorView(onGoHome: () => context.go('/'))`.
The callback keeps the view testable in isolation, with no live router. Scope is the router
boundary only; the optional `main()` global `FlutterError.onError` / `runZonedGuarded` is left out
(the issue marks it optional and it is a separate concern).

## Alternatives Considered

- **Reuse `ErrorState` unchanged** (`onRetry: () => context.go('/')`) — rejected: its button is
  hardcoded to "Tentar novamente"/refresh, which misrepresents a "go home" action on a not-found
  screen.
- **Generalize `ErrorState` with a configurable action label/icon** — rejected: modifies a shared
  widget (used by history and management_tips) to serve one new caller; a dedicated purpose-view
  matches the existing pattern (`permission_denied_view.dart`) and leaves `ErrorState` untouched.

## Scope

- Includes:
  - `RouteErrorView` widget (localized message + "Voltar ao início" button → `onGoHome`).
  - `errorBuilder` on `appRouter` rendering `RouteErrorView` with `context.go('/')`.
  - Tests for the view and for unknown-route rendering.
- Does NOT include:
  - `main()` global error handling (`runZonedGuarded` / `FlutterError.onError`) — optional per the issue.
  - Changes to existing routes or the `/details` / `/preview` `state.extra` coercion.
  - Any change to `ErrorState`.

## Acceptance Criteria

- `route_error_view_shows_localized_message_and_calls_on_go_home_on_button_tap`
- `router_error_builder_renders_route_error_view_for_an_unknown_route` (a minimal
  `MaterialApp.router` with the same `errorBuilder` wiring, navigating to an unregistered path —
  deterministic, avoids the real `appRouter`'s splash timer and permission calls)
- `flutter_analyze_clean_and_full_suite_green`

## Reproducibility

- `flutter analyze`; `flutter test test/core/widgets/route_error_view_test.dart test/routes/app_router_test.dart`
  (+ full suite). Flutter 3.x / Dart 3.10.4+, go_router ^17.1.0.

## Risks and Assumptions

- Assumption: testing via a minimal local `GoRouter` (not the global `appRouter`) is sound — the
  real `appRouter` starts at `/splash`, whose 1200 ms permission timer and platform permission
  calls make an end-to-end navigation test flaky; the local router exercises the identical
  `errorBuilder` wiring deterministically.
- Assumption: `context.go('/')` is valid from the errorBuilder's context (it runs within the router).
- No ADR — localized robustness / i18n fix, not a hard-to-reverse decision.
