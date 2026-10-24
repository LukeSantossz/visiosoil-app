# SPEC: feat(capture): add the v11 processing triangle

## Problem

The capture flow shows a loading chip instead of v11's accessible processing surface and illustrative texture triangle.

## Design Decision

Replace the capture flow's running-classification body with a processing view titled Resultado, using existing theme, density, spacing, motion and haptic tokens. Add a feature-owned TextureTriangle with deterministic, precomputed geometry and 26 particles, a single 2.4-second controller and a repaint boundary; paint reuses paths and paints rather than allocating objects per frame. Highlight only a real returned class, using approximate regions for the released model's broad texture classes rather than the mock's fictional result. After the real result arrives, finish the illustrative settlement before exposing the existing result controls; Sun and reduced motion show the static state immediately.

## Alternatives Considered

- Keep the loading chip: rejected because it omits the requested diagram, explanation and processing hierarchy.
- Render particles as widgets: rejected because layout and widget allocation on every frame are unnecessary for 26 decorative grains.
- Display the mock's Franco-argilosa result while waiting: rejected because it fabricates model output.

## Scope

- Includes: a feature-owned processing view and triangle, running-state wiring in CaptureScreen, centralized processing copy, widget and flow tests, light/dark/Sun and accessibility coverage.
- Does NOT include: changes to shared base components, result redesign, classifier algorithms, fractions, alternative classes, field registration, mock badges or haptic indicators, or a second inference timeout.

## Acceptance Criteria

- Processing displays the requested title, supporting text, estimate, thin indeterminate progress and fixed illustrative disclaimer in all three themes.
- The triangle supports empty, falling, settling and highlighted states, and exposes one descriptive semantics label without decorative descendants.
- A real class is the only source of a highlighted label; inference failure returns to the existing failure surface, including the existing 15-second timeout cause.
- Particle positions are deterministic and contained in the selected approximate region, with 26 grains, one controller and no per-frame geometry generation.
- Settlement emits one confirm haptic and callback; Sun, system-disabled animations and the application reduced-motion preference omit particles and pulse while still completing settlement.
- Processing remains readable without overflow at 320 dp and 200% text scale, and meets text contrast guidelines in light, dark and Sun.
- Disposing or superseding a capture cannot apply a late settlement to another capture.

## Reproducibility

Flutter 3.44.1 / Dart 3.12.1. Particle seed: 193.

```sh
export PATH="$HOME/flutter/bin:$PATH"
dart run build_runner build --delete-conflicting-outputs
flutter analyze
flutter test
mf check
```

## Risks and Assumptions

- The diagram is illustrative: the released model returns broad classes, not measured sand/silt/clay coordinates. The disclaimer must always remain visible.
- The existing inference service owns the 15-second deadline and isolate teardown; the screen preserves that boundary.
- Repaint isolation and allocation-free frame code aim at 60 fps; actual entry-level hardware profile measurements remain necessary and cannot be inferred from widget tests.
- The user's supplied screen design and explicit implementation request authorize this specification's scope.

## Reference

Redesign v11 SPEC §3.5, §6.3 and PNGs 13, 29–31 and 38 in `/workspace/visiosoil-mocks/spec-dev/`.
