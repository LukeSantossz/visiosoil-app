import 'package:visiosoil_app/models/soil_record.dart';

/// Backend-agnostic contract the [SyncEngine] drains the outbox against.
///
/// Concrete backends (Google Drive, NAS/WebDAV) implement this in their own
/// issues. Records are identified across devices by [SoilRecord.uuid]; the
/// returned handle is stored locally as [SoilRecord.remoteId]. Blob transfer is
/// exposed here so backends can move image bytes; the concrete upload strategy
/// is per-backend.
abstract class RemoteSyncBackend {
  /// Pushes a record's metadata (create or update). Returns the backend handle
  /// to persist as the record's `remote_id`.
  Future<String> pushRecord(SoilRecord record);

  /// Propagates a tombstone so the deletion is not resurrected on pull.
  Future<void> deleteRecord(SoilRecord record);

  /// Pulls records changed on the backend since the last sync.
  Future<List<SoilRecord>> pullRecords();

  /// Uploads an image blob for [uuid]. Returns the backend handle.
  Future<String> uploadBlob(String uuid, List<int> bytes);

  /// Downloads an image blob by its backend handle.
  Future<List<int>> downloadBlob(String remoteId);
}
