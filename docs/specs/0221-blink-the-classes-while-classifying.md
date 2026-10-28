# SPEC: fix(capture): blink the classes while classifying and hold the predicted one

## Problem

In the field session of 2026-10-27 the triangle on the processing view did not show that the app was working.

- **While classifying, no class is known**, so `TextureTriangle` receives no `highlightClass`.
  - Its 26 particles fall once, over the 2.4 s run, and stop.
  - A classification on the phone takes longer than that, so the triangle then sits still and bare. It reads as a frozen screen.
- **When the result arrives, the run restarts.** The particles fall again, now in the class's colour, and only at 2.1 s does the region fill.
  - The result is shown 2.1 s after it is known.

The Developer asked for the regions to blink in turn while the photograph is processed, with no particles, and for only the predicted class to stay highlighted at the end.

## Design Decision

**While no class is known, the four model classes blink in turn. When one is known, it fills and stays.**

- **Waiting.** In processing mode with no `highlightClass`, the triangle loops for as long as it waits.
  - Each cycle lights the four model classes' regions in texture order, from the base up: Arenosa, Média, Argilosa, Muito argilosa.
  - Each region has a 600 ms quarter of a 2.4 s cycle. Its fill's opacity follows `sin(π·t)` over its quarter, so it rises from 0 to the region's 85 % fill and back to 0, with the region's edge at the same opacity.
  - The Silte region never blinks. It is not a class the model emits (ADR 0016), and lighting it would suggest it was considered.
- **No particles.** `_Particle`, its 26 grains and their colour ramp are removed.
- **The result.** When `highlightClass` arrives, the loop stops at once, wherever it is.
  - The predicted region fills, with today's 4 % pulse over 360 ms, and stays filled.
  - The haptic and the settled semantics fire as the fill starts, and `onSettled` fires when the pulse ends.
  - The result therefore shows 360 ms after it is known, instead of 2.1 s.
- **Static triangles do not change.** Static mode, Modo Sol, the app's reduced-motion preference and the system's disabled animations draw no blinking.
  - The bare triangle while waiting, and the predicted region filled at once, settling on the next frame as today.
  - Details' overview and onboarding use static mode, so they are untouched.
- **Only the prediction is drawn.** The triangle has no input for the true class (SPEC 0220). Capture passes the classification's `textureClass`, and nothing else reaches it.

## Alternatives Considered

- **Keep the particles and loop them.** Rejected by the Developer, who asked for no particles.
- **Blink all five regions.** Rejected. Silte is not a class the model emits.
- **Finish the current cycle before filling the result.** Rejected. It delays a known result by up to 2.4 s, for no information.
- **Blink in a random order.** Rejected. A fixed order reads as a scan, and a random one can repeat a region and look like a hint.

## Scope

- Includes:
  - `TextureTriangle`'s processing mode: the waiting loop, the particles' removal and the shorter settlement;
  - its tests in `processing_view_test.dart`.
- Does NOT include:
  - the static triangle, details' overview and onboarding;
  - the processing view's text and phases;
  - the delay when "Corrigir" opens.

## Acceptance Criteria

- `waiting_triangle_blinks_the_model_classes`: in processing mode with no class, under animated motion, the painter lights Arenosa at 300 ms, Média at 900 ms, Argilosa at 1500 ms and Muito argilosa at 2100 ms, and Arenosa again at 2700 ms.
- `waiting_triangle_never_lights_silt`: across a full cycle, the Silte region is never filled.
- `waiting_triangle_draws_no_particles`: across a full cycle, nothing is drawn outside the triangle's regions, edges and labels.
- `result_holds_the_predicted_class`: once a class is given mid-cycle, the blinking stops, only that class's region is filled, and it is still the only one filled 5 s later.
- `result_settles_after_the_pulse`: the haptic fires as the class is given, and `onSettled` fires once, 360 ms later, and not again.
- `static_triangle_never_blinks`: under reduced motion, in Modo Sol and in static mode, no region is filled while no class is given, and no frame is scheduled.
- Existing triangle tests pass. Those that name particles are rewritten to the criteria above.

## Reproducibility

Flutter 3.44.1, Dart 3.12.1. Run `flutter test`, `flutter analyze` and `mf check`.

## Risks and Assumptions

- **A loop that never ends keeps scheduling frames** while classifying. It stops when the view leaves the tree or a class arrives, and the processing view is only shown while classifying.
- **The faster settlement shortens what capture waits for** before it opens details (SPEC 0219): 360 ms plus `AppMotion.slow`, instead of 2.4 s.
- **A blink can be read as a guess.** The disclaimer under the triangle already says it does not plot the sample's fractions, and the order is fixed and covers all four classes.
