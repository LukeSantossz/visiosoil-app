# SPEC: feat(camera): show the light in lux and the distance in centimetres

## Problem

The guided camera's quality chips name a verdict, not a measure, and the mock shows a measure.

- **What the chips say.** "Luz" reads "Boa", "Baixa" or "Excessiva", and "Distância" reads "Enquadrada" or "Ajuste a moldura" (SPEC 0166, SPEC 0224). Screens 10 to 12 of the v11 mock read "Baixa · 180 lx" and "48 cm" (`docs/design/spec/SPEC.md` §3.4), and the fidelity map marks them partial.
- **The frame cannot give either number.** `LiveQuality` judges light by the frame's mean grey, which the camera's auto exposure has already normalised. The `camera` plugin on Android reports neither the exposure time, the sensitivity nor the aperture, so no illuminance can be computed from a frame. Nor does it report the lens's focal length or the sensor's size, so a distance cannot be computed from the sheet's size in the frame. A number made up from either would be the fictional data SPEC 0202 §11 forbids.
- **The phone has both.** The ambient light sensor measures the illuminance on the phone's face in lux, and the face looks up at the light falling on the sheet when the camera looks down. Camera2's characteristics give the focal length and the sensor's physical size, and with the sheet's 297 mm the live reader already measures, they give the distance by the thin-lens equation.
- **Decision.** On 2026-10-29 the Developer chose the lux from the ambient light sensor, the distance from the focal length read natively, and the protocol as the distance's target, not the mock's 18 to 25 cm. Flash and gallery stay out (ADR 0017).

## Design Decision

**On Android, the light chip adds the ambient light sensor's lux to its verdict, and the distance chip shows the sheet's estimated distance in place of its words. Each chip's verdict does not change.**

### The numbers

- **Lux.** `AmbientLightSource.lux` streams the sensor's readings. The light chip reads "<verdict> · <lux>", for example "Boa · 1.480 lx": the lux below 100 is whole, from 100 it is rounded to the nearest 10, with a dot between thousands. The shown lux refreshes at most twice a second.
- **Distance.** `CameraOpticsSource.opticsOf(cameraId)` returns the camera's focal length in millimetres and the long side of its active pixel array in millimetres. For a found sheet, the sheet's image on the sensor is `h = sheetLongSidePx × activeLongSideMm / readLongSidePx`, and the distance from the lens is `f × (1 + 297 / h)`. The distance chip reads "≈ 34 cm", rounded to the whole centimetre. The "≈" says it is an estimate: it assumes the stream spans the active array's long side, a flat sheet, and a lens without distortion.
- **When a number is unknown, the chip says what it says today.** No light sensor, no reading yet, a sensor error or a platform other than Android keep the verdict alone. No optics, optics with a focal length or sensor side that is not positive, or a reading without a whole sheet keep the distance's words.

### The verdicts

- The light verdict stays the frame's (`LiveQuality`). No threshold is set on the lux: the sensor reads the light on the phone's face, not on the sheet, and the project has no evidence for a lux limit.
- The distance verdict stays the protocol's rows (SPEC 0166, SPEC 0169, SPEC 0224): the whole sheet in the frame and its 297 mm side spanning at least 2299 px in the still. No centimetre target is shown or checked; the mock's 18 to 25 cm is not this protocol's. On a typical 12 MP main camera, a 5.6 mm lens over a 7.3 mm active side, the whole sheet fits beyond about 23 cm and spans 2299 px up to about 40 cm.
- The shutter, the automatic capture and the blocked alert do not change.

### The platform side

- `MainActivity` gains two channels and no dependency is added:
  - the method channel `com.visiosoil.app/camera_optics`, whose `opticsOf` takes a Camera2 camera id and replies `{focalLengthMm, activeLongSideMm}` from `LENS_INFO_AVAILABLE_FOCAL_LENGTHS[0]`, `SENSOR_INFO_PHYSICAL_SIZE`, `SENSOR_INFO_PIXEL_ARRAY_SIZE` and `SENSOR_INFO_ACTIVE_ARRAY_SIZE`, or null when one is missing;
  - the event channel `com.visiosoil.app/ambient_light`, which registers a `Sensor.TYPE_LIGHT` listener while it is listened to and unregisters it on cancel. A phone without the sensor ends the stream.
- The Dart sources turn a missing plugin, a platform error or a malformed reply into "unknown", never into an error on the screen.
- `CaptureCamera` gains `cameraId`, the open camera's Camera2 id: the `camera` plugin's `CameraDescription.name` on Android, which `camera_android_camerax` fills from `Camera2CameraInfo.getCameraId`.
- The screen reads the optics each time it opens or switches a camera, and listens to the light only while a camera is live.

### Where the code lives

- `lib/core/features/capture/guided_camera/camera_optics.dart`: `CameraOptics`, `CameraOpticsSource`, `PlatformCameraOpticsSource` and `estimatedDistanceMm`.
- `lib/core/features/capture/guided_camera/ambient_light_source.dart`: `AmbientLightSource` and `PlatformAmbientLightSource`.
- `Formatters.distanceCm` and `Formatters.lux`, which the details' "Captura" row will also read.
- `cameraOpticsSourceProvider` and `ambientLightSourceProvider` in `guided_camera_provider.dart`, overridden in tests as `tiltSourceProvider` is.

