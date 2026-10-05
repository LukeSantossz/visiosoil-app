# SPEC: fix(sync): compare the remote version before pushing, so a stale push cannot overwrite newer data

## Problem

`SyncEngine.sync()` drains the outbox to the backend first, and only then pulls and merges by last-write-wins (#88). The comparison in `_remoteWins` protects the local side during the pull. On the way out, `_pushOperation` calls `pushRecord` or `deleteRecord` with no comparison, and the `RemoteSyncBackend` contract does not ask a backend to run one.

So a stale local operation reaches the backend before the engine has looked at the remote:
- a pending upsert overwrites a newer remote edit;
- a pending delete deletes a newer remote edit.

The defect is dormant: no concrete backend exists (#55), and `SyncEngine` is not in the provider graph. It becomes live the day one is wired.

## Design Decision

**`sync()` pulls first, then decides each push against what it pulled.** The engine calls `pullRecords()` once, at the start, and indexes the result by `uuid`. For each pending operation:
- with no pulled version of its record, the remote has not changed since the last sync, so the operation is pushed, as today;
- with a pulled version that loses to the local record under `_remoteWins`, the operation is pushed;
- with a pulled version that wins, the operation is not pushed. The local record is stale, and pushing it would overwrite the newer remote.

In every case the outbox entry is marked synced, so a stale one does not come back on the next run.

**The merge then runs over the same pulled list,** with the same `_remoteWins`. The remote version that stopped a push is the one it applies, so the device ends with the newer data. A pushed local winner is not overwritten, because the remote it was compared with lost.

So one rule decides both directions: last-write-wins on `updated_at`, and a tombstone on a tie.

**`SyncReport.pushed` counts the operations sent to the backend.** A superseded operation is drained without being sent, and is not counted. No caller reads the report today.

**The backend contract does not change.** `pullRecords()` already returns what changed on the backend since the last sync, which is what the comparison needs. #55 can add a server-side check later without changing this order.

## Alternatives Considered

- **Push, then pull, as today, with a check inside each backend.** Rejected: the contract would rely on every backend implementing the same comparison. The engine already holds the rule.
- **Pull, merge, then push.** Rejected, as #88 notes: the outbox still holds the stale operation after the merge, and the merged record would be pushed as if it were a local change.
- **Fetch each record's remote version just before pushing it.** Rejected: one request per operation, and the contract has no single-record read.

## Scope

- Includes:
  - `lib/core/services/sync_engine.dart`: the order, the comparison before each push, and the report's count.
  - `test/services/sync_engine_test.dart`: the tests below.
- Does NOT include:
  - A concrete backend, a scheduler, or wiring `SyncEngine` into providers (#55, #57).
  - Partial-failure handling, such as a pull that fails. A failed pull now stops the run before anything is pushed, which is the safe side.
  - Blob transfer.

## Acceptance Criteria

- `stale_upsert_is_not_pushed`: with a pending upsert older than the pulled remote version, nothing is pushed for that record, its outbox entry is drained, and the local record takes the remote's content.
- `stale_delete_is_not_pushed`: with a pending delete older than a pulled remote edit, no delete is sent, its outbox entry is drained, and the local record takes the remote edit.
- `newer_local_still_pushes`: with a pending upsert newer than the pulled remote version, the record is pushed and keeps its local content.
- `a_tie_pushes_a_local_tombstone`: with a pending delete and a pulled remote edit of the same `updated_at`, the delete is sent, as the tie rule says.
- `report_counts_what_was_sent`: `SyncReport.pushed` counts the operations sent, not the ones superseded.
- The existing tests pass unchanged.

## Reproducibility

`flutter test test/services/sync_engine_test.dart`

Flutter 3.44.1, Dart 3.12.1.

## Risks and Assumptions

- The rule assumes `pullRecords()` returns every record changed on the backend since the last sync, as its contract states. A backend that returns less lets a stale push through, as it would today.
- Two devices whose clocks disagree still resolve by their clocks. That is a limit of last-write-wins on `updated_at`, the engine's documented rule, and this spec does not change the rule.
