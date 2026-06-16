/// Kinds of sync operation persisted in the `sync_queue` outbox.
///
/// Stored as the lowercase [name] in the `operation` column. `upsert` covers
/// both create and any future edit (records are create+delete only today);
/// `delete` carries a tombstone so the deletion propagates on pull.
enum SyncOperation {
  upsert,
  delete;

  static SyncOperation fromName(String value) =>
      SyncOperation.values.firstWhere((op) => op.name == value);
}

/// Lifecycle status of a queued operation.
enum SyncOperationStatus {
  pending,
  synced;

  static SyncOperationStatus fromName(String value) =>
      SyncOperationStatus.values.firstWhere((status) => status.name == value);
}
