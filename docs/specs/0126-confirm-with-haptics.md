# SPEC: feat(feedback): confirm selections, the photograph, a save and a result with haptics

## Problem

The app never vibrates, so a selection, a photograph returning from the camera, a saved record or a classification result arrives without a touch the user can feel while looking at the sample.

The microinteraction strategy sets three haptic tiers, one per class of event, and forbids the heaviest (`docs/design/ux-2026/09-microinteractions.md` §5, rule 3 of §2). Roadmap item 12 carries them. No file under `lib/` calls `HapticFeedback` today.

This is item 12's first slice. The rest of item 12 waits on other items: the staggered verdict reveal on the result presentation (item 2), and the desaturated rejection on the quality gate (item 6).

## Design Decision

**`AppHaptics` holds the three tiers, beside `AppMotion`.** It lives in `lib/core/theme/app_haptics.dart` as an `abstract final class` with three static methods, each one call to `HapticFeedback` from `flutter/services`:

| Method | Calls | Events |
| --- | --- | --- |
| `selection()` | `selectionClick()` | a history filter chip, a bottom tab, the theme choice in settings, and a tap that toggles a record in history's selection mode |
| `confirm()` | `lightImpact()` | the photograph returning from the camera, and a record saved |
| `result()` | `mediumImpact()` | a classification arriving with a result |

**`heavyImpact` has no method.** The strategy says it is never used, so it is left out rather than discouraged.

**A long press adds no haptic of its own.** Flutter's `Feedback.forLongPress` already calls `HapticFeedback.vibrate()` on Android for every long press an `InkWell` handles, so entering history's selection mode by a long press already vibrates. A `selection()` on top would vibrate twice. Entering by the "Selecionar registros" button is a button press, like any other, and does not vibrate either.

**A failed classification does not vibrate.** The strategy gives `mediumImpact` to a result arriving and to a blocking quality verdict, and the second does not exist until item 6 lands. A failure's chip already names its cause.

**A recovered photograph does not vibrate.** The shutter's return is what `confirm()` marks. A photograph recovered after Android killed the app (SPEC 0096) arrives when the user opens the app, not when they take it.

**No setting gates the haptics.** The strategy notes that Android's `HapticFeedback` already honours the system's touch-feedback setting. No call sits in a loop.

## Alternatives Considered

- **Call `HapticFeedback` directly at each site.** Rejected: the tiers would live only in the strategy document, and nothing would stop a later site from reaching for `heavyImpact`. One class keeps the three choices in one place and lets a test scan for the fourth.
- **A user setting to turn haptics off.** Rejected: the system already has one, and duplicating it adds a setting nobody asked for.
- **Vibrate on a failed classification too.** Rejected for now, as above. Item 6's blocking verdict is where the strategy puts an alarm-like haptic.

## Scope

- Includes:
  - `lib/core/theme/app_haptics.dart`.
  - The call sites: `history_filter_bar.dart`, `main_screen.dart`, `settings_screen.dart`, `history_screen.dart`, and `capture_screen.dart` (picked photograph, save, result).
  - Tests that record the platform's haptic calls, plus a source scan.
- Does NOT include:
  - The staggered verdict reveal and the press-scale animation (item 12's later slices).
  - Haptics for the quality gate (item 6).
  - iOS-specific tuning.

## Acceptance Criteria

Each test records the calls to `HapticFeedback.vibrate` on `SystemChannels.platform`.

- `selection_clicks`: tapping a history filter chip, switching the bottom tab, choosing a theme in settings, and a tap that toggles a record in history's selection mode each make one `selectionClick`.
- `long_press_vibrates_once`: entering history's selection mode by a long press makes the platform's one long-press vibration and no `selectionClick`.
- `photograph_and_save_confirm`: a photograph returning from the camera makes one `lightImpact`, and a confirmed save makes one more.
- `result_arrival`: a classification that reports a result makes one `mediumImpact`. A failed one makes none.
- `never_heavy`: no file under `lib/` mentions `heavyImpact`.
- The existing tests pass unchanged.

## Reproducibility

`flutter test test/core/theme/ test/features/`

Flutter 3.44.1, Dart 3.12.1.

## Risks and Assumptions

- A test can show that the app asks for a haptic, not that the phone produces one. Feeling the three tiers on a device is left to a manual pass.
- Some Android phones have no vibration motor, or have touch feedback turned off. The call then does nothing, which is the intended fallback.
- On iOS, Flutter's own long-press feedback uses `heavyImpact`. That is the framework's choice, not a call in `lib/`, so `never_heavy` does not see it, and this spec leaves it alone.
