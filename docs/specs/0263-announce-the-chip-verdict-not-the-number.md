# SPEC: fix(capture): announce the chip verdict, not the number

## Problem

QA on PR #464 (SPEC 0238, the light and distance numbers on the guided camera's chips) returned it as "Com bug" with one bug and four non-blocking findings. The Dev audit of 2026-11-05 on `107f7f9` found the bug still present. This change closes the bug and the three findings that are about the code; the other two are not defects of the tree (see Scope).

1. **The chips announce numbers that change all the time.** The three quality chips (`QualityChip`, `lib/core/features/capture/guided_camera/quality_chip.dart`) are polite live regions whose semantics label is `'$label, $value'`. Since SPEC 0238 the Luz chip's value carries the ambient sensor's lux, `Boa · 1.480 lx`, refreshed up to twice a second, and the sensor's noise changes it on most refreshes. The Distância chip's value is the sheet's estimated distance, `≈ 34 cm`, recomputed on every accepted live reading. A live region is announced each time its label changes, so with TalkBack on the two chips are read aloud continuously, and the announcements that matter (the light turning `Boa`, the sheet becoming framed) are lost in them.
2. **A reading that is not a number crashes the build.** `Formatters.lux` and `Formatters.distanceCm` call `round()`, which throws on NaN and infinity, and both run inside the camera screen's `build`. `PlatformAmbientLightSource` passes on any `num` the channel sends, and `estimatedDistanceMm` checks only that its inputs are positive, so an infinite focal length or size passes and gives an infinite distance.
3. **A long value can change the panel's height.** The chip's value text has no line limit. In a narrow chip a long value, such as `Excessiva · 12.350 lx`, wraps to a second line, so the chip and the panel grow when the number appears and shrink when it goes, which the chip's own comment says must not happen.
4. **The Kotlin side has no test.** `MainActivity`'s optics channel computes the active array's long side, and its light handler forwards the sensor's value, with no automated test, and nothing in CI runs a JVM test for the app module.

Source: Trello card "[P1] Redesign · Câmera guiada: chips, obturador, aviso foto ruim (retrato)" (list Com bug), the QA review of PR #464 (https://github.com/LukeSantossz/visiosoil-app/pull/464#issuecomment-6551596822) and the Dev audit of 2026-11-05.

## Design Decision

### 1. The chip announces its verdict

- `QualityChip` takes an optional `spokenValue`. Its semantics label is `'$label, ${spokenValue ?? value}'`, so a chip whose value is already a verdict is unchanged.
- The Luz chip passes the light verdict alone: `Boa`, `Excessiva` or `Baixa`, and `Ajustando…` before the first reading. Its visible value is unchanged.
- The Distância chip passes its verdict: `Enquadrada` when the row is ready, `Ajuste a moldura` when the block is a distance cause, and `Ajustando…` otherwise. These are the words the chip already shows when there is no estimate. Its visible value is unchanged.
- The Foco chip's value is already a verdict and passes nothing.
- The chips stay live regions without a tap action.

A chip's label therefore changes only when its verdict changes, and a live region whose label does not change is not announced again.

### 2. Only finite readings reach the chips

- `PlatformAmbientLightSource` passes on a reading only when it is finite and not negative. Anything else is not an illuminance, and is dropped as a missing plugin's silence is.
- `estimatedDistanceMm` returns null unless its inputs are finite and positive and its result is finite.
- On the Kotlin side the light handler sends a value only when it is finite and not negative, and the optics reply is null unless the focal length and the active long side are finite and positive (see 4).
- `Formatters.lux` and `Formatters.distanceCm` state in their documentation that they take a finite value, which the two sources now guarantee. They are not changed to accept a non-number: there is no honest text for one, and the chip already has its words for "no number".

### 3. The value keeps to one line

The chip's value text takes `maxLines: 1` and an ellipsis, so the chip's height does not depend on its value. Its label is a constant and is left as it is. The full value stays in the chip's semantics label only where it is a verdict (see 1); the number a narrow chip cuts short is the same number SPEC 0240 keeps with the record.

### 4. The Kotlin arithmetic is tested on the JVM

- The arithmetic leaves `MainActivity` for `CameraReadings`, an `internal object` in `android/app/src/main/kotlin/com/visiosoil/app/CameraReadings.kt`, with no Android type in its signatures: `focalLengthMm(focals: FloatArray?)`, `activeLongSideMm(physicalLongMm: Float, activeLongPx: Int, pixelLongPx: Int)` and `luxOf(values: FloatArray)`, each returning null when its input is not a measurement. `MainActivity` calls them and keeps the Android calls.
- `android/app/src/test/kotlin/com/visiosoil/app/CameraReadingsTest.kt` tests them with JUnit 4, declared in `android/app/build.gradle.kts` as `testImplementation("junit:junit:4.13.2")`.
- CI's `build` job runs `./gradlew :app:testReleaseUnitTest` in `android/` after it builds the release APK, so a failing Kotlin test fails the build.

The Kotlin channel code that needs a device (the sensor registration, the Camera2 lookup) is still not tested automatically.

