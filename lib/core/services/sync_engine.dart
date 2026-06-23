import 'package:visiosoil_app/core/data/sync/remote_sync_backend.dart';
import 'package:visiosoil_app/core/data/sync/sync_local_store.dart';
import 'package:visiosoil_app/core/data/sync/sync_operation.dart';
import 'package:visiosoil_app/models/soil_record.dart';

/// Outcome of a [SyncEngine.sync] run.
class SyncReport {
  const SyncReport({required this.pushed, required this.pulled});

  /// Number of outbox operations drained to the backend.
  final int pushed;

  /// Number of remote records applied locally.
  final int pulled;
}

/// Backend-agnostic sync engine.
///
/// Drains the outbox to a [RemoteSyncBackend] (push), then merges remote
/// changes back (pull). Conflicts resolve by last-write-wins on `updated_at`,
/// with delete-wins on a timestamp tie so a tombstone is never resurrected.
class SyncEngine {
  SyncEngine({
    required SyncLocalStore localStore,
    required RemoteSyncBackend backend,
  })  : _local = localStore,
        _backend = backend;

  final SyncLocalStore _local;
  final RemoteSyncBackend _backend;

  Future<SyncReport> sync() async {
    final pushed = await _drainOutbox();
    final pulled = await _pullRemote();
    return SyncReport(pushed: pushed, pulled: pulled);
  }

  /// Pushes every pending outbox operation to the backend and marks it synced.
  Future<int> _drainOutbox() async {
    final operations = await _local.pendingOperations();
    for (final operation in operations) {
      final record = await _local.findByUuid(operation.recordUuid);
      if (record != null) {
        await _pushOperation(operation.operation, record);
      }
      await _local.markOperationSynced(operation.id);
    }
    return operations.length;
  }

  Future<void> _pushOperation(SyncOperation operation, SoilRecord record) async {
    switch (operation) {
      case SyncOperation.delete:
        await _backend.deleteRecord(record);
        await _local.markRecordSynced(record.uuid!);
      case SyncOperation.upsert:
        final remoteId = await _backend.pushRecord(record);
        await _local.markRecordSynced(record.uuid!, remoteId: remoteId);
    }
  }

  /// Pulls remote records and applies the ones that win the merge.
  Future<int> _pullRemote() async {
    final remotes = await _backend.pullRecords();
    var applied = 0;
    for (final remote in remotes) {
      final local = await _local.findByUuid(remote.uuid!);
      if (local == null) {
        await _local.insertFromRemote(remote);
        applied++;
      } else if (_remoteWins(local, remote)) {
        await _local.applyRemote(remote);
        applied++;
      }
    }
    return applied;
  }

  /// Last-write-wins by `updated_at`; on a tie, a tombstone wins so deletions
  /// propagate instead of resurrecting.
  ///
  /// Comparison is by UTC instant, not lexicographic string order, so stamps
  /// with different timezone offsets are ordered correctly.
  bool _remoteWins(SoilRecord local, SoilRecord remote) {
    final localInstant = _instant(local.updatedAt ?? local.timestamp);
    final remoteInstant = _instant(remote.updatedAt ?? remote.timestamp);
    final comparison = remoteInstant.compareTo(localInstant);
    if (comparison != 0) return comparison > 0;
    return remote.deleted && !local.deleted;
  }

  /// Parses an ISO-8601 timestamp to a UTC [DateTime]. An unparseable value
  /// sorts oldest so it never wins a merge by accident.
  DateTime _instant(String value) =>
      DateTime.tryParse(value)?.toUtc() ??
      DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
}
