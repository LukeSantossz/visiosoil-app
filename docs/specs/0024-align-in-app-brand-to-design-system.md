# SPEC: feat(brand): align the in-app mark and copy to the design system

## Problem

The app renders `Icons.layers` as its logo (splash and home hero) instead of the
official VisioSoil brand mark, and three UI strings use Title Case where the
design system mandates sentence case.

## Design Decision

Add a dependency-free `VisioSoilLogo` widget that paints the official mark with a
`CustomPainter` translated one-to-one from the design system's canonical
`assets/logo-mark.svg` (a 48×48 geometry: a lens ring, three decreasing grain
dots, and a handle line), color-parameterized so it adapts to any background like
the SVG's `currentColor`. Replace the two `Icons.layers` usages (splash, hero)
with it. Correct the three sentence-case violations. Remove the two color tokens
the design system's June-2026 slimming dropped and that the app already leaves
unused (`success`, `surfaceDim`).

## Alternatives Considered

- **Render the mark via `flutter_svg` from a bundled asset:** rejected — the mark
  is five primitives (one stroked circle, three filled circles, one line), so a
  `CustomPainter` matches it exactly without a new runtime dependency or an
  asset-loading path, and keeps `currentColor` as a simple `color` parameter.
- **Switch the icon system to Material Symbols Rounded to match the design
  system's specimen cards:** rejected — the design system explicitly flags
  Rounded as its *web substitute* for the app's built-in `Icons.*`; the app's
  Material Icons are the source of truth, so there is nothing to change.
- **Change the home primary-action CTA from its dark surface to the green-glow
  treatment:** rejected here — the dark CTA is a deliberate, polished choice and
  the available design-system text does not contradict it; kept out of scope
  pending the design system's own home mockup.

## Scope

- Includes:
  - `VisioSoilLogo` widget (`CustomPainter`) rendering the official mark, with a
    `color` and `size` parameter and a "VisioSoil" semantics label.
  - Replace `Icons.layers` with `VisioSoilLogo` in `splash_screen.dart` (white,
    on the green gradient) and `hero_section.dart` (white, on the green square).
  - Sentence-case corrections applied at every occurrence: `Nova Captura`→
    `Nova captura` (capture app bar, camera-denied app bar, history empty-state
    button), `Salvar Registro`→`Salvar registro` (capture save action),
    `Abrir Configurações`→`Abrir configurações` (permission-denied action).
  - Remove the unused `AppColors.success` and `AppColors.surfaceDim` constants.
- Does NOT include:
  - The app launcher icon / "capa" (a separate change, spec 0025).
  - Switching the icon system to Material Symbols Rounded.
  - Changing the home CTA treatment or any color/type/spacing token values.
  - Any onboarding or other copy change beyond the three strings above.
  - Versioning the design-system export (kept local, reference only).

## Acceptance Criteria

- logo_widget_renders_with_semantics: pumping `VisioSoilLogo` builds without
  error and exposes the "VisioSoil" semantics label.
- hero_uses_the_brand_mark: `HeroSection` renders a `VisioSoilLogo` and no
  `Icon(Icons.layers)`.
- corrected_copy_present_and_titlecase_absent: under `lib/`, every occurrence
  uses the sentence-case string and no source retains the Title-Case form (the
  replacement examples quoted in this spec and its tests are excluded).
- removed_tokens_absent: `AppColors` no longer declares `success` or `surfaceDim`.
- analyze_clean: `flutter analyze` reports no new issues.
- tests_green: `flutter test` passes.

Verification note: the `splash_screen.dart` logo swap is verified by code
inspection (Splash is untestable by construction — static `PermissionService`
channels + timed `Future.delayed`), per the accepted precedent (specs 0007/0009,
issues #133/#137). `AppColors.success`/`surfaceDim` removal is a pure deletion of
unused constants, verified by a clean `flutter analyze` and the passing suite.

## Reproducibility

- Toolchain: Flutter 3.44.1 / Dart 3.12.1 (pinned per `ci.yml`).
- Mark geometry source: the design system's `assets/logo-mark.svg`
  (viewBox 0 0 48 48): ring `cx20 cy20 r13 stroke 3.2`; grains
  `cx16.5 cy18 r3`, `cx23.5 cy19.5 r2.1`, `cx19.5 cy24.5 r1.4` (filled);
  handle `29.5,29.5 → 39,39 stroke 3.4 round`.
- Run: `flutter analyze && flutter test`.

## Risks and Assumptions

- Assumption: `AppColors.success` and `AppColors.surfaceDim` are unused across
  `lib/` and `test/`; verified by search before removal. Invalidated only if a
  later reference is added before this lands.
- Assumption: the `CustomPainter` scaled from the 48-unit viewBox reproduces the
  mark faithfully at the app's small sizes (19–64 px). Invalidated if stroke
  widths read too heavy at 19 px; mitigated by scaling stroke widths with size.
