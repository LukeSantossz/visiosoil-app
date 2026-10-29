# SPEC: fix(splash): keep the root page across a hand-off

## Problem

Two review findings on #447 (SPEC 0217) were left open when it merged. Both still hold on `main`.

- **Deleting a record rebuilds the main screen from nothing.**
  - The boot routes on to `/` with a `BootHandOff` as the extra. `bootHandOffPage` answers it with a `CustomTransitionPage`.
  - Deleting a record from details calls `context.go('/')` with no extra. `bootHandOffPage` then answers with a `MaterialPage` under the same page key.
  - `Page.canUpdate` compares the runtime type as well as the key. The type differs, so the navigator drops the existing route and builds a new one. `MainScreen` and the tabs in its `IndexedStack` are mounted again.
  - The selected tab survives, because `mainTabIndexProvider` holds it. What the tabs hold in their own state is lost, such as the history list's scroll position and the tips tab's state.
  - The same happens to `/onboarding`, which also uses `bootHandOffPage`.
- **The boot repaints its static contours on every frame of the reveal.**
  - The green and its contour rings sit inside the `ClipPath` whose `_RevealClipper` grows on each frame.
  - `_BootContoursPainter.shouldRepaint` returns false. Even so, its `paint` runs again whenever the clip's render object repaints, because nothing caches the rings in a layer of their own.
  - The 22 contour paths and 14 dots are drawn again each frame for the length of the reveal.

## Design Decision

**`bootHandOffPage` returns one page type for every arrival, and the contours paint into their own layer.**

- **One page type.** `bootHandOffPage(state, child)` keeps its signature and always returns a private `_BootHandOffPage`.
  - The page holds the `BootHandOff` the arrival carried, or null when it carried none.
  - Its route is a `PageRoute` with `MaterialRouteTransitionMixin`, the mixin `MaterialPage`'s own route uses.
  - Going to `/` from details therefore updates the existing route in place. `MainScreen` keeps its state.
- **The route's transition is fixed by the arrival that created it.**
  - `slide` runs the boot's slide-up, which is 540 ms and has no reverse, as today.
  - `cut` runs no transition, as today.
  - Null runs the theme's transition with the theme's durations, exactly as the `MaterialPage` it replaces did.
  - A later update with another extra does not change the transition, because the route has already entered.
  - In every case, routes pushed over the page meet the theme's own secondary transition, as today.
- **Contours in a repaint boundary.** The contour `CustomPaint` inside the reveal's `ClipPath` is wrapped in a `RepaintBoundary`. The rings are painted once, and each frame of the reveal only clips the cached layer again.
  - The reduced-motion boot draws the contours outside any changing clip, so it is not changed.

## Alternatives Considered

- **Always return `CustomTransitionPage`.** Rejected. A `CustomTransitionPage` is built without a context, so it cannot read the theme's transition durations. An arrival without a hand-off, such as finishing onboarding, would run the theme's transition on go_router's fixed 300 ms instead of the theme's own timing.
- **Make details pass a `BootHandOff` when it goes home.** Rejected. Every caller that goes to `/` or `/onboarding` would have to know about the boot's extra, and the next caller to forget it would bring the remount back.
- **Leave the contours as they are.** Rejected. The fix is one widget, and it removes per-frame path drawing from the first screen every launch shows.

## Scope

- Includes:
  - `bootHandOffPage` and its private page and route in `lib/core/features/splash/splash_screen.dart`;
  - the `RepaintBoundary` around the reveal's contours in the same file;
  - their tests in `test/features/splash/splash_screen_test.dart`.
- Does NOT include:
  - the routes in `app_router.dart`, whose `pageBuilder`s stay as they are;
  - `/details`' own `NoTransitionPage` and `MaterialPage` pair (SPEC 0219). Each `/details` push gets its own page key, so the pair never updates one route;
  - the other review threads left open on #446 and #450. Both were checked against `main`: the #446 finding is fixed by the write-retry loop in `capture_screen.dart`, and the #450 test runs on the fake clock with a 6 KB contract that decodes without an isolate.

## Acceptance Criteria

- `the_root_keeps_its_state_when_reached_without_a_hand_off`:
  - the boot hands off to `/`, and its child is a stateful probe;
  - a route is pushed over it, and then `go('/')` is called with no extra;
  - the probe's `State` is the same object as before, and its `initState` ran once.
- `an_arrival_without_a_hand_off_runs_the_theme_transition`:
  - `/` is reached without an extra;
  - its route mixes in `MaterialRouteTransitionMixin`;
  - its `transitionDuration` and `reverseTransitionDuration` equal those of a plain `MaterialPage` route in the same app. It passes before the change too, and pins that the new page keeps the theme timing.
- `the_reveal_paints_the_contours_in_their_own_layer`: in the full-motion boot, a `RepaintBoundary` lies between the `boot-reveal` clip and the `boot-contours` paint.
- Existing splash tests pass unchanged, `boot_hands_off_by_sliding_up` and the reduced-motion and Modo Sol cases included.

## Reproducibility

Flutter 3.44.1, Dart 3.12.1. Run `flutter test test/features/splash`, `flutter test`, `flutter analyze` and `mf check`.

## Risks and Assumptions

- **The private route has to stay in step with `MaterialPage`.** It relies on `MaterialRouteTransitionMixin` for the theme's transition and durations. That is the mixin `MaterialPage`'s route uses, so it follows the theme the same way.
- **The extra is read only on arrival.** A hand-off extra arriving at an already-entered page does not replay the slide, and the boot never does that: it routes on once.
