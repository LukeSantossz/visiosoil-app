# SPEC: fix(profile): hide the sync action while no backend is wired

## Problem

A signed-in Perfil offers "Sincronizar", and the button cannot sync.

- **What it does.** Tapping it shows a snackbar: "A sincronização com a conta ainda não está disponível. As análises seguem neste aparelho." (SPEC 0204). No `RemoteSyncBackend` exists and `SyncEngine` is not in the provider graph, so there is nothing for it to start.
- **What it says.** A button that only explains it does nothing reads as broken. The row beside it, "Dados só neste aparelho", already says where the data is.
- **The rest of the sync status is gone.** SPEC 0235 hides every sync status while `syncBackendWired` is false. This button is the last sync control on a main tab.
- **Decision.** The Developer chose, on 2026-10-29, to hide "Sincronizar" until a server exists, behind the same gate as SPEC 0235.

## Design Decision

**While `syncBackendWired` is false, the linked account card shows no "Sincronizar" button.**

- The rule under the header and the "Dados só neste aparelho" row stay. Only the `TextButton` is gated.
- The row keeps a minimum height of 48 dp, the height the button gave it. The card therefore keeps PNG 22's geometry, with the cloud icon's centre 36 dp above the card's bottom edge.
- The button's code stays behind the gate. The spec that wires a backend sets `syncBackendWired` to true and gives the button its real action in place of the snackbar.
- The comment above the row says why the action is hidden.

## Alternatives Considered

- **Delete the button and `AppStrings.syncNotAvailable`.** Rejected: the Developer asked for the same gate as SPEC 0235, so one constant brings the sync UI back.
- **Disable the button instead of hiding it.** Rejected: a greyed "Sincronizar" still promises a feature that does not exist, and the Developer asked for it hidden.

## Scope

- Includes:
  - `lib/core/features/profile/profile_screen.dart`;
  - `test/features/profile/profile_screen_test.dart`.
- Does NOT include:
  - Ajustes' "Backup na conta" and "Sincronizar só no Wi-Fi", which are disabled and say why;
  - the signed-out card, which offers sign-in and not sync;
  - `AppStrings.syncNotAvailable`, which stays for the gated button.

## Acceptance Criteria

- `test/features/profile/profile_screen_test.dart`:
  - `linked_card_matches_the_mock`, amended:
    - the initials, the rule and its 16 dp gap keep their expectations;
    - the card shows "Dados só neste aparelho" and no "Sincronizar";
    - the cloud icon's centre stays 36 ± 1 dp above the card's bottom edge.

## Reproducibility

Flutter 3.44.1, Dart 3.12.1. Run `flutter test test/features/profile/profile_screen_test.dart`, then `flutter test`, `flutter analyze` and `mf check`.

## Risks and Assumptions

- **The gated code is not exercised.** No test can reach the button while the constant is false. The wiring spec replaces its action anyway, and tests it then.
- **Stacked on SPEC 0235.** The gate comes from SPEC 0235's branch, so this branch merges after it.
