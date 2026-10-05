import 'package:visiosoil_app/core/data/sync/remote_sync_backend.dart';
import 'package:visiosoil_app/core/data/sync/sync_local_store.dart';
import 'package:visiosoil_app/core/data/sync/sync_operation.dart';
import 'package:visiosoil_app/models/soil_record.dart';

/// Outcome of a [SyncEngine.sync] run.
class SyncReport {
  const SyncReport({required this.pushed, required this.pulled});

  /// Number of outbox operations sent to the backend. An operation a newer
  /// remote version superseded is drained without being sent (SPEC 0136).
  final int pushed;

  /// Number of remote records applied locally.
  final int pulled;
}

/// Backend-agnostic sync engine.
///
/// Pulls the remote changes first, then drains the outbox to a
/// [RemoteSyncBackend] (push), then merges the pulled changes back. Conflicts
/// resolve by last-write-wins on `updated_at`, with delete-wins on a timestamp
/// tie so a tombstone is never resurrected. The same rule decides each push,
/// so a stale local operation never overwrites a newer remote one (SPEC 0136).
class SyncEngine {
  SyncEngine({
    required SyncLocalStore localStore,
    required this._backend,
  }) : _local = localStore;

  final SyncLocalStore _local;
  final RemoteSyncBackend _backend;

  Future<SyncReport> sync() async {
    // Pulled before anything is pushed, so each push is decided against the
    // remote's version (#88).
    final remotes = await _backend.pullRecords();
    final pushed = await _drainOutbox({
      for (final remote in remotes) remote.uuid!: remote,
    });
    final pulled = await _mergeRemote(remotes);
    return SyncReport(pushed: pushed, pulled: pulled);
  }

  /// Pushes each pending outbox operation whose record wins against the
  /// pulled remote version, and marks every one synced. One that loses is
  /// stale: it is dropped, and the merge applies the newer remote instead.
  Future<int> _drainOutbox(Map<String, SoilRecord> remoteByUuid) async {
    final operations = await _local.pendingOperations();
    var pushed = 0;
    for (final operation in operations) {
      final record = await _local.findByUuid(operation.recordUuid);
      final remote = remoteByUuid[operation.recordUuid];
      if (record != null && (remote == null || !_remoteWins(record, remote))) {
        await _pushOperation(operation.operation, record);
        pushed++;
      }
      await _local.markOperationSynced(operation.id);
    }
    return pushed;
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

  /// Applies the pulled remote records that win the merge.
  Future<int> _mergeRemote(List<SoilRecord> remotes) async {
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
