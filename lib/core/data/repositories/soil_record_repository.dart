import 'package:visiosoil_app/core/services/classification_report.dart';
import 'package:visiosoil_app/models/class_score.dart';
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

  /// Writes the true class and the sample label of the record with the given
  /// [id] and marks it for sync (SPEC 0149, SPEC 0220).
  ///
  /// [trueTextureClass] is a name from `SoilTextureReference.modelClasses`, or
  /// null to clear it; any other name throws an [ArgumentError] and nothing is
  /// written. The sample label is trimmed, and one that is empty once trimmed
  /// is stored as null. The field label is not written. No-op if the record
  /// does not exist or is deleted.
  Future<void> updateCorrection(
    int id, {
    String? trueTextureClass,
    String? sampleLabel,
  });

  /// Writes what classifying the record with the given [id] produced and
  /// marks it for sync (SPEC 0219): the result, or the [classificationFailure]
  /// when nothing was classified. No-op if the record does not exist or is
  /// deleted.
  Future<void> updateClassification(
    int id, {
    String? textureClass,
    double? confidenceScore,
    List<ClassScore>? classDistribution,
    String? modelVersion,
    String? datasetVersion,
    ClassificationFailureCause? classificationFailure,
  });

  /// Writes the location reading of the record with the given [id] and marks
  /// it for sync (SPEC 0219). No-op if the record does not exist or is
  /// deleted.
  Future<void> updateLocation(
    int id, {
    required double latitude,
    required double longitude,
    double? horizontalAccuracy,
    required String address,
  });

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
  /// [searchTerm] filters by address or sample label, case-insensitively: a
  /// record matches when either contains it. The field label is not searched
  /// (SPEC 0220). It is
  /// matched as a literal substring: it is trimmed first, and `%` and `_`
  /// match themselves rather than acting as SQL wildcards.
  ///
  /// A filter that carries no content is not applied. For either argument that
  /// means null or empty; for [searchTerm] it also means a value that is empty
  /// once trimmed. When neither filter applies, behavior is identical to
  /// [watchAll].
  Stream<List<SoilRecord>> watchFiltered({
    String? textureClass,
    String? searchTerm,
  });
}
