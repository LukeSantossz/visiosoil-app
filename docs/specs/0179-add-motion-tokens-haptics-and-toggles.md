# SPEC: feat(theme): add M3 motion curves, haptic tiers and toggles

## Problem

The app uses implicit animations with default curves and durations, and has no haptic feedback. When a user with vestibular sensitivity or motion sickness uses the app, they have no way to reduce movement. The guided camera gives no tactile signal when a capture is blocked.

## Design Decision

Add motion tokens, haptic tiers and user toggles that the redesign (v11 §3.11, §6.5) specifies.

**Motion tokens** in `AppMotion`:
- M3 curves: `emphasized`, `emphasizedDecelerate`, `emphasizedAccelerate`, `standard`, `standardDecelerate`, `standardAccelerate`.
- Named durations: `short` (150ms), `medium` (300ms), `long` (500ms), `extraLong` (700ms), `reducedMotion` (150ms).
- `AppMotion.durationOf(context, duration)` helper: returns `reducedMotion` (or the original if shorter) when `AppMotion.reduceMotion` is true or `MediaQuery.disableAnimationsOf(context)` is true; otherwise returns the original duration.
- `AppMotion.reduceMotion` static flag, synced with `ReduceMotionController`.

**Haptic tiers** in `AppHaptics`:
- `AppHaptics.enabled` static flag, synced with `VibrationController`.
- Five tiers: `selection` (selectionClick), `confirm` (lightImpact), `result` (mediumImpact), `blocked` (heavyImpact), `linked` (selectionClick).
- Each returns immediately if `enabled` is false.

**Toggles** in Settings (PREFERÊNCIAS section):
- Vibration switch: `ref.watch(vibrationProvider)`, persisted via `AppearanceStore.writeVibration`.
- Reduce motion switch: `ref.watch(reduceMotionProvider)`, persisted via `AppearanceStore.writeReduceMotion`.

**Startup**: `main.dart` restores both flags before `runApp`, passing them as initial provider overrides so the first frame already reflects the choice.

## Alternatives Considered

- **Platform-only reduce motion via `MediaQuery`.** Rejected: users may want to keep platform animations but reduce in-app motion, and vice versa.
- **Single haptic intensity instead of tiers.** Rejected: each tier has a semantic meaning (selection vs confirmation vs blocking).

## Scope

- Includes:
  - `lib/core/theme/app_motion.dart`: the curves, durations, `durationOf` and `reduceMotion`.
  - `lib/core/theme/app_haptics.dart`: the tiers and `enabled`.
  - `lib/core/services/appearance_store.dart`: `readVibration`, `writeVibration`, `readReduceMotion`, `writeReduceMotion`.
  - `lib/providers/appearance_provider.dart`: `initialVibrationProvider`, `vibrationProvider`, `VibrationController`, `initialReduceMotionProvider`, `reduceMotionProvider`, `ReduceMotionController`.
  - `lib/main.dart`: restoring both flags before `runApp`.
  - `lib/core/features/settings/settings_screen.dart`: `_VibrationSwitch`, `_ReduceMotionSwitch`.
  - `lib/core/features/capture/guided_camera/guided_camera_screen.dart`: wiring `AppHaptics.blocked()` on shutter tap when not ready.
  - Tests for each criterion.
- Does NOT include:
  - Wiring existing animations through `durationOf` (only the helper is added).
  - Haptics on capture success, save or share (future PRs).
  - `AppHaptics.linked()` wiring (reserved for corpus link).

## Acceptance Criteria

- `app_motion_exposes_m3_curves`: `AppMotion.emphasized`, `emphasizedDecelerate`, `emphasizedAccelerate`, `standard`, `standardDecelerate`, `standardAccelerate` are `Curve` instances.
- `durationOf_honors_static_flag`: when `AppMotion.reduceMotion` is true and the input is above 150ms, `durationOf` returns 150ms; when false, it returns the input.
- `durationOf_honors_platform`: when `MediaQuery.disableAnimationsOf` is true and the input is above 150ms, `durationOf` returns 150ms; when false, it returns the input.
- `app_haptics_enabled_gates_feedback`: each tier returns without calling HapticFeedback when `AppHaptics.enabled` is false.
- `blocked_fires_heavy_and_is_only_heavy`: `AppHaptics.blocked()` calls `HapticFeedback.heavyImpact`, and no other tier does.
- `restart_with_vibration_off`: a preference saved as off is restored before `runApp`, so the first frame sees `AppHaptics.enabled == false`.
- `restart_with_reduce_motion_on`: a preference saved as on is restored before `runApp`, so the first frame sees `AppMotion.reduceMotion == true`.
- `shutter_fires_blocked_when_not_ready`: tapping the shutter when the guidance is not ready calls `AppHaptics.blocked()` and does not capture.
- The existing settings, appearance and guided camera tests pass.

## Reproducibility

```sh
flutter test test/core/theme test/features/settings test/app_appearance_test.dart test/features/capture/guided_camera
flutter analyze && flutter test && mf check
```

Flutter 3.44.1, Dart 3.12.1, `mf` v0.8.0.

## Risks and Assumptions

- Assumption: the platform haptic APIs are available and no-op on unsupported devices.
- Assumption: `reduceMotion` and `MediaQuery.disableAnimationsOf` compose with OR, so either signal alone triggers reduced motion.
- Risk: a haptic tier misnamed as the wrong HapticFeedback method would fire the wrong intensity. The acceptance criterion pins each tier's method.
- What would invalidate this spec: a user with vestibular sensitivity who cannot disable animations through either setting.
