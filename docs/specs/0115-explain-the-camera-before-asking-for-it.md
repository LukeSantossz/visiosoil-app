# SPEC: feat(capture): explain why the camera is needed before asking for it

## Problem

The first tap on "Câmera" goes straight to Android's camera permission dialog, which carries no word from the app (#325). SPEC 0099 gave location a one-line rationale under that button (`LocationRationale`). The camera got none, so the first request VisioSoil makes is unexplained. After a denial, `CameraPermissionDeniedView` already explains and offers Settings, so only the first request is affected.

The UI/UX roadmap's item 4 sets the criterion `permission_priming_precedes_system_dialog`: "the camera permission rationale is shown before the system dialog".

## Design Decision

**One line explains the camera, the way `LocationRationale` explains location.** A new `CameraRationale` widget sits under "Câmera", above the location line, before a photograph exists. While the camera permission is not granted, it reads:

> A câmera fotografa a amostra sobre a folha A4 para classificar a textura do solo.

It follows `LocationRationale`'s rules:
- It checks the status once, through an injectable probe that defaults to `PermissionService.checkCamera`.
- A granted status shows nothing.
- A status read that throws shows nothing, rather than a claim the app cannot back.

`CaptureActions` places it and passes an optional `checkCameraPermission` probe through, as it already does for location. The capture screen's request flow does not change. The line is on screen from the moment the capture screen opens, and the system dialog only comes after the user taps "Câmera", so the rationale always precedes the dialog.

## Alternatives Considered

- **A rationale screen or dialog with "Continuar" before the system dialog**, as the reference app in PR #323 does. Rejected for the same reason SPEC 0099 gave for location: it adds a tap to every first capture and a second "no" beside the system's own. The line says the same thing without stopping the user.
- **Generalize `LocationRationale` into one `PermissionRationale` taking a message and a probe.** Rejected for now: it rewrites a tested widget that this change does not need to touch. The two widgets are short, and a third permission would be the time to merge them.
- **One combined line for camera and location.** Rejected: each line hides on its own grant, and a combined line would keep claiming a request that is no longer coming.

## Scope

- Includes:
  - `lib/core/features/capture/widgets/camera_rationale.dart`: the line and its probe.
  - `lib/core/features/capture/widgets/capture_actions.dart`: places the line under "Câmera", above the location line, and takes an optional `checkCameraPermission` probe.
  - Tests in `test/features/capture/capture_widgets_test.dart`.
- Does NOT include:
  - `CaptureScreen`, `PermissionService` and `CameraPermissionDeniedView`. The request, denied and permanently-denied flows are unchanged.
  - `LocationRationale`.
  - iOS's `NSCameraUsageDescription`, which iOS already shows in its own dialog.

## Acceptance Criteria

- `permission_priming_precedes_system_dialog`: with the camera permission not granted and no photograph, `CaptureActions` shows the camera line before "Câmera" is tapped, which is the only thing that starts the request.
- `the_camera_line_is_hidden_once_the_camera_is_granted`: with the camera permission granted, the line is absent.
- `the_camera_line_is_hidden_when_the_status_is_unreadable`: with a camera probe that throws, the line is absent.
- `the_camera_line_is_hidden_once_a_photograph_exists`: with a photograph, the line is absent.
- The existing `CameraPermissionDeniedView` and capture permission tests pass unchanged.

## Reproducibility

`flutter test test/features/capture/`

Flutter 3.44.1, Dart 3.12.1.

## Risks and Assumptions

- The line reads the status when "Câmera" is shown, not live, as `LocationRationale` does. A user who grants the camera in system settings and returns sees the line until the screen is rebuilt.
- On a first capture, both lines can show at once, one under the other. Each is one sentence, and the two requests come one after the other.
- If a platform channel is missing, as in widget tests, the probe fails and the line stays hidden.
