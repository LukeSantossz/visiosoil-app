# SPEC: feat(capture): capture through an in-app camera with a sheet guide and a level

## Problem

The app hands capture to the operating system's camera, so it cannot draw where the A4 sheet and the soil circle belong or tell the user to hold the phone level, and the first real session produced no photograph the classifier could read.

On 2026-10-05, 31 photographs were taken to the A4 protocol (ADR 0017). The reader refused 5 by name, 1 as `cropped` and 4 as `notFound`, and found the sheet on 26, every one of which stopped before the grid: 24 at `soilRegionTooSmall`, because the soil was spread to about 5 cm instead of 8 to 10, and 2 at `photographTooCoarse`, taken at 3200 × 1440 ([the check](../ml/sheet-reader-real-photographs.md)). The capture guide (SPEC 0142) teaches the protocol once, before the first camera launch, but nothing is on screen while the photograph is framed. `docs/design/ux-2026/06-capture-experience.md` §4 already names the remedy as its phase 2, "the in-app viewfinder", and states that no live guidance is possible while `image_picker` owns the camera.

This is the first of three slices. SPEC 0166 reads the sheet live on the preview, and SPEC 0167 captures automatically. Each ships on its own.

## Design Decision

**An in-app camera screen replaces the system camera as the default capture path.** `CaptureScreen` already takes its camera as an injected `CameraImagePicker` (`Future<XFile?> Function()`), whose default is `ImagePicker().pickImage`. The default becomes a composition of two injected pickers: push a new route, `/camera`, and await the `GuidedCaptureResult` it pops, a sealed type with three cases:

- `GuidedCaptureResult.captured(XFile)`: the picker returns the file;
- `GuidedCaptureResult.cancelled()`, also what a back gesture pops as `null`: the picker returns `null`, as the system camera's cancel does today;
- `GuidedCaptureResult.unavailable()`: the picker calls the system-camera picker, `ImagePicker().pickImage` with `requestFullMetadata: false` as today, and returns what it returns.

The composition lives in `CaptureScreen`'s default picker and nowhere else. `CaptureScreen` gains two optional injected seams beside `pickFromCamera`, used only when `pickFromCamera` is not injected:

- `openGuidedCamera`, a `Future<GuidedCaptureResult?> Function(BuildContext)`, whose default pushes `/camera`;
- `pickFromSystemCamera`, a `CameraImagePicker`, whose default is today's `ImagePicker().pickImage` call.

`CameraImagePicker` keeps its signature, so every existing capture test, which injects its own picker, runs unchanged. Nothing after the picker changes: the permission check that runs before it, location, classification, the save, and the EXIF strip in `ImageStorageService`, which keeps only the orientation tag.

**The screen, `GuidedCameraScreen`**, in `lib/core/features/capture/guided_camera/`, is locked to portrait while it is open: it awaits `SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp])` before it initialises the camera, and restores the empty list, the app's default of every orientation, after it has released the camera on dispose. It holds, top to bottom:

- **An instruction banner**: one short pt-BR sentence on a state colour taken from `AppPalette`: `primary` for green, `warning` for amber and `error` for red. The state is also carried by an icon, so it is never told by colour alone.
- **The full-screen preview**, covered by `CaptureGuideOverlay`, a `CustomPainter`:
  - **The preview fills the screen** with `BoxFit.cover`, so the overlay is laid out on the screen's rectangle, which the preview covers.
  - **The sheet outline**: a portrait rectangle of A4's aspect (210 : 297), centred, whose width is 85 % of the screen's width, or less if its height would exceed 85 % of the space between the banner and the footer, drawn as corner brackets. Outside it the preview is dimmed. The margin around it is the margin the protocol asks for.
  - **The soil target**: a circle centred in the outline whose diameter is 90 / 210 of the outline's width, the 9 cm middle of the protocol's 8 to 10 cm, labelled "8–10 cm de solo".
  - **A bubble level**: a dot that moves with the tilt inside a ring at the centre.
- **A footer**: a close button, which pops `null`, and the shutter, which is **always enabled**. The flash is forced off, as the protocol asks.

