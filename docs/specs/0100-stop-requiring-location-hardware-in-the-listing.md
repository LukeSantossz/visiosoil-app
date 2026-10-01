# SPEC: fix(android): stop requiring location hardware in the Play listing

## Problem

The location permissions make Play require `android.hardware.location`, although VisioSoil saves a record without coordinates when there is no location. So a device without location hardware is filtered out of a listing whose app would work on it (#291).

## Design Decision

**The manifest declares the hardware VisioSoil uses, with what it needs:**
- `android.hardware.camera` required. Capture is camera-only by design.
- `android.hardware.location` with `android:required="false"`, since location is optional for a record.
- `android.hardware.camera.autofocus` with `android:required="false"`. Neither `aapt` 35.0.0 nor `aapt2` 36.1.0 implies it from `CAMERA` today. Android's feature reference still lists it as implied by `CAMERA`, so declaring it not required costs one line and holds whichever reading Play applies. The camera app handles focus.

Whether location exists is already handled where it is used: `LocationService` reports an error, and the record saves without coordinates.

## Alternatives Considered

- **Close #291 with the aapt evidence and change nothing.** Rejected by the Developer, who chose to fix the location requirement the evidence turned up.
- **Declare location features one by one (`location.gps`, `location.network`) as not required.** Rejected: for a target SDK of 21 or higher, the permissions imply only `android.hardware.location`, which the badging confirms. The narrower features are implied by nothing, and declaring them would add noise.
- **Leave the camera implied rather than declared.** Rejected: declaring it states the one hard requirement next to the two soft ones, and a reviewer reading the manifest sees all three.

## Scope

- Includes:
  - `android/app/src/main/AndroidManifest.xml`: the three `uses-feature` lines.
  - `test/android_config_test.dart`: tests pinning them.
- Does NOT include:
  - The permissions themselves, and when they are requested (#286, SPEC 0099).
  - The Play Console device catalog check. It needs the first upload, and #291 keeps that criterion for then.
  - iOS, which has no feature filtering of this kind.

## Acceptance Criteria

- `manifest_requires_the_camera`: the manifest declares `android.hardware.camera`, with no `android:required="false"`.
- `manifest_does_not_require_location_hardware`: it declares `android.hardware.location` with `android:required="false"`.
- `manifest_does_not_require_camera_autofocus`: it declares `android.hardware.camera.autofocus` with `android:required="false"`.
- **Badging check.** In `aapt2 dump badging` of the release APK, `android.hardware.camera` is required, and both other features appear as `uses-feature-not-required`.

## Reproducibility

`flutter test test/android_config_test.dart`, then:

```
flutter build apk --release
aapt2 dump badging build/app/outputs/flutter-apk/app-release.apk | grep feature
```

Use `aapt2` from build-tools 36.1.0. Flutter 3.44.1, target SDK 36.

## Risks and Assumptions

- Assumes Play filters by the same declared and implied features that `aapt` reports, as Android's documentation says it does. The device catalog after the first upload is where that is confirmed (#291).
- A device without location hardware can now install the app, and every capture on it saves without coordinates. That is how the app already behaves when location is denied.
