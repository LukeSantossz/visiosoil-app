# SPEC: fix(capture): recover a photograph lost when Android kills the app during capture

## Problem

On Android the system can kill VisioSoil while the camera app is in front. The photograph is taken, the app restarts on the home screen, and the photograph is gone without a word (#284).

## Design Decision

**When the app lands home, it asks `image_picker` once for a lost result.** This goes through a `LostCaptureService` seam, which maps `retrieveLostData()` to one of three outcomes:
- nothing was lost;
- a recovered photograph's path;
- a capture that could not be recovered.

A recovered photograph opens the capture screen with it. That screen then runs location and classification exactly as for a fresh capture, and the photograph is saved or discarded like any other. An unrecoverable capture shows a snackbar on home saying the photograph was lost.

**Where the check lives.** A `LostCaptureRecovery` widget wraps `MainScreen`'s scaffold, so the check runs wherever the app lands home, after the splash or after onboarding. The plugin clears its cache when read (`ImagePickerDelegate.retrieveLostImage`), so a later arrival home finds nothing.

## Alternatives Considered

- **In the splash, before it navigates.** Rejected:
  - #301 and #286 both change that screen.
  - The splash would have to learn the capture route and both of its exits, home and onboarding.
- **In `CaptureScreen.initState`.** Rejected: the app restarts on home, not on capture. The photograph would surface only if the user opened capture again, maybe much later, with nothing telling them it exists.
- **In `main()` before `runApp`.** Rejected: no navigator exists yet, so the result would have to wait in global state until home appears. The wrapper avoids that.

## Scope

- Includes:
  - `lib/core/services/lost_capture_service.dart`:
    - the sealed `LostCapture`, with `NoLostCapture`, `RecoveredCapture` (a path) and `UnrecoverableCapture`;
    - the abstract `LostCaptureService`;
    - `ImagePickerLostCaptureService`. It asks the plugin on Android only, and any other platform answers `NoLostCapture`.
  - `lib/providers/lost_capture_service_provider.dart`.
  - `lib/core/features/main/lost_capture_recovery.dart`, and `MainScreen` wrapping its scaffold in it.
  - `CaptureScreen`:
    - a new `initialImagePath`, which the `/capture` route reads from `state.extra`;
    - `_pickImage`'s steps after the pick become `_useCapturedImage(path)`, shared by a picked photograph and a recovered one.
  - `AppStrings.lostCaptureUnrecoverable`, the snackbar's pt-BR copy.
  - Tests for the service's mapping, for the recovery widget, and for the capture screen opened with a photograph.
- Does NOT include:
  - iOS. `retrieveLostData` is Android's; iOS does not lose a picker result this way.
  - What classification does with the photograph. Today it refuses every one, and #306 (SPEC 0092) changes that.
  - Deleting the recovered file. It is a picker file, so SPEC 0094's save and discard paths already delete it.
  - Several photographs in one lost result, and video. The app picks one image.
  - The permissions the splash requests (#286).

## Acceptance Criteria

- `retrieve_answers_none_for_an_empty_response`
- `retrieve_answers_the_recovered_photographs_path`: a response holding a file answers `RecoveredCapture` with that file's path.
- `retrieve_answers_unrecoverable_for_a_lost_data_exception`: a response holding an exception answers `UnrecoverableCapture`.
- `retrieve_answers_none_off_android`: off Android, the plugin is never asked.
- `a_recovered_capture_opens_the_capture_screen_with_it`: arriving home with a recovered photograph pushes `/capture` with its path, and going back returns home.
- `an_unrecoverable_capture_is_reported_on_home`: the snackbar shows `AppStrings.lostCaptureUnrecoverable`, and home stays.
- `no_lost_capture_leaves_home_alone`: nothing is pushed and no snackbar shows.
- `a_capture_screen_opened_with_a_photograph_locates_and_classifies_it`, without opening the camera:
  - the preview shows the photograph;
  - classification receives its path;
  - location is resolved.
- **Device check.** On an emulator with "Don't keep activities" enabled, a photograph taken in the camera app reaches the capture screen after the restart.

## Reproducibility

`flutter test test/core/services/lost_capture_service_test.dart test/features/main/lost_capture_recovery_test.dart test/features/capture/capture_screen_test.dart`

For the device check:
1. `adb shell settings put global always_finish_activities 1`
2. Install the release APK and open "Nova captura".
3. Take a photograph in the camera app and confirm it.
4. The app restarts, passes the splash and lands on the capture screen with the photograph.
5. `adb shell settings put global always_finish_activities 0` restores the setting.

Flutter 3.44.1, Dart 3.12.1, `image_picker` 1.2.1 with `image_picker_android` 0.8.13+15.

## Risks and Assumptions

- Assumes the device is still where the photograph was taken when the app comes back, usually seconds later. Location is resolved then, as for any capture. The record's timestamp is the recovery time, not the shutter's.
- The device check uses the emulator's camera app. A phone vendor's camera may behave differently, which the device pass (#290) covers.
- If the splash's permission requests ever block arrival home, the recovery waits with them. It is never lost, because the plugin keeps the result until it is read.
- `retrieveLostData` is unimplemented off Android, which is why the service checks the platform before it asks.