**The camera sits behind an interface, `CaptureCamera`**, so every widget test runs without the plugin. Its production implementation uses `camera` (`CameraController(description, ResolutionPreset.max, enableAudio: false)`) on the first camera `availableCameras()` lists with `CameraLensDirection.back`, which is the device's default rear camera on both platforms. After `initialize` it calls `setFlashMode(FlashMode.off)` and `lockCaptureOrientation(DeviceOrientation.portraitUp)`. The lock matters because a phone held flat over a sheet has no reliable orientation of its own, and an unlocked still could be encoded in any of four. `ResolutionPreset.max` takes the largest still the device gives, which is what `photographTooCoarse` needs.

**The lifecycle is the app's job, because the plugin no longer manages it.** The screen holds a small state machine with one controller at most:

- `inactive`, `hidden`, `paused` and `detached` release the controller, once, whichever arrives first;
- `resumed` creates and initialises a new one, unless one is already initialising;
- every initialisation carries a generation number, and an initialisation that completes after a newer one started, or after the screen was disposed, disposes its own controller and is otherwise ignored;
- dispose releases the controller and then restores the orientations.

A `CameraException` on a re-initialisation whose code is `CameraAccessDenied`, `CameraAccessDeniedWithoutPrompt` or `CameraAccessRestricted`, the plugin's codes for a camera permission refused, which means the permission was revoked while the app was away, pops `cancelled`: the next tap on "Câmera" runs `CaptureScreen`'s permission check, which already explains the denial. Any other exception pops `unavailable`.

**The level comes from `TiltSource`**, an interface over `sensors_plus`'s raw accelerometer stream, gravity included, at `SensorInterval.normalInterval`. The tilt is the unsigned angle between the phone's z axis and the vertical, `acos(clamp(|z| / |a|, 0, 1))`, in degrees: 0° with the phone flat, screen up or down, and 90° on edge. A sample whose magnitude is not finite or is below 1 m/s², such as a phone in free fall, is skipped. The angle is smoothed by an exponential moving average (α = 0.2) so the dot does not shake. `CaptureGuidance`, a pure function, maps it to the banner:

| Tilt | Colour | Sentence |
|---|---|---|
| up to 5° | green | "Nivelado. Encaixe a folha no contorno." |
| over 5° and up to 12° | amber | "Quase. Deixe o celular paralelo ao chão." |
| over 12° | red | "Segure o celular paralelo ao chão, de cima." |
| no tilt (`tiltUnavailable`) | neutral, `surfaceVariant` | "Encaixe a folha no contorno." |

The bands are starting values. If the field session of SPEC 0167 shows them wrong, a follow-up spec revises them; this one is not edited after its Gate. The level guides and never blocks: the sheet reader rectifies perspective, and a photograph taken at a tilt is still judged by the reader on the full photograph.

**`tiltUnavailable` is one state, shared by the three slices.** It holds when the device has no accelerometer, when the stream errors, or before its first valid sample. The level is hidden, the banner shows the last row above, and the shutter works. SPEC 0166 skips its tilt rows in this state, and SPEC 0167 never arms.

**Failures never strand the user:**

- No back camera, or a `CameraException` on the first initialisation: the screen pops `unavailable`, and `CaptureScreen` opens the system camera, as today.
- `takePicture` throws: a snackbar reads "Não foi possível tirar a foto. Tente de novo.", the screen stays open, and the error is recorded in `ErrorReportStore` with the source `guided_camera`.
- No accelerometer, or its stream errors: `tiltUnavailable`.

**Recovery after the process dies.** `LostCaptureService` recovers only the system camera's photograph, through `ImagePicker.retrieveLostData()`, so it keeps serving the fallback and nothing else. The guided camera needs no recovery of its own: the app's process stays alive while its own screen is open, and the only window in which a photograph exists unsaved is between `takePicture` returning and the screen popping, which is a frame.

