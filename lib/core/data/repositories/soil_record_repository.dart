import 'package:visiosoil_app/models/soil_record.dart';

/// Persistence contract for [SoilRecord].
///
/// The UI depends only on this interface: Drift-specific types never
/// leak into the presentation layers. An implementation based on another
/// mechanism (e.g. a remote API) could be plugged in without changing the screens.
abstract class SoilRecordRepository {
  /// Persists [record] and returns a copy with the [SoilRecord.id] filled in.
  Future<SoilRecord> create(SoilRecord record);

  /// Returns the record with the given [id] or `null` if it does not exist.
  Future<SoilRecord?> getById(int id);

  /// Emits the full list of records, ordered from most recent to oldest,
  /// reacting to database changes.
  Stream<List<SoilRecord>> watchAll();

  /// Reads the full list of records, ordered from most recent to oldest,
  /// in a single request.
  Future<List<SoilRecord>> getAll();

  /// Returns the most recent record or `null` if the database is empty.
  Future<SoilRecord?> getLatest();

  /// Returns the total number of records.
  Future<int> count();

  /// Deletes the record with the given [id]. No-op if it does not exist.
  Future<void> deleteById(int id);

  /// Deletes in batch the records whose ids are listed in [ids].
  Future<void> deleteByIds(List<int> ids);

  /// Deletes all records from the database in a single operation.
  Future<void> deleteAll();

  /// Emits a filtered list of records, reacting to database changes.
  ///
  /// [textureClass] filters by texture class (exact match).
  ///
  /// [searchTerm] filters by address, case-insensitively. It is matched as a
  /// literal substring: it is trimmed first, and `%` and `_` match themselves
  /// rather than acting as SQL wildcards.
  ///
  /// A filter that carries no content is not applied. For either argument that
  /// means null or empty; for [searchTerm] it also means a value that is empty
  /// once trimmed. When neither filter applies, behavior is identical to
  /// [watchAll].
  Stream<List<SoilRecord>> watchFiltered({
    String? textureClass,
    String? searchTerm,
  });

  /// Returns the list of distinct texture classes present in the database.
  Future<List<String>> getDistinctTextureClasses();
}
