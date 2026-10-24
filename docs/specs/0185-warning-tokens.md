# SPEC: fix(theme): apply warning roles with accessible contrast

## Problem

Warning text inherits the light amber tint in dark and Sol palettes, and the medium confidence fill fails the non-text contrast threshold against its track (QA v11 items 2, 3 and 7).

## Design Decision

Apply the distinct warning roles approved in design SPEC §1.1, §8 and §16 while preserving the Designer's published §15/§16. Container text uses `onWarningContainer`: light #6D4C1D on #FBEBD2, dark #FFDDB6 on #604012, and Sol #4A3417 on white. Surface text uses `warningText`: light #9E6B2C, dark #FEB968 and Sol #4A3417. Medium confidence fills use `warningText` against `surfaceContainerHigh`; the icon token remains unchanged.

## Alternatives Considered

- Use `warning` for container text. Rejected because the light pair fails AA.
- Darken the confidence track. Rejected because the existing text tint provides sufficient contrast without changing other confidence levels or surface roles.

## Scope

- Includes: palette warning text roles, medium confidence fill, WCAG contrast regression tests, affected palette goldens, and recording the publication of design SPEC §15/§16.
- Does NOT include: camera redesign, other QA items, typography changes, theme selection changes, or changes to the Designer's published sections.

## Acceptance Criteria

- Warning container text meets 4.5:1 in light and dark and 7:1 in Sol.
- Warning surface text meets 4.5:1 in light and dark and 7:1 in Sol.
- Rendered medium confidence fill meets 3:1 against its track in every palette.
- Existing caution notices retain the container foreground role, and affected palette goldens pass.

## Reproducibility

```sh
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter analyze
flutter test
```

Flutter 3.44.1 / Dart 3.12.1. Update only affected golden files with a targeted `flutter test --update-goldens` invocation.

## Risks and Assumptions

- Assumption: existing caution notices already use `onWarningContainer`; the blocked capture overlay is an error notice and retains its error roles.
- Contrast tests cover the fixed palette endpoints; animated intermediate themes are outside this change.