## Alternatives Considered

- **Debounce the chips' announcement.** Rejected: a debounced number still re-announces every interval while the sensor is noisy, and delays the verdict change the agronomist waits for.
- **Drop `liveRegion` from the chips.** Rejected: the card's acceptance criterion asks for live chips, and without it a TalkBack user hears no verdict change.
- **Announce the number only when the verdict changes.** Rejected: the number read then is one noisy sample of a value SPEC 0238 sets no threshold on.
- **Make `Formatters.lux` return a placeholder for NaN.** Rejected: a non-number is not a reading, and the chip already shows its verdict alone when there is no number, so the source is the place to drop it.
- **Let the value wrap to two lines.** Rejected: the panel would still move between a one-line and a two-line value.
- **Robolectric tests of `MainActivity`.** Rejected for this change: a new test runtime and an Android SDK on the JVM for what is arithmetic; the pure functions cover the computation.

## Scope

- Includes:
  - `lib/core/features/capture/guided_camera/quality_chip.dart`: `spokenValue`, the label built from it, and the value's line limit;
  - `lib/core/features/capture/guided_camera/guided_camera_screen.dart`: the Luz and Distância chips pass their verdict;
  - `lib/core/features/capture/guided_camera/ambient_light_source.dart` and `camera_optics.dart`: the finite guards;
  - `lib/core/utils/formatters.dart`: the documented precondition;
  - `android/app/src/main/kotlin/com/visiosoil/app/CameraReadings.kt` (new) and `MainActivity.kt`;
  - `android/app/src/test/kotlin/com/visiosoil/app/CameraReadingsTest.kt` (new) and the JUnit test dependency in `android/app/build.gradle.kts`;
  - `.github/workflows/ci.yml`: the Kotlin unit test step in `build`, and the `build` description in `docs/agents/project.md` with the instruction files `mf agents sync` generates from it;
  - Dart tests under `test/features/capture/guided_camera/`.
- Does NOT include:
  - QA's third finding, a stale reading shown for an instant with a switched camera's optics, which QA judged harmless;
  - QA's fifth finding, the out-of-date spec numbers in PR #464's description, which is not in the tree;
  - the shutter, the blocked feedback or any other part of the redesign card;
  - the lux refresh rate, the distance estimate's formula, or a device run of the Kotlin channels.

## Acceptance Criteria

Each test below is red before the change unless it says otherwise.

- `light_chip_announces_the_verdict_without_the_lux`: with good light and the sensor at 1480 lx, the Luz chip's semantics label is `Luz, Boa` and its visible value is still `Boa · 1.480 lx`.
- `light_chip_label_holds_while_the_lux_changes`: the sensor going from 1480 to 57 lx under the same verdict leaves the Luz chip's semantics label unchanged.
- `distance_chip_announces_the_verdict_without_the_estimate`: with a found, ready sheet and known optics, the Distância chip's semantics label is `Distância, Enquadrada` while its visible value is the estimate.
- `focus_chip_announces_its_value`: the Foco chip's label is `Foco, Nítido` with good focus (green before the change: it pins what stays).
- `platform_light_drops_a_reading_that_is_not_a_measurement`: NaN, infinity and a negative value sent on the channel do not reach the stream, and a finite reading after them does.
- `distance_is_unknown_for_a_reading_that_is_not_finite`: `estimatedDistanceMm` is null for an infinite focal length, an infinite active side and a NaN sheet span.
- `chip_height_does_not_follow_its_value`: a chip 90 dp wide at text scale 1.2 has the same height with `Boa` as with `Excessiva · 12.350 lx`.
- `CameraReadingsTest`: the active long side for a 7.3 mm, 4000 px of 4032 px sensor; null for a non-positive or non-finite physical size, and for a non-positive pixel count; the first focal length, and null for an empty, null, zero or NaN list; the lux of a sensor event, and null for an empty, NaN, infinite or negative value.
- `chips_cover_every_state_and_passive_semantics` and the rest of the guided camera tests still pass.
- `flutter test`, `flutter analyze`, `./gradlew :app:testReleaseUnitTest` and `mf check` pass, apart from the palette goldens that fail only on this machine.

## Reproducibility

Flutter 3.44.1, Dart 3.12.1: `flutter test test/features/capture/guided_camera/`, then `flutter test`, `flutter analyze` and `mf check`. JDK 17: after `flutter build apk --release`, run `./gradlew :app:testReleaseUnitTest` in `android/`.

## Risks and Assumptions

- **Assumption:** TalkBack announces a polite live region when its semantics label changes, and not when only its excluded children change. No device run is part of this change; the widget tests check the label, not the speech.
- **A sighted reader and a TalkBack user get different detail.** The number stays visible and kept with the record (SPEC 0240); only the speech drops it.
- **An ellipsis can hide the lux on a narrow phone.** The verdict comes first in the value, so a cut value still shows it.
- **CI time.** The Kotlin step reuses the Gradle daemon and the compiled release sources of the APK build before it; its added time is measured on the pull request.
