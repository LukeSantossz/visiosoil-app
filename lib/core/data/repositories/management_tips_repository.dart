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

  /// Returns the cached tips together with the corpus release that produced
  /// them, or `null` if none are stored.
  ///
  /// Separate from [getByRecordUuid] because most callers only want the result;
  /// this one exists for the caller that has to decide whether to refresh.
  Future<CachedManagementTips?> getCached(String recordUuid);

  /// Stores [result] for [recordUuid], replacing any existing entry.
  Future<void> upsert(String recordUuid, ManagementTipsResult result);

  /// Removes the cached tips for [recordUuid]. No-op if none exist.
  Future<void> deleteByRecordUuid(String recordUuid);
}

/// A cached result and the corpus release it came from.
///
/// The repository **reports** staleness and does not act on it: it is a cache,
/// not an orchestrator, and deciding to regenerate belongs to the caller. Making
/// a read perform a write is the shape this split exists to avoid.
class CachedManagementTips {
  const CachedManagementTips({
    required this.result,
    required this.corpusVersion,
  });

  final ManagementTipsResult result;

  /// The value in the column, which is null for a row cached before schema v5
  /// and for one written while the app held no corpus.
  final String? corpusVersion;

  /// Whether this row was produced by a corpus other than [currentVersion].
  ///
  /// **Exact inequality, not ordering.** A corpus version is a release label,
  /// not a number: any difference means a different corpus answered, which is
  /// the question the cache needs answered. Ordering would require the app to
  /// understand a versioning scheme the corpus build owns, and would silently
  /// answer "not stale" the first time that scheme changed.
  ///
  /// A null cached version is stale against any corpus — that is what lets an
  /// answer given while no corpus was held refresh itself once one ships. With
  /// no corpus held either, nothing is out of date, or the app would report
  /// every row stale forever.
  bool isStaleAgainst(String? currentVersion) => corpusVersion != currentVersion;
}
