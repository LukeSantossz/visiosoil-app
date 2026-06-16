import 'package:drift/drift.dart';

/// Durable outbox of pending sync operations.
///
/// Every local mutation (create -> `upsert`, delete -> `delete`) appends a row
/// here so the [SyncEngine] can drain it against a backend later. Operations
/// reference the record by its global [recordUuid]; [status] tracks whether the
/// operation is still `pending` or already `synced`.
@DataClassName('SyncQueueRow')
class SyncQueue extends Table {
  @override
  String get tableName => 'sync_queue';

  IntColumn get id => integer().autoIncrement()();
  TextColumn get recordUuid => text().named('record_uuid')();
  TextColumn get operation => text()();
  TextColumn get status => text().withDefault(const Constant('pending'))();
  TextColumn get createdAt => text().named('created_at')();
}