## Alternatives Considered

- **A lux package from pub.dev.** Rejected. The focal length already needs a native channel, and one more channel there reads the same sensor without a dependency to vet.
- **A relative light percentage from the frame.** Rejected by the Developer: the frame's grey is normalised by auto exposure, so its percentage says little about the light.
- **The distance from a typical 26 mm-equivalent lens.** Rejected by the Developer in favour of each phone's own focal length.
- **Gate the shutter on a lux or centimetre range.** Rejected. The protocol's limits are in pixels and already gate it; a second gate in other units could only disagree with them.
- **iOS.** Left out. iOS has no public ambient light API, and the app ships to Play first; its chips keep today's words.

## Scope

- Includes:
  - `camera_optics.dart` and `ambient_light_source.dart`, new;
  - `capture_camera.dart` (`cameraId`), `guided_camera_screen.dart` (the two chips) and `guided_camera_provider.dart`;
  - `lib/core/utils/formatters.dart`;
  - `android/app/src/main/kotlin/com/visiosoil/app/MainActivity.kt`;
  - the tests below and `test/support/fake_capture_camera.dart`.
- Does NOT include:
  - storing the numbers with a record, and the details' "Captura" row (its own spec, schema v12);
  - the flash and the gallery, which stay out;
  - any verdict, threshold, gate or alert text;
  - iOS.

## Acceptance Criteria

- `test/features/capture/guided_camera/camera_optics_test.dart`:
  - `distance_follows_the_thin_lens`: a focal length of 5.6 mm, an active long side of 7.3 mm, a read long side of 1024 px and a sheet of 700 px give 339 ± 1 mm.
  - `distance_is_unknown_without_usable_optics`: a focal length, sensor side or sheet side that is zero or negative gives null.
  - `platform_optics_reads_the_channel_reply`: a mocked `opticsOf` reply gives the two numbers and sends the camera id; a null reply, a reply missing a number, a `PlatformException` and a `MissingPluginException` each give null.
- `test/features/capture/guided_camera/ambient_light_source_test.dart`:
  - `platform_light_streams_the_sensor_lux`: a mocked event of 1480.0 reaches the stream as 1480.0.
  - `platform_light_stays_quiet_on_an_error`: an error event and a missing plugin each reach the stream as no value and no error.
- `test/utils/formatters_test.dart`:
  - `distance_reads_approximate_whole_centimetres`: 339 mm reads "≈ 34 cm".
  - `lux_reads_rounded_with_a_thousands_dot`: 87.4 reads "87 lx", 1483 reads "1.480 lx", 12345 reads "12.350 lx".
- `test/features/capture/guided_camera/guided_camera_numbers_test.dart`:
  - `light_chip_adds_the_sensor_lux`: with good light and a sensor reading of 1480, the light chip reads "Boa · 1.480 lx" with the ready status.
  - `light_chip_keeps_its_verdict_without_a_sensor`: with no reading, it reads "Boa".
  - `light_chip_refreshes_at_most_twice_a_second`: a second reading 400 ms after the first is not shown yet, and is shown at 500 ms.
  - `distance_chip_shows_the_estimate_for_a_found_sheet`: with optics and a found sheet on a ready row, the distance chip reads "≈ 34 cm" with the ready status.
  - `distance_chip_keeps_a_failed_status_beside_the_estimate`: on a too-coarse row, it reads "≈ 34 cm" with the failed status.
  - `distance_chip_keeps_its_words_without_optics`: with no optics, it reads "Enquadrada" for a ready row.
  - `distance_chip_keeps_its_words_without_a_whole_sheet`: with optics and a cropped sheet, it reads "Ajuste a moldura".
  - `optics_are_read_for_each_camera`: opening the camera, then switching it, asks `opticsOf` for each camera's id.
  - `light_is_heard_only_while_the_camera_is_live`: opening the capture guide cancels the light subscription, and coming back listens again.
- The present guided camera tests pass, with the fake camera giving an id and the default test sources giving no optics and no light.
- On a phone, by hand: the chips show a lux that rises under a lamp and a distance within a few centimetres of a tape measure at 30 cm.

## Reproducibility

Flutter 3.44.1, Dart 3.12.1. Run `flutter test test/features/capture test/utils/formatters_test.dart`, then `flutter test`, `flutter analyze`, `flutter build apk --release` and `mf check`.

## Risks and Assumptions

- **The Kotlin side has no automated test.** The tests stop at the channels. The phone check above and CI's release build and emulator smoke are what cover it; an emulator has no real light sensor or lens.
- **A logical multi-camera.** On a phone whose back camera is a logical camera, the first focal length is the default physical lens at 1×. The guided camera does not zoom, so that is the lens shooting; a phone that switches lenses on its own would make the estimate wrong without warning.
- **The stream's crop.** The estimate assumes the preview stream keeps the active array's long side. A stream that crops it would read the sheet as farther away than it is. The verdict does not use the estimate, so the shutter is not affected.
- **The lux is the phone's, not the sheet's.** A phone that shades the sheet, or a lamp to one side, makes the two differ. The chip shows it beside the frame's verdict, and gates nothing.
