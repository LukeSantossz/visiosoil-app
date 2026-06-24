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

  @override
  Set<Column> get primaryKey => {recordUuid};
}
