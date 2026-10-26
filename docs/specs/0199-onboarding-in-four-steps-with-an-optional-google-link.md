# SPEC: feat(onboarding): onboarding in four steps with an optional Google link

## Problem

Redesign v11 §3.2 (PNGs 02 to 07) asks for an onboarding in four steps:

1. an optional Google link;
2. the photograph;
3. the estimated class;
4. the camera permission.

The onboarding today has three steps, one per point of the capture protocol (SPEC 0104). It offers no account link, although §9 asks for "Agora não" in the onboarding and the link later in Perfil. It never asks for the camera, so the first request arrives on the first capture.

## Design Decision

`OnboardingScreen` keeps its route, its `PageView`, "Pular", and `_complete()`, which marks completion and then pops or goes home. Its content becomes the four §3.2 steps.

- **Header.** "Passo N de 4" and "Pular", above four bars.
- **Step 1, account.**
  - Copy: "Vincular conta para salvar e sincronizar suas análises" and "Guardamos suas análises, fotos e coleção na sua conta Google. Sem conta, tudo fica só neste aparelho."
  - Buttons: the Google brand button (§9) and the text button "Agora não", which moves to step 2.
  - The brand button signs in through `authNotifierProvider`, as Perfil does. While it runs, the button reads "Vinculando sua conta…" with a spinner, and "Agora não" stays enabled.
  - Linked: "Conta vinculada", "Suas análises vão sincronizar sozinhas quando houver internet.", the `AccountCard`, and [Continuar]. A sign-in that lands plays `AppHaptics.linked()`.
  - A failed sign-in shows the snackbar "Não foi possível vincular. Tente de novo ou continue sem conta." and restores the buttons.
  - Offline: the brand button is disabled, with the caption "Sem conexão. Você pode vincular depois em Perfil."
  - Perfil and the onboarding share one brand button, `GoogleSignInButton`, so the §9 branding has one owner.
- **Step 2, photograph.**
  - Copy: "Fotografe a amostra de solo" and "Destorroe uma porção da camada de 0–20 cm e enquadre na moldura. O app checa luz, foco e distância antes de liberar a foto."
  - The step also lists the three points of `captureProtocolSteps`, so the onboarding still teaches the A4-sheet protocol the reader assumes (ADR 0017, SPEC 0142).
  - [Continuar].
- **Step 3, estimated class.**
  - The static `TextureTriangle` as the illustration.
  - Copy: "Veja a classe textural estimada" and "O resultado mostra a classe textural estimada pelo modelo e a confiança dela, em palavras e em percentual."
  - [Continuar].
- **Step 4, camera.**
  - Copy: "Permita o acesso à câmera" and "Usamos a câmera para fotografar o solo. Funciona sem internet; as análises sincronizam quando houver sinal."
  - Two list rows: the camera row and the optional approximate location row.
  - [Permitir câmera] requests the camera permission and then completes, whatever the answer. A denial is handled where it matters, by capture's existing denied view (SPEC 0117).
  - [Agora não] completes without asking.
  - The request is an injected `requestCameraPermission`, defaulting to `PermissionService.requestCamera`, as in `CaptureScreen`.
- **Unchanged behaviour.** Reduced motion still jumps between pages (SPEC 0120), and each page still scrolls at large text (SPEC 0121).

## Alternatives Considered

- **Drop the protocol points from the photograph step.** Rejected: the reader refuses any photograph taken another way. The onboarding is the only place a first-time user meets the protocol before the first capture.
- **Ask for the location in step 4 too.** Rejected: capture asks for it when it reads the fix, and §3.2's button names only the camera.
- **Make step 1 mandatory once online.** Rejected: §9 makes the login optional and the app works fully without an account.

## Scope

- Includes:
  - The four steps, the header and the step actions.
  - `GoogleSignInButton`, shared by Perfil and the onboarding.
  - The injected camera request.
  - Updates to the onboarding tests that pinned the three protocol pages and "Próximo"/"Começar".
- Does NOT include:
  - Splash, first-launch gating, or the capture guide.
  - Profile's layout beyond the shared button.
  - Any change to auth, sync or permissions services.
  - The §10 small-screen illustration height.

## Acceptance Criteria

- `header_counts_four_steps`: the first page reads "Passo 1 de 4" and draws four bars; after "Agora não" it reads "Passo 2 de 4".
- `account_step_links_with_google`: tapping "Continuar com o Google" signs in. The page then shows "Conta vinculada", the account's name and e-mail, and [Continuar], and plays the linked haptic.
- `account_step_offline_disables_google`: offline, the brand button is disabled and the caption reads "Sem conexão. Você pode vincular depois em Perfil.".
- `account_step_error_shows_snackbar`: a failed sign-in shows the §3.2 snackbar and the brand button again.
- `photo_step_teaches_the_sheet_protocol`: step 2 shows its title and every protocol point's title and sentence, in order.
- `class_step_shows_the_triangle`: step 3 shows "Veja a classe textural estimada" and a `TextureTriangle`.
- `camera_step_requests_then_completes`: "Permitir câmera" calls the injected request once, marks completion and leaves. "Agora não" marks completion without calling it.
- Existing onboarding and profile tests pass, updated only where they pinned the replaced pages or buttons.

## Reproducibility

Flutter 3.44.1, Dart 3.12.1. Run `flutter test`, `flutter analyze` and `mf check`.

## Risks and Assumptions

- The Developer asked for every pending v11 visual item on 2026-10-26.
- "O app checa luz, foco e distância" describes the guided camera's live checks (SPEC 0165): light and focus from `LiveQuality`, and framing from the live sheet reader. The light check is not a calibrated lux reading, and the copy claims no number.
