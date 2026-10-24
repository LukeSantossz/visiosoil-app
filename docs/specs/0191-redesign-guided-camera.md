# SPEC: feat(camera): implement the v11 guided camera screen

## Problem

The guided camera lacks v11's readable quality chips, timed bad-photo warning, and accessible shutter feedback in light, dark, and Sun themes.

## Design Decision

Retain the existing camera lifecycle, A4 protocol guides, live reader, and automatic capture, and compose the v11 presentation around them. Show three non-interactive live-region chips for light, focus, and distance/framing; use preview luminance and Laplacian variance with the existing provisional quality thresholds for light and focus, and the existing sheet alignment for distance. Never label image luminance as lux or infer centimetres without calibrated optics. A blocked tap shakes for 300 ms, highlights failed chips and shows a composed amber warning for 3.8 seconds; a ready capture scales to .86, flashes white at 55% outside Sun mode, and plays the medium haptic.

## Alternatives Considered

- Replace the sheet guides with the mock's square: rejected because the existing classifier requires the whole A4 reference and its soil target.
- Copy the mock's lux and centimetres: rejected because the camera does not supply those calibrated measurements.
- Add gallery import and decorative camera controls: rejected because capture is camera-only and controls must have real behavior.

## Scope

- Includes: guided camera presentation, preview quality readings, chip and warning widgets, shutter feedback, permission title, portrait locking and restoration, and structural widget tests.
- Does NOT include: design §11 features, gallery import, classifier changes, quality-threshold calibration, global orientation policy, shared component redesign, or other screens.

## Acceptance Criteria

- Light and focus chip values require two consecutive matching quality readings; capture gates keep using raw quality, and the back action is labelled “Voltar”.
- Each theme renders light, focus, and distance chips in failed, adjusting, and ready states, with live-region semantics and no tap actions.
- Blocked taps take no photograph, play two heavy impacts, shake for 300 ms unless motion is reduced, and show a failure-specific warning and amber chip outlines for 3.8 seconds; another tap restarts the deadline.
- Ready captures play medium impact, scale the shutter to .86 and flash at 55%; Sun and reduced-motion modes omit the flash, and reduced motion omits shake and scale.
- The existing reader-unavailable manual fallback remains available; unknown readings are visibly adjusting rather than fabricated successes.
- Camera initialization, shot errors, denial, restricted permission, and close remain recoverable with existing lifecycle guarantees.
- Portrait is requested before opening on phones and tablets and restored after release on exit.
- Small screens, tablets, and 200% text scale render without overflow; no simulation or haptic labels appear.

## Reproducibility

```sh
PATH=$HOME/flutter/bin:$PATH dart run build_runner build --delete-conflicting-outputs
PATH=$HOME/flutter/bin:$PATH flutter analyze
PATH=$HOME/flutter/bin:$PATH flutter test
```

Flutter 3.44.1 / Dart 3.12.1. Structural tests use fake camera, reader, sensor, and platform channels; no camera hardware or pixel goldens are required.

## Risks and Assumptions

- Preview quality thresholds are provisional engineering values from the existing quality criteria, not calibrated field measurements.
- A4 framing remains the distance signal; physical camera distance and lux are unavailable.
- The existing manual fallback when the reader is unavailable remains necessary to avoid trapping the user behind a failed checker.
- Native operating systems can constrain portrait requests on large displays; device validation remains necessary.
