# SPEC: fix(a11y): stop the onboarding's page slide when the device asks for no animations

## Problem

When the phone's "remove animations" setting is on, the onboarding still slides 380 ms between its steps, because `PageController.nextPage` is the one animation in the app that the setting does not shorten.

The UI/UX audit's accessibility section (`docs/design/ux-2026/12-accessibility.md` §3.4) and the roadmap's `reduce_motion_zero_duration` ask that, with animations disabled, no animation runs and no content is hidden. Item 3's first slice, SPEC 0118, left motion to a later slice. This is that slice.

The app has four animations on `main`. Flutter already shortens three of them to about one frame when the platform reports `disableAnimations`, because each runs on an `AnimationController` with the default `AnimationBehavior.normal`, which the framework runs at 5 % of its duration:

| Site | Animation | With animations disabled |
| --- | --- | --- |
| `splash_screen.dart` | the name and tagline fade in over `AppMotion.reveal` (640 ms) | about 32 ms |
| `history_grid.dart` | a thumbnail's `AnimatedSwitcher` from placeholder to photo, `AppMotion.base` (220 ms) | about 11 ms |
| route changes | the theme's page transitions | about one frame |
| `onboarding_screen.dart` | `nextPage` slide, `AppMotion.slow` (380 ms) | **380 ms, unchanged** |

The onboarding is the exception because a scroll position animates through `AnimationController.unbounded`, whose behaviour is `AnimationBehavior.preserve`. The framework keeps that duration on purpose, so a fling does not jump.

## Design Decision

**The onboarding's "Próximo" jumps instead of sliding when `MediaQuery.disableAnimationsOf(context)` is true.** `_next` calls `_controller.jumpToPage(_currentPage + 1)` in that case, and keeps `nextPage` otherwise. A swipe is the user's own gesture and is left alone.

**The other three sites are not changed.** The framework already collapses them, so code there would duplicate what it does. Tests pin the splash, the one site whose content is hidden until its animation runs, so a later change that moves it off a normal `AnimationController` is caught.

**Progress indicators keep spinning.** An indeterminate spinner repeats, and the framework preserves repeating animations so they do not flash. It is the only sign that work is running, and the audit's rule is about content hidden by motion, which a spinner does not hide.

## Alternatives Considered

- **Read `MediaQuery.disableAnimationsOf` at every site and pass `Duration.zero`.** Rejected: three of the four sites already collapse through the framework, so the change would add code that does nothing on a device. Only the onboarding needs it.
- **Remove the onboarding slide altogether.** Rejected: it is the expected feedback for most users, and the setting exists to serve the others.
- **Stop the spinners too.** Rejected for the reason above: a still spinner reads as a frozen app.

## Scope

- Includes:
  - `lib/core/features/onboarding/onboarding_screen.dart`: `_next` jumps when animations are disabled.
  - `test/features/onboarding/onboarding_screen_test.dart` and `test/features/splash/splash_screen_test.dart`: the tests below.
- Does NOT include:
  - Text scaling to 200 % (the remaining slice of item 3).
  - The progress indicators, the ink ripples and the route transitions, which the framework handles.
  - Any change to `AppMotion` tokens or to the animations' look with animations on.
  - The splash's fixed delays before it routes (1.2 s and 0.5 s). They are waits, not animations.

## Acceptance Criteria

- `onboarding_step_jumps_without_motion`: with the platform's `disableAnimations` on, one tap on "Próximo" and a single frame show the second step fully in place.
- `onboarding_step_slides_with_motion`: with animations on, the same tap and single frame leave the page between the steps. This control proves the first test can fail.
- `splash_reveal_collapses_without_motion`: with `disableAnimations` on, the splash's name fade reaches full opacity within 50 ms.
- The existing tests pass unchanged.

## Reproducibility

`flutter test test/features/onboarding/ test/features/splash/`

Flutter 3.44.1, Dart 3.12.1.

## Risks and Assumptions

- The tests set `disableAnimations` through `tester.platformDispatcher.accessibilityFeaturesTestValue`, which feeds both `MediaQuery` and the `AnimationController` scaling, as a device's setting does.
- Android's "remove animations" setting reaches Flutter as `disableAnimations`. Checking that on a device is left to the manual TalkBack pass the audit asks for.
- iOS's "Reduce Motion" reaches `dart:ui` as a separate `reduceMotion` flag. This spec reads `disableAnimations` only, the flag `MediaQuery` and `AnimationController` read, and does not verify what iOS sets. Android is the release target (#265).
