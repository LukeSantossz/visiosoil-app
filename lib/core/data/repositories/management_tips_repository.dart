import 'package:visiosoil_app/models/management_tips_result.dart';

/// Persistence contract for cached Management Tips, keyed by a Soil Record's
/// global `uuid`.
///
/// A read-through cache: the UI reads cached tips here and the research layer
/// writes the graded, cited result after a fetch. Like [SoilRecordRepository],
/// Drift-specific types never leak past this interface.
abstract class ManagementTipsRepository {
  /// Returns the cached tips for [recordUuid], or `null` if none are stored.
  Future<ManagementTipsResult?> getByRecordUuid(String recordUuid);

  /// Stores [result] for [recordUuid], replacing any existing entry.
  Future<void> upsert(String recordUuid, ManagementTipsResult result);

  /// Removes the cached tips for [recordUuid]. No-op if none exist.
  Future<void> deleteByRecordUuid(String recordUuid);
}
