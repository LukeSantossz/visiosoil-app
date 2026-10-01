# SPEC: fix(permissions): ask for camera and location when capture needs them, not at launch

## Problem

The splash asks for the camera and location on first launch, before onboarding and before the user has done anything that needs either. On Android the location dialog also carries no word from the app about why it wants it (#286).

## Design Decision

**The splash asks for nothing.** It keeps its reveal and its "Iniciando..." line, and goes to onboarding or home at the same moment it did when both permissions were already granted.

**Capture asks, as it already does on its own:**
- the camera when the user taps "Câmera", through the screen's existing check and request seams;
- location once the photograph arrives, through `LocationService`, which requests it when it is missing.

So a first capture asks for the camera, then location, each once. A denied location already saves the record without coordinates.

**One line explains location.** Before a capture, while location is not granted, a `LocationRationale` line under "Câmera" says that the device's location marks where the sample was collected, and that the record is saved without coordinates if location is denied. On Android it is the app's only word on why it wants location. iOS already shows `NSLocationWhenInUseUsageDescription` in its dialog.

`LocationRationale` checks the status through an injectable probe that defaults to `PermissionService.checkLocation`, like the capture screen's camera seams. `CaptureActions` places it and passes an optional probe through. So this change does not touch `capture_screen.dart`, which #307 and #308 change.

## Alternatives Considered

- **An explanation dialog before the system's location prompt.** Rejected: it adds a tap to every first capture and a second "no" beside the system's own. Android's guidance keeps an educational screen for after a denial. The line says the same thing without stopping the user.
- **Ask for location when "Câmera" is tapped, before the camera opens.** Rejected: two system dialogs would stand between the user and the camera. Location is only needed once a photograph exists, which is where `LocationService` already asks.
- **Keep the splash requests and add the line.** Rejected: the splash would still ask before onboarding has said what the app is for, which is what #286 is about.

## Scope

- Includes:
  - `lib/core/features/splash/splash_screen.dart`: `_requestPermissions` and its two requests go. The reveal, the "Iniciando..." line and the routing to onboarding or home stay.
  - `lib/core/features/capture/widgets/location_rationale.dart`: the line and its probe.
  - `lib/core/features/capture/widgets/capture_actions.dart`: places the line under "Câmera" before a photograph exists, and takes an optional probe.
  - Tests:
    - the splash, through a router with the permission channel recorded;
    - the line, through `CaptureActions`;
    - a new `test/features/capture/capture_permissions_test.dart` for the capture's order and for a save without location.
- Does NOT include:
  - `CaptureScreen` and `LocationService`. Their requests already happen where they should.
  - A way to reopen settings after a permanent location denial. The chip still reads "Sem localização".
  - The copy of the permission dialogs, which the platforms own, and iOS's usage descriptions, which already explain both permissions.
  - Onboarding's copy.

## Acceptance Criteria

- `first_launch_requests_no_permission`: the splash, pumped until it routes, makes no call on `permission_handler`'s channel and lands on onboarding.
- `first_capture_requests_the_camera_then_location_once_each`: with neither permission granted, a capture calls the camera request once, then the location resolver once, in that order.
- `a_capture_without_location_still_saves_the_record`: when location is denied, saving creates one record with no coordinates and the unavailable-address text.
- `the_location_line_shows_before_a_capture_while_location_is_not_granted`
- `the_location_line_is_hidden_once_location_is_granted`
- `the_location_line_is_hidden_once_a_photograph_exists`

## Reproducibility

`flutter test test/features/splash/ test/features/capture/`

Flutter 3.44.1, Dart 3.12.1, `permission_handler`, whose method channel is `flutter.baseflow.com/permissions/methods`.

## Risks and Assumptions

- Assumes `LocationService`'s Geolocator request and `PermissionService`'s `permission_handler` check read the same Android permission, `ACCESS_FINE_LOCATION`. They do, which is why the line disappears once the Geolocator prompt is accepted.
- The line reads the status when "Câmera" is shown, not live. A user who grants location in system settings and returns sees it until the screen is rebuilt, for example after a discard.
- If a platform channel is missing, as in widget tests, the probe fails and the line stays hidden. That is the right failure: no claim the app cannot back.
