import 'package:drift/drift.dart';

/// Drift table for soil records.
///
/// The explicit table name (`soil_records`) avoids collision with the Dart
/// class name and follows the SQLite snake_case convention.
///
/// Sync metadata (v3): [uuid] is the canonical, client-generated global
/// identity; [remoteId] holds the backend handle once synced; [updatedAt]
/// drives last-write-wins; [deleted] is a tombstone so deletions propagate
/// instead of resurrecting on pull.
@DataClassName('SoilRecordRow')
@TableIndex(name: 'idx_soil_records_uuid', columns: {#uuid}, unique: true)
class SoilRecords extends Table {
  @override
  String get tableName => 'soil_records';

  IntColumn get id => integer().autoIncrement()();
  TextColumn get uuid => text()();
  TextColumn get remoteId => text().named('remote_id').nullable()();
  TextColumn get syncStatus =>
      text().named('sync_status').withDefault(const Constant('pending'))();
  TextColumn get imagePath => text().named('image_path')();
  RealColumn get latitude => real().nullable()();
  RealColumn get longitude => real().nullable()();
  TextColumn get address => text().nullable()();
  TextColumn get timestamp => text()();
  TextColumn get updatedAt => text().named('updated_at')();
  BoolColumn get deleted => boolean().withDefault(const Constant(false))();
  TextColumn get textureClass => text().named('texture_class').nullable()();
  RealColumn get confidenceScore =>
      real().named('confidence_score').nullable()();
}
