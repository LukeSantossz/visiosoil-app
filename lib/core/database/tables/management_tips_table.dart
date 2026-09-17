import 'package:drift/drift.dart';

/// Read-through cache of Research Agent Management Tips, one row per Soil Record.
///
/// Keyed by the record's global [recordUuid] (the stable identity from
/// `soil_records`), so cached tips track the record rather than its local
/// autoincrement id. The graded, cited result is stored whole as [payloadJson]
/// (serialized `ManagementTipsResult`); [retrievedAt] is duplicated out as a
/// column for future staleness/eviction queries.
///
/// This is deliberately NOT part of the sync outbox: tips are server-derived and
/// read-only, with no local mutation to push, so they never enter `sync_queue`.
@DataClassName('ManagementTipsRow')
class ManagementTips extends Table {
  @override
  String get tableName => 'management_tips';

  TextColumn get recordUuid => text().named('record_uuid')();
  TextColumn get payloadJson => text().named('payload_json')();
  TextColumn get retrievedAt => text().named('retrieved_at')();

  /// Which corpus release produced [payloadJson], duplicated out of the payload
  /// for the same reason [retrievedAt] is: so staleness can be answered without
  /// decoding every row.
  ///
  /// Nullable rather than defaulted. A row cached before v5 genuinely has no
  /// known version, and so does one written while the app held no corpus at all
  /// — a fabricated default would claim currency neither has. Null reads as
  /// stale against any corpus, which is what lets an answer given with no corpus
  /// refresh itself once one ships.
  TextColumn get corpusVersion =>
      text().named('corpus_version').nullable()();

  @override
  Set<Column> get primaryKey => {recordUuid};
}
