# SPEC: fix(history): hide the sync status while no backend is wired

## Problem

Every record in Início and Histórico reads "Pendente", and an agronomist reads that as an analysis that has not finished.

- **What the word means.** `StatusPill` and Início's status dot show a record's `syncStatus`: "Enviada", "Pendente" or "Erro" (redesign v11 §4). "Pendente" means the record has not been sent to a server.
- **Nothing can send it.** No `RemoteSyncBackend` exists and `SyncEngine` is not in the provider graph, so every record is written `pending` and stays `pending`. The word is true of every record and therefore says nothing.
- **It takes the place of what the row would show.** A pending row in Histórico shows the "Pendente" pill where a sent row shows its chevron, so a classified sample whose details show class and confidence reads, in the list, as waiting for something.
- **Two more surfaces repeat it.** Offline, Histórico's banner says "N análises aguardam envio", and a signed-in Perfil counts "0 enviadas".
- **Seen on the device.** The Developer asked on 2026-10-29 why a sample reads "Pendente" in Histórico when its details show class and confidence.

## Design Decision

**While no sync backend is wired, the app shows no sync status anywhere.**

- One constant, `syncBackendWired` in `lib/core/data/sync/sync_availability.dart`, is `false`. The spec that wires `SyncEngine` to a backend sets it to `true`, and every surface below returns as designed.
- `AnalysisTile` gains `syncWired` (default `false`). When it is `false`:
  - a Histórico row shows what a sent row shows: its chevron, or its failure icon;
  - a row outside Início and Histórico shows its confidence badge, its failure icon, or its chevron;
  - an Início row shows no status dot and no status word;
  - neither row's semantics label names a sync status;
  - a record's `syncStatus` of `error` hides nothing, so Início's metadata keeps its confidence.
- Início and Histórico pass `syncBackendWired` to the tile.
- `OfflineBanner.pendingCount` becomes nullable. Histórico passes `null` while not wired, and the banner then reads only "Tudo continua salvo neste aparelho." under "Sem conexão".
- Perfil counts every record as "só no aparelho" while not wired, signed in or not.
- The stored `syncStatus`, the `sync_queue` and the sync code are unchanged: records still enqueue, so wiring a backend later sends them.

## Alternatives Considered

- **Rename "Pendente" to "Só no aparelho".** Rejected by the Developer on 2026-10-29. It is true, but it repeats the same word on every row and still takes the confidence badge's place.
- **Wire a backend.** Out of reach: none exists, and sync is a later phase.
- **Delete the sync UI.** Rejected. Redesign v11 draws it, and it is right once a backend exists; one constant brings it back.

## Scope

- Includes:
  - `lib/core/data/sync/sync_availability.dart` (new);
  - `AnalysisTile`, `OfflineBanner`, `HistoryList`, `HomeScreen`, `ProfileScreen`;
  - their tests in `test/core/widgets/` and `test/features/`, `main_tabs_mock_test.dart` included.
- Does NOT include:
  - `SoilRecord.syncStatus`, the database, `SyncEngine`, `sync_queue` or `RemoteSyncBackend`;
  - `StatusPill` itself, its colours or its labels;
  - the details screen, which shows no sync status.

## Acceptance Criteria

- `test/core/widgets/analysis_tile_test.dart`:
  - `unwired_pending_history_row_shows_its_chevron`: a classified `pending` record in a Histórico tile without `syncWired` shows the chevron a sent row shows and no `StatusPill`.
  - `unwired_pending_tile_shows_its_confidence`: a classified `pending` record in a default tile without `syncWired` shows its `ConfidenceBadge`, no `StatusPill`, and its semantics label has no "sincronização".
  - `unwired_home_row_shows_no_sync_status`: an Início tile (`showSyncStatus: true`) of a `pending` record without `syncWired` shows no `status-dot`, no "Pendente", and its semantics label has no "sincronização".
  - `unwired_error_record_keeps_its_confidence`: an Início tile of an `error` record without `syncWired` shows its confidence percent and no "Erro".
  - The present pending, error and sent tests pass `syncWired: true` and keep their expectations.
- `test/core/widgets/offline_banner_test.dart`:
  - `banner_without_a_count_names_no_pending_upload`: `OfflineBanner(pendingCount: null)` shows "Tudo continua salvo neste aparelho." and no "aguarda".
- `test/features/home/home_v11_test.dart`: with records of each `syncStatus`, Início shows no "Pendente", "Enviada" or "Erro", and every row keeps its confidence.
- `test/features/main/main_tabs_mock_test.dart`: Início's recent rows show no `status-dot` and no "Enviada", and keep their 64 dp rhythm; Histórico's `pending` row shows the chevron and no `StatusPill`.
- `test/features/history/history_v11_test.dart`: offline, Histórico's banner reads "Sem conexão" and "Tudo continua salvo neste aparelho.", and names no count.
- `test/features/profile/profile_screen_test.dart`: `signed_in_records_count_as_only_on_this_device`: a signed-in account with records counts them under "só no aparelho", not "enviadas".

## Reproducibility

Flutter 3.44.1, Dart 3.12.1. Run `flutter test test/core/widgets/analysis_tile_test.dart`, then `flutter test`, `flutter analyze` and `mf check`.

## Risks and Assumptions

- **The constant can be forgotten.** A backend spec that does not set `syncBackendWired` leaves the status hidden. Its doc comment names that spec's duty, and `SyncEngine`'s wiring is the place it is read.
- **No golden draws a sync status.** None of the golden tests renders `AnalysisTile`, `HistoryList` or `HomeScreen`, so no golden changes.
