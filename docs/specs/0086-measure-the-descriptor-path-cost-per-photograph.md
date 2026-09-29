# SPEC: test(inference): measure the descriptor path's cost per photograph on the emulator

## Problem

Nobody knows whether one classification fits `InferenceService`'s 15 s timeout
on an Android device, because the descriptor path (SPEC 0083) has never run
outside a desktop JIT, where one patch's 26 descriptors take about 40 ms
(SPEC 0077) and a photograph can need 25 patches plus a full-resolution decode
in pure Dart (#215, implementation map A7).

## Scope

- Includes:
  - `integration_test/descriptor_path_cost_test.dart`, a harness run with
    `flutter drive --profile` on the `android_emulator` AVD (x86_64, API 36,
    4 cores, 4 GB RAM), the reference the Developer accepted in A7. Profile
    mode is AOT-compiled, as release is. Debug mode's JIT would overstate every
    number.
  - The photograph is generated inside the harness: a 3024 × 4032 JPEG of
    uniform noise. Noise is the worst case for a JPEG decoder, so the decode
    figure is an upper bound for a real photograph at that resolution, and the
    harness needs no git-ignored archive image. The measurement is a fixed
    scale of 90 mm over 2 700 px, a disc centred in the frame, which is a typical
    12 MP dish photograph. The harness records how many patches the grid cuts.
  - Each phase is timed separately over five runs: decode, orientation bake,
    frame conversion, `canonicalPatches`, `describePatch` for every patch,
    `DescriptorContract.distribution`, and the end-to-end
    `InferenceService.classify`. The last includes the isolate spawn and the
    contract copy, which is what the user waits for. The harness reports the
    timings as JSON through `IntegrationTestWidgetsFlutterBinding.reportData`.
  - `test_driver/integration_test.dart`, the standard driver, and
    `integration_test` from the Flutter SDK as a dev dependency.
  - `docs/ml/descriptor-path-cost.md`: the medians and maxima, the patch count,
    the emulator and host, the Flutter version, the mode, and the command. It
    gives the verdict against the 15 s timeout, with A7's caveat that an
    emulator can be faster or slower than a phone.
  - The map's A7 entry, with the result. #215 closes after merge.
- Does NOT include:
  - Any change to production code, including the timeout. Whether the numbers
    call for an optimisation or a longer timeout is a decision for after the
    measurement, taken against its record.
  - Running the harness in CI. It is a measurement, not a gate, and CI's
    emulator boots only for `smoke`.
  - A physical device, which A7 records as unavailable.
  - The A4-sheet reader's cost, which does not exist yet. The fixed measurement
    stands in for it.

## Acceptance Criteria

- `the_harness_times_every_phase`: one `flutter drive --profile` run reports
  five timings for each of decode, orientation, frame, grid, describe, score and
  classify, plus the patch count, and every `classify` run returns an `ok`
  report.
- `the_cost_is_recorded`: `docs/ml/descriptor-path-cost.md` records the medians
  and maxima per phase, the patch count, the AVD's configuration, the host CPU,
  the Flutter version and the mode. It names the command that reproduces them,
  and states whether the end-to-end median and maximum fit inside 15 s.
- `flutter analyze` and `flutter test` stay green: the harness lives outside
  `test/`, so the suite does not run it.
