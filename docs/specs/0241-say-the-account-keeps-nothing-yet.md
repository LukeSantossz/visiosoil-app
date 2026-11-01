# SPEC: fix(account): say the account keeps nothing yet

## Problem

Four lines of copy promise that a Google account keeps or syncs the analyses, and nothing does.

- **What they say.**
  - Perfil's signed-out card says "Vincule uma conta para salvar e sincronizar suas análises. Se trocar ou perder o aparelho, elas não se perdem."
  - Onboarding's account step is titled "Vincular conta para salvar e sincronizar suas análises". Its description reads "Guardamos suas análises, fotos e coleção na sua conta Google. Sem conta, tudo fica só neste aparelho."
  - Onboarding's linked step says "Suas análises vão sincronizar sozinhas quando houver internet."
  - Onboarding's camera step ends with "as análises sincronizam quando houver sinal."
- **What is true.** No `RemoteSyncBackend` exists and `SyncEngine` is not in the provider graph, so linking an account copies nothing. An agronomist who links, loses the phone and trusts the card loses every analysis.
- **The rest of the sync UI is already gated.** SPEC 0235 hides the sync status and SPEC 0236 hides "Sincronizar" while `syncBackendWired` is false. These four lines are the promise left behind.
- **Decision.** The Developer approved, on 2026-10-31, the visual review item that names this copy as a false promise, and then this spec with the copy below.

## Design Decision

**While `syncBackendWired` is false, each of the four lines says the analyses stay on the device.**

| Where | Today | While `syncBackendWired` is false |
|---|---|---|
| Perfil, signed-out card | Vincule uma conta para salvar e sincronizar suas análises. Se trocar ou perder o aparelho, elas não se perdem. | Suas análises ficam só neste aparelho. A cópia na conta Google ainda não está disponível. |
| Onboarding, account step title | Vincular conta para salvar e sincronizar suas análises | Vincular sua conta Google |
| Onboarding, account step description | Guardamos suas análises, fotos e coleção na sua conta Google. Sem conta, tudo fica só neste aparelho. | Por enquanto, suas análises e fotos ficam só neste aparelho. A cópia na conta ainda não está disponível. |
| Onboarding, linked step description | Suas análises vão sincronizar sozinhas quando houver internet. | Por enquanto, suas análises ficam só neste aparelho. |
| Onboarding, camera step description | Usamos a câmera para fotografar o solo. Funciona sem internet; as análises sincronizam quando houver sinal. | Usamos a câmera para fotografar o solo. Funciona sem internet. |

- Each line picks its text from `syncBackendWired`, so the spec that wires a backend gets today's copy back by setting the constant to true.
- Nothing else on the steps or the card changes: the art, the buttons, the offline line and the device count stay.

## Alternatives Considered

- **Remove the account step from onboarding.** Rejected: signing in works and is kept for the backend to come; the step only needs to stop promising.
- **Replace the copy without the gate.** Rejected: SPEC 0235 and SPEC 0236 gate the sync UI on one constant, and these lines belong with them.

## Scope

- Includes:
  - `lib/core/features/profile/profile_screen.dart`;
  - `lib/core/features/onboarding/onboarding_screen.dart`;
  - `test/features/profile/profile_screen_test.dart`;
  - `test/features/onboarding/onboarding_mock_test.dart`;
  - `test/features/narrow_large_text_test.dart`, for the account step's new title.
- Does NOT include:
  - Ajustes' "Backup na conta" and "Sincronizar só no Wi-Fi" rows, which SPEC 0236 also left out;
  - `AppStrings.syncNotAvailable`, behind SPEC 0236's gate;
  - the semantics label "pendente de sincronização", behind SPEC 0235's gate.

## Acceptance Criteria

- `test/features/profile/profile_screen_test.dart`:
  - `signed_out_card_says_the_analyses_stay_on_the_device`: the signed-out card shows "Suas análises ficam só neste aparelho. A cópia na conta Google ainda não está disponível." and no text containing "sincroniz".
- `test/features/onboarding/onboarding_mock_test.dart`:
  - `account_step_promises_no_copy`: the account step shows "Vincular sua conta Google" and the new description, and no text containing "sincroniz" or "Guardamos".
  - `linked_step_promises_no_sync`: with an account, the step shows "Por enquanto, suas análises ficam só neste aparelho."
  - `camera_step_promises_no_sync`: the camera step's description is "Usamos a câmera para fotografar o solo. Funciona sem internet."
- `test/features/narrow_large_text_test.dart`: the account step with the new title fits at 320 dp wide and 2.0 text scale, as the old title did.

## Reproducibility

Flutter 3.44.1, Dart 3.12.1. Run `flutter test test/features/profile test/features/onboarding test/features/narrow_large_text_test.dart`, then `flutter test`, `flutter analyze` and `mf check`.

## Risks and Assumptions

- **The wired copy is not exercised.** No test reaches it while the constant is false, as with SPEC 0236's button. The wiring spec tests it.
- **The mock still draws the old copy.** PNG 02 and PNG 22 show the promise. The tests pin the honest copy, and the mock is not changed here.
- **Stacked on SPEC 0236.** The gate comes from SPEC 0235's branch, so this branch merges after #462 and #463.
