# SPEC: feat(onboarding): gate onboarding on first launch

## Problem
The 3-step capture onboarding is only reachable from Settings; a first-time user
is never shown it, and `OnboardingScreen.onComplete` is a dead parameter no
caller passes.

## Design Decision
Persist a single `onboarding_completed` boolean in `shared_preferences` behind an
`OnboardingStore` abstraction (provider-injected, so it is fakeable in tests),
mirroring the existing `SecureCredentialStore` store pattern. `SplashScreen`
becomes the first-launch gate: after the permission step it routes to
`/onboarding` when onboarding is not yet completed, otherwise to `/`.
`OnboardingScreen` becomes a `ConsumerStatefulWidget` that marks completion on
finish or skip and then navigates with its existing pop-or-go logic (pop when
opened over another route from Settings, go `/` when it replaced Splash). The
dead `onComplete` parameter is removed, since both entry points now work without
it.

## Alternatives Considered
- **Router-level `redirect` gating instead of Splash:** rejected because the
  `shared_preferences` read is asynchronous and a go_router redirect needs a
  bootstrapped value or a `refreshListenable` to gate on async state, which is
  more machinery; Splash is already the post-permission entry point, so gating
  there keeps the change local.
- **Keep and wire `onComplete` through go_router `extra`:** rejected because
  threading a callback through routing is indirection; in-screen persistence
  plus the screen's existing pop-or-go navigation already covers both the
  first-launch and the Settings entry points, and removing the dead parameter is
  the issue's own stated goal.
- **Store the flag in the existing secure storage
  (`KeyValueSecureStorage`):** rejected because onboarding-seen is
  non-sensitive UI state; `shared_preferences` is the right tool and avoids
  coupling this feature to the auth secure store.

## Scope
- Includes:
  - Add the `shared_preferences` dependency (regenerate `pubspec.lock` on the
    pinned toolchain).
  - `OnboardingStore` (abstract) + `SharedPreferencesOnboardingStore`
    (`hasCompletedOnboarding()`, `markOnboardingCompleted()`), and an
    `onboardingStoreProvider`.
  - `SplashScreen`: after the permission step, route to `/onboarding` when not
    completed, else `/`.
  - `OnboardingScreen`: mark completion on finish and on skip, then navigate via
    the existing pop-or-go logic; remove the dead `onComplete` parameter.
  - Unit tests for the store and widget tests for the onboarding
    persist-and-navigate behavior.
- Does NOT include:
  - Any change to the onboarding step content, copy, or visuals.
  - Any change to the permission-request flow itself.
  - A router-level redirect refactor.
  - A "reset onboarding" affordance; Settings re-opens it for reference but the
    completed flag stays set.
  - Use of the secure storage for this flag.

## Acceptance Criteria
- store_defaults_to_not_completed: a fresh store over empty preferences returns
  `false` from `hasCompletedOnboarding()`.
- store_marks_and_persists_completion: after `markOnboardingCompleted()`, a new
  store instance over the same preferences returns `true`.
- onboarding_persists_completion_on_finish: completing the last step calls
  `markOnboardingCompleted()`.
- onboarding_persists_completion_on_skip: tapping "Pular" calls
  `markOnboardingCompleted()`.
- onboarding_navigates_home_when_cannot_pop: when it cannot pop (it replaced
  Splash), completing routes to `/`.
- onboarding_pops_when_opened_over_a_route: when opened over another route (from
  Settings), completing pops back to that route.
- onboarding_onComplete_parameter_removed: `OnboardingScreen` no longer declares
  an `onComplete` parameter.
- analyze_clean: `flutter analyze` reports no new issues.
- tests_green: `flutter test` passes.

Verification note: `SplashScreen`'s routing decision (route to `/onboarding` vs
`/`) is verified by code inspection rather than a widget test. Splash is
untestable by construction here — it calls the static `PermissionService`
(`permission_handler` platform channels, no injection seam) and drives timed
`Future.delayed` transitions — matching the accepted code-inspection precedent
for by-construction-untestable criteria (specs 0007/0009 / issues #133/#137).

## Reproducibility
- Toolchain: Flutter 3.44.1 / Dart 3.12.1 (pinned per `ci.yml`).
- Run: `flutter pub get && flutter analyze && flutter test`.
- Store tests use `SharedPreferences.setMockInitialValues({})`; no randomness.

## Risks and Assumptions
- Assumption: `SharedPreferences.getInstance()` returns the plugin's cached
  singleton after first resolution, so the store may call it per method without
  a separate async provider. Invalidated only if the plugin stops caching, which
  it does not.
- Assumption: after Splash `context.go('/onboarding')`, the onboarding route
  replaces Splash so `context.canPop()` is `false` there, while a Settings
  `context.push('/onboarding')` leaves it poppable. Invalidated if the routing
  method changes; both call sites are covered by the tests and code inspection.
- Assumption: persisting completion again when re-opened from Settings is
  harmless because the write is idempotent. Invalidated only if a future
  "reset" feature needs to distinguish the two entries, which is out of scope.
