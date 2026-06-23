import 'package:drift/drift.dart';
import 'package:visiosoil_app/core/data/sync/sync_operation.dart';
import 'package:visiosoil_app/core/database/app_database.dart';
import 'package:visiosoil_app/core/database/soil_record_mapper.dart';
import 'package:visiosoil_app/models/soil_record.dart';

/// A pending entry read from the `sync_queue` outbox.
class PendingSyncOperation {
  const PendingSyncOperation({
    required this.id,
    required this.recordUuid,
    required this.operation,
  });

  final int id;
  final String recordUuid;
  final SyncOperation operation;
}

/// Low-level local data access for the [SyncEngine].
///
/// Deliberately separate from `SoilRecordRepository`: it reaches sync internals
/// (the outbox, tombstoned rows, `remote_id`) that screens must never see, so
/// the repository's public contract stays unchanged. Reads here intentionally
/// include tombstoned rows because merge must compare against them.
class SyncLocalStore {
  SyncLocalStore(this._db);

  final AppDatabase _db;

  /// Returns the outbox operations still awaiting sync, oldest first.
  Future<List<PendingSyncOperation>> pendingOperations() async {
    final query = _db.select(_db.syncQueue)
      ..where((t) => t.status.equals(SyncOperationStatus.pending.name))
      ..orderBy([(t) => OrderingTerm(expression: t.id)]);
    final rows = await query.get();
    return rows
        .map((row) => PendingSyncOperation(
              id: row.id,
              recordUuid: row.recordUuid,
              operation: SyncOperation.fromName(row.operation),
            ))
        .toList();
  }

  /// Marks an outbox operation as synced.
  Future<void> markOperationSynced(int operationId) async {
    await (_db.update(_db.syncQueue)..where((t) => t.id.equals(operationId)))
        .write(
      SyncQueueCompanion(status: Value(SyncOperationStatus.synced.name)),
    );
  }

  /// Finds a record by its global [uuid], including tombstoned rows.
  Future<SoilRecord?> findByUuid(String uuid) async {
    final row = await (_db.select(_db.soilRecords)
          ..where((t) => t.uuid.equals(uuid)))
        .getSingleOrNull();
    return row == null ? null : soilRecordFromRow(row);
  }

  /// Marks a local record as synced, optionally storing the backend [remoteId].
  ///
  /// A delete push leaves [remoteId] null (the tombstone may never have been
  /// pushed as an upsert), so the existing `remote_id` is left untouched.
  Future<void> markRecordSynced(String uuid, {String? remoteId}) async {
    await (_db.update(_db.soilRecords)..where((t) => t.uuid.equals(uuid)))
        .write(
      SoilRecordsCompanion(
        remoteId: remoteId == null ? const Value.absent() : Value(remoteId),
        syncStatus: const Value('synced'),
      ),
    );
  }

  /// Inserts a record pulled from the backend that does not exist locally.
  Future<void> insertFromRemote(SoilRecord remote) async {
    await _db.into(_db.soilRecords).insert(
          SoilRecordsCompanion.insert(
            uuid: remote.uuid!,
            remoteId: Value(remote.remoteId),
            imagePath: remote.imagePath,
            latitude: Value(remote.latitude),
            longitude: Value(remote.longitude),
            address: Value(remote.address),
            timestamp: remote.timestamp,
            updatedAt: remote.updatedAt ?? remote.timestamp,
            deleted: Value(remote.deleted),
            syncStatus: const Value('synced'),
            textureClass: Value(remote.textureClass),
            confidenceScore: Value(remote.confidenceScore),
          ),
        );
  }

  /// Overwrites the local row for [remote] with the backend's version (used
  /// when the remote wins the merge).
  Future<void> applyRemote(SoilRecord remote) async {
    await (_db.update(_db.soilRecords)
          ..where((t) => t.uuid.equals(remote.uuid!)))
        .write(
      SoilRecordsCompanion(
        remoteId: Value(remote.remoteId),
        imagePath: Value(remote.imagePath),
        latitude: Value(remote.latitude),
        longitude: Value(remote.longitude),
        address: Value(remote.address),
        timestamp: Value(remote.timestamp),
        updatedAt: Value(remote.updatedAt ?? remote.timestamp),
        deleted: Value(remote.deleted),
        syncStatus: const Value('synced'),
        textureClass: Value(remote.textureClass),
        confidenceScore: Value(remote.confidenceScore),
      ),
    );
  }
}
