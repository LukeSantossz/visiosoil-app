# SPEC: feat(onboarding): match the onboarding to the redesign mocks

## Problem

The Developer asked on 2026-10-26 that every screen follow the redesign v11 mocks "fielmente e estritamente" ("faithfully and strictly"). The onboarding (SPEC 0199) differs from PNG 02 to 07:

- **Header.**
  - The app draws "Passo N de 4" as a 16 sp title with "Pular" at the top right, above the step bars.
  - The mocks draw no header. The step bars sit under the illustration, with "Passo N de 4" at 12 sp under them.
- **Illustration.**
  - The app centres a 160 dp tinted disc holding a Material icon.
  - The mocks draw a 420 dp panel from the top of the screen, behind the status bar. It is `surfaceContainer` crossed by contour lines, with line art for each step: a phone and a cloud; a framed sample with a check; the texture triangle; a camera; and a cloud with a check once linked.
- **Text.**
  - The app centres a 22 sp headline over 16 sp body text at 1.6 line height.
  - The mocks set the headline at 28/36 weight 650 and the body at 16/24 in `onSurfaceVariant`, both left-aligned, 24 dp from the edges.
- **Actions.**
  - The app's actions follow the text.
  - The mocks pin two 48 dp actions 24 dp from the bottom: Google over an outlined "Agora não"; "Continuar" over a text "Pular"; and "Permitir câmera" over a text "Agora não".
- **Linked account.**
  - The app shows Perfil's account card in the text.
  - PNG 04 shows a bordered row above "Continuar", with a 40 dp initials avatar, the name and e-mail, and a Lucide `cloudCheck`.

## Design Decision

Measured on the 2× PNGs, 2 px to the dp, with a 44 dp status bar.

