# SPEC: fix(settings): hide sync rows without a backend

## Problem

Settings shows "Backup na conta" and "Sincronizar só no Wi-Fi" even though no remote sync backend is wired, so both controls advertise unavailable behavior.

## Design Decision

When `syncBackendWired` is false, Settings omits the two sync-only rows from the data-and-sync group. The existing constant remains the source of truth: the future backend-wiring spec sets it to true and makes the rows available again without a second Settings change.

## Alternatives Considered

- Keep the rows disabled with explanatory copy. Rejected because unavailable controls still imply that account backup or Wi-Fi-only synchronization exists.
- Remove the entire data-and-sync section. Rejected because export and local-data deletion remain useful device-local actions.

## Scope

- Includes:
  - `lib/core/features/settings/settings_screen.dart`, gating only the Backup and Wi-Fi-only sync rows on `syncBackendWired`;
  - `test/features/settings/settings_screen_test.dart`, proving those rows are absent while the backend flag is false.
- Does NOT include:
  - changing `syncBackendWired`, `SyncEngine`, or any sync backend;
  - changing Exportar análises, Limpar dados do aparelho, row order outside the two omitted rows, or PNG 23.

## Acceptance Criteria

- `settings_hides_sync_rows_without_a_backend`: Settings with `syncBackendWired == false` does not show "Backup na conta" or "Sincronizar só no Wi-Fi".
- `settings_keeps_local_data_actions_without_a_backend`: the same group still shows "Exportar análises" and "Limpar dados do aparelho".

## Reproducibility

Flutter 3.44.1, Dart 3.12.1. Run `flutter test test/features/settings/settings_screen_test.dart`, then `flutter test`, `flutter analyze`, and `mf check`.

## Risks and Assumptions

- **Future wiring.** The backend-wiring spec must set `syncBackendWired` to true; otherwise the rows remain hidden, as intended for an unwired backend.
- **Mock departure.** PNG 23 draws the two disabled rows. The Developer approved hiding them because they promise unavailable behavior.
