# SPEC: feat(home): implement the v11 home dashboard

## Problem

The Home screen still uses the previous greeting, large green capture card and single latest-analysis layout instead of the approved v11 dashboard.

## Design Decision

Render the compact capture control, weekly summary and a shared card containing up to five newest local records using the v11 components and theme tokens. Derive the weekly count, collected class count and latest confidence from the existing records stream, without changing persistence or introducing sample data. Collection shows the number of observed classes without the mock's fictional twelve-class denominator, since the released model does not expose twelve classes. Extend AnalysisTile with an optional Home presentation to expose sync pills and confidence metadata while preserving its existing default presentation.

## Alternatives Considered

- Keep the previous aggregate labels and latest-only card: rejected because neither matches the approved dashboard or its recent-record states.
- Copy the mock's twelve-class denominator and sample values: rejected because these are not supported by the released model or local records.
- Duplicate the shared analysis row inside Home: rejected because the base-components PR explicitly supplies the reusable row.

## Scope

- Includes: Home screen, capture control, stats, inline error, a minimal optional AnalysisTile presentation, and structural widget tests for light, dark, Sun, empty, loading, error, offline, navigation and semantics.
- Does NOT include: redesigning the navigation shell or other screens, persistence changes, dependencies, mock identities or data, sample fractions, alternative classes, field registration, or any other feature in design section 11.

## Acceptance Criteria

- All three themes render the capture control, weekly summary and recent section using their palette and density.
- Empty data shows zero counts and the approved capture guidance.
- Loading renders three stat skeletons and three row skeletons; shimmer stops under either reduced-motion setting.
- Stream failure shows the approved inline error and retry; capture remains available and retry resubscribes.
- Recent records are sorted newest first and capped at five, including unclassified records; online rows expose sent, pending or error status and offline rows expose only pending pills.
- Weekly count excludes records before local Monday; collection counts distinct classified labels; confidence belongs to the newest record and missing confidence displays an em dash.
- Capture opens capture, each row opens its record, and Ver todas selects History.
- Controls and records expose labelled semantics, meet minimum tap sizes and remain usable at 200 percent text scale.

## Reproducibility

Use Flutter 3.44.1 / Dart 3.12.1 with `PATH=$HOME/flutter/bin:$PATH`:

```sh
dart run build_runner build --delete-conflicting-outputs
flutter analyze
flutter test
```

## Risks and Assumptions

- The existing records stream is the source for local records; connectivity affects presentation only.
- Collection means distinct classified labels already observed locally; a future model-aware collection screen may supply a denominator.
- Structural tests avoid platform-dependent pixel goldens; physical-device visual review remains useful.
- The existing navigation shell remains owned by its separate screen work.

## Reference

Design: `/workspace/visiosoil-mocks/spec-dev/SPEC.md`, section 3.3 and PNGs 08, 09, 25 and 27; prototype `/workspace/visiosoil-mocks/app-completo-v11/index.html`.