- **Panel.**
  - It runs from the top of the screen to 420 dp on the mock's phone: 376 dp under the safe area, plus the safe area.
  - Fill: `surfaceContainer`. In high contrast the art's fill is the solid `primaryContainer` under `onPrimaryContainer`, as the discs it replaces were (SPEC 0139).
  - Contour lines: about twenty irregular closed rings around the illustration, 1 dp in `primaryText` at 17 % (the PNG's #D0DBCF), with a few 2 dp dots at the same tint.
  - Modo Sol draws the panel white, without contours, under a 2 dp black rule, as §3.2 asks.
- **Line art.** One painter draws every step on a 200 × 180 dp canvas whose top left is 100 dp left of the panel's centre and 76 dp under the safe area. Each shape keeps the coordinates measured on its PNG, to a quarter of a dp:
  - fills in `primaryContainer` at 50 % (the PNG's #DDECDE), and the sample square of PNG 05 at 70 % (#D6EBDB);
  - 2 dp strokes in `primaryText`, and 1.5 dp dashes, 3 dp long every 7.5 dp;
  - the clouds of PNG 02 and 04 as one outline: three lobes over a flat base;
  - the camera's body and hump as one outline, its outer ring 1.5 dp in `textTertiary`;
  - the dots at the sizes the PNGs give them, from 1.75 to 4.25 dp;
  - the check badge, a 16 dp circle in `primary` with a 2.5 dp white check.
  - The triangle step reuses the static `TextureTriangle`, 146/170 of 300 dp wide, so its outline spans 146 dp under its apex at 15.75 dp. Its medium region is filled through `SoilTextureColors.exampleClass`, the model's label "Media": the earlier "Média" matched no region and left the triangle empty.
  - The triangle's class is filled at 85 % `primary` under a 2 dp `primary` edge, as PNG 06 and PNG 14 draw it. Its labels use Inter's two-storey "a", and the apex label sits 3 units lower.
- **Under the panel**, at 24 dp margins:
  - the four 4 dp step bars, 6 dp apart, 24 dp below the panel, in `primary` up to the current step and `surfaceContainerHigh` after it;
  - 16 dp lower, "Passo N de 4" at 12 sp in `textTertiary`;
  - 4 dp lower, the headline in `headlineMedium` (28/36, weight 650, −0.025 em);
  - 8 dp lower, the body at 16/24 in `onSurfaceVariant`;
  - step 4's list 16 dp lower, each row a 20 dp Lucide icon in `primaryText`, then 12 dp, then the text at 14/20 in `onSurfaceVariant`, with a 14 sp weight 600 title where it has one.
- **Actions.**
  - Pinned to the bottom with 24 dp margins and 24 dp below them; the content above scrolls to 8 dp above the first, which leaves step 4's list whole, as PNG 07 draws it.
  - Elevated buttons are flat across the app, as every mock draws them.
  - The first is 48 dp tall; a second follows 8 dp lower, also 48 dp.
    - Step 1: the Google button, then an outlined "Agora não" that moves to step 2, in `onSurface` at 17 sp weight 500 on a 1 dp `outline` rule, as the Google label is set.
    - Steps 2 and 3: "Continuar", then a text "Pular" that ends the onboarding, as the top "Pular" did.
    - Step 4: "Permitir câmera", then a text "Agora não".
  - The top "Pular" leaves.
- **Linked (PNG 04).**
  - The panel shows the cloud with a check.
  - The title is "Conta vinculada"; the body is unchanged.
  - 16 dp above "Continuar" sits a row on `surface` with a 1 dp `outlineVariant` border, radius 12 and 12 dp padding. It holds a 40 dp `primaryContainer` avatar with the initials at 14 sp weight 600 in `primaryText`, then the name at 16 sp weight 600 over the e-mail at 14 sp, and a 20 dp Lucide `cloudCheck` in `onSurface` at the end.
- **Step 2 is its sentence alone**, as PNG 05 draws it. The Developer asked on 2026-10-26 for "100% de fidelidade ao mock" ("100% fidelity to the mock"). The A4-sheet protocol the reader depends on (ADR 0017) is still taught before the first photograph, by the capture guide SPEC 0142 shows before the first camera launch.

## Alternatives Considered

- **Keep the protocol list on step 2** (SPEC 0104). Dropped at the Developer's request for full fidelity. The capture guide already shows the same three steps from the same source (`capture_protocol.dart`) before the first camera launch, so no photograph is taken without them.
- **Draw the illustrations from Lucide icons.** Rejected: the mocks' line art (phone with a dashed link to a cloud, a framed sample) has no Lucide equivalent, and composed icons would not match their proportions.

## Scope

- Includes:
  - `OnboardingScreen`, its steps and the linked state;
  - the new `OnboardingPanel` and line-art painters;
  - the capture protocol's icons, which move to Lucide (`fileText`, `circleDashed`, `camera`) for the capture guide;
  - `TextureTriangle`'s class fill and label style, which the result screens share;
  - the flat elevated button in `AppTheme`.
- Does NOT include:
  - The boot (PNG 01), which has its own change.
  - What a step does: the sign-in, the permission request and the completion keep their behaviour and tests (SPEC 0199).

## Acceptance Criteria

- `panel_matches_the_mock`:
  - on a 390 × 844 surface with a 44 dp top inset, the panel spans 0 to 420 dp;
  - it is `surfaceContainer`, with contour lines outside Modo Sol.
- `step_text_is_left_aligned`:
  - the headline is `headlineMedium` and starts 24 dp from the edge;
  - "Passo 1 de 4" sits under the step bars;
  - no "Pular" sits above the bars.
- `actions_are_pinned_to_the_bottom`:
  - on step 2, "Continuar" ends 24 dp above the bottom inset, and "Pular" sits under it;
  - on step 1, "Agora não" is an `OutlinedButton`.
- `linked_row_matches_the_mock`: once linked, a bordered row shows the initials, the name, the e-mail and `LucideIcons.cloudCheck`, above "Continuar".
- `photo_step_has_no_protocol_list` and `photo_step_is_the_sentence_alone`: step 2 shows no `captureProtocolSteps` title or sentence.
- `class_step_highlights_the_class`: the triangle highlights "Media" and is 146/170 of 300 dp wide.
- `camera_step_list_is_not_cut`: step 4's content ends 8 dp above "Permitir câmera".
- `linked_row_matches_the_mock` also checks the 16 dp gap above "Continuar" and the 20 dp `cloudCheck`.
- Existing tests pass. They are updated only where they pinned the header, the centred layout or the disc illustrations.

## Reproducibility

Flutter 3.44.1, Dart 3.12.1. Run `flutter test`, `flutter analyze` and `mf check`.

## Risks and Assumptions

- The contour lines are generated, not traced, so they follow the mocks' density and tint rather than their exact paths.
- Sizes come from 2× PNGs and can be a sub-pixel off.