**Platform declarations.** iOS gains `NSMotionUsageDescription`, which `sensors_plus` requires or the app crashes on reading the sensor, worded "O VisioSoil usa o sensor de movimento para mostrar se o celular está nivelado.", and `NSMicrophoneUsageDescription`, which the `camera` README's iOS setup lists, worded "O VisioSoil não grava áudio; o sistema pede esta declaração para usar a câmera." The app passes `enableAudio: false`, so the microphone is never requested. On Android, the merged release manifest must not gain `RECORD_AUDIO`. If the plugin brings it, it is removed by a `<uses-permission android:name="android.permission.RECORD_AUDIO" tools:node="remove"/>` entry, with `xmlns:tools="http://schemas.android.com/tools"` declared on the manifest's root, because the Play Data safety answers (#293) depend on it.

## Alternatives Considered

- **A document scanner (`google_mlkit_document_scanner`, VisionKit's document camera).** Rejected. Both return a cropped and enhanced page, and the reader needs the whole frame with the sheet and its surroundings untouched. The ML Kit scanner is Android-only.
- **Keep `image_picker` and improve only the guide before the camera.** Rejected. SPEC 0142 did that, and nothing can be drawn while the system camera is open.
- **Lock the shutter until the level is green**, as `06-capture-experience.md` §4's "capture lock" proposes. Rejected by the Developer: a lock that misjudges strands an agronomist in the field, and the reader on the full photograph is the judge that counts.
- **The `camera_android` (Camera2) implementation instead of the endorsed CameraX one.** Not chosen. The plugin's README says CameraX supports more devices; Camera2 stays the fallback if a device fails on CameraX.

## Scope

- Includes:
  - `pubspec.yaml` and `pubspec.lock`: `camera` and `sensors_plus`, at the versions pub resolves under Flutter 3.44.1 (`camera` 0.12.1 and `sensors_plus` 7.1.1 at the time of writing).
  - `lib/core/features/capture/guided_camera/`: `GuidedCameraScreen`, `CaptureGuideOverlay`, `CaptureCamera` and its plugin implementation, `TiltSource` and its plugin implementation, `CaptureGuidance`.
  - `lib/core/routes/app_router.dart`: the `/camera` route.
  - `lib/core/features/capture/capture_screen.dart`: the default picker composes the guided camera and the system camera through `GuidedCaptureResult`.
  - Providers for `CaptureCamera` and `TiltSource`, so tests inject fakes.
  - `ios/Runner/Info.plist`: `NSMotionUsageDescription` and `NSMicrophoneUsageDescription`.
  - `android/app/src/main/AndroidManifest.xml`: the `RECORD_AUDIO` removal, only if the plugin merges it.
  - Tests for each criterion.
  - The route, provider and widget counts in `docs/agents/project.md` and the README, with `CLAUDE.md` and `AGENTS.md` regenerated by `mf agents sync`, never edited; and the status of phase 2 in `docs/design/ux-2026/06-capture-experience.md`.
- Does NOT include:
  - Reading the sheet on the preview, or any message about the sheet or the soil (SPEC 0166).
  - Automatic capture (SPEC 0167).
  - Live blur, exposure or glare checks; `ImageQualityAnalyzer` stays without a caller until its thresholds are calibrated.
  - Zoom, a manual flash, the front camera, landscape capture, or gallery selection.
  - Any change to the sheet reader, the grid, the contract, or a refusal's copy.

## Acceptance Criteria

- `tilt_is_the_angle_to_gravity`: `TiltSource`'s angle for the accelerometer vectors (0, 0, 9.81), (0, 0, −9.81), (0, 9.81, 0), and the vectors at 5° and 12° from the z axis is 0°, 0°, 90°, 5° and 12° within 0.01°; a vector whose |z| / |a| rounds above 1 gives 0°, not NaN.
- `a_degenerate_sample_is_skipped`: the vectors (0, 0, 0), (0, 0, 0.5) and one holding a NaN leave the smoothed angle unchanged, and a stream that has produced only such samples is `tiltUnavailable`.
- `tilt_is_smoothed`: a single reading of 30° after a run of 0° moves the smoothed angle by α × 30° = 6°, not to 30°.
- `tilt_bands_name_the_sentence`: `CaptureGuidance` returns green and "Nivelado. Encaixe a folha no contorno." at 0° and 5°, amber and "Quase. Deixe o celular paralelo ao chão." at 5.01° and 12°, red and "Segure o celular paralelo ao chão, de cima." at 12.01° and 90°, and neutral and "Encaixe a folha no contorno." for `tiltUnavailable`. Each state carries its own icon.
- `the_guide_is_drawn`: with a fake camera, the screen shows the preview, the soil target's label "8–10 cm de solo", the level, the close button and the shutter.
- `the_guide_has_the_sheets_proportions`: `CaptureGuideOverlay`'s layout, computed for a 390 × 844 and a 360 × 640 logical screen, gives an outline whose height over width is 297 / 210 within 0.5 %, whose width is 85 % of the screen's or whose height is 85 % of the space between banner and footer, whichever is smaller, and a target whose diameter is 90 / 210 of the outline's width within 0.5 %, centred in the outline within 1 logical pixel.
- `the_banner_follows_the_tilt`: a fake `TiltSource` stepping through 0°, 8° and 20° changes the banner's sentence and colour accordingly.
- `the_shutter_returns_the_photograph`: tapping the shutter calls `takePicture` once and pops `captured` with its `XFile`, and `CaptureScreen` runs today's flow on it.
- `a_double_tap_takes_one_photograph`: two taps in the same frame call `takePicture` once.
- `the_shutter_is_never_disabled`: at 20° the shutter is enabled and a tap captures.
- `close_returns_nothing`: the close button and the back gesture each make the picker return `null`, and `CaptureScreen` keeps whatever photograph it held.
- `no_camera_falls_back_to_the_system_camera`: when the fake camera lists no back camera, or throws on the first initialise, the screen pops `unavailable` and the injected `pickFromSystemCamera` is called once, its file returned; on `captured` and `cancelled` it is not called.
- `a_failed_shot_keeps_the_screen`: when `takePicture` throws, the snackbar shows, the screen stays open, `ErrorReportStore` records the error with the source `guided_camera`, and a second tap captures.
- `no_sensor_blocks_nothing`: when `TiltSource` errors, the level is hidden, the banner reads "Encaixe a folha no contorno.", and the shutter captures.
- `the_camera_follows_the_lifecycle`: `inactive`, then `paused`, release the fake camera once, and `detached` alone releases it too; `resumed` initialises one new camera; a second `resumed` while that initialisation is pending starts none; an initialisation that completes after dispose disposes its camera.
- `a_revoked_permission_cancels`: a re-initialisation that throws an access-denied `CameraException` pops `cancelled`, not `unavailable`.
- `the_orientation_is_restored`: the screen sets portrait-up before the fake camera's `initialize` is called, and restores every orientation after its release on dispose.
- `the_camera_is_configured`: the production `CaptureCamera` selects the first back-facing camera listed, creates its controller with `ResolutionPreset.max` and `enableAudio: false`, and after initialise sets `FlashMode.off` and locks the capture orientation to portrait-up (checked against the plugin's platform interface with a fake platform).
- `no_audio_permission_on_android`: the merged manifest of `flutter build apk --release` declares no `android.permission.RECORD_AUDIO`.
- On a device (Developer), recorded in the PR with the phone's model and OS: a photograph taken through the guided screen with the phone held flat over a sheet is saved and classified, or refused by name, by today's flow; the stored file's pixel dimensions equal those of the still `takePicture` returned; it displays upright in history; and `decodeJpgExif` on the stored bytes yields the orientation tag and nothing else.
- The router registers `/camera`, and every existing capture test passes, with the picker still injected.

## Reproducibility

```sh
flutter test test/features/capture test/routes
flutter analyze && flutter test && mf check
flutter build apk --release   # then inspect the merged manifest for RECORD_AUDIO
```

Flutter 3.44.1, Dart 3.12.1, `mf` v0.8.0.

## Risks and Assumptions

- **Risk: the camera lifecycle across backgrounding and permission revocation**, the first risk `06-capture-experience.md` §4 names. Covered by `the_camera_follows_the_lifecycle` with a fake, and by the device check with the real plugin.
- **Risk: a device the CameraX implementation fails on.** The fallback to `image_picker` keeps capture working on it.
- **Risk: iOS parity.** CI builds iOS but runs no iOS device test, so the iOS path is checked only by the build and by a device, if one is available.
- **Assumption: the guide's proportions match the protocol's sheet.** The outline is drawn at A4's aspect, and the target at 90 / 210 of its width, so a sheet that fills the outline shows the soil circle at the size the protocol asks for.
- **What would invalidate this spec:** a change to the capture protocol, or a decision to keep the system camera.
