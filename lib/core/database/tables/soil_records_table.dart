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

  /// v7 (SPEC 0097): every class's probability, as a JSON array of
  /// `{"label", "probability"}` in the contract's class order, and the versions
  /// of the contract that scored the photograph. Null when not known: a record
  /// saved before v7, or without a classification, never had them.
  TextColumn get classDistribution =>
      text().named('class_distribution').nullable()();
  TextColumn get modelVersion => text().named('model_version').nullable()();
  TextColumn get datasetVersion => text().named('dataset_version').nullable()();

  /// v8 (SPEC 0148): the radius in metres the device reported for the GPS
  /// fix. Null when not known: a record saved before v8, without a location,
  /// or whose device reported no usable accuracy, never had one.
  RealColumn get horizontalAccuracy =>
      real().named('horizontal_accuracy').nullable()();

  /// v9 (SPEC 0149): the field or plot the agronomist named for the sample,
  /// and the sample's own label. Null when not given, which every record
  /// saved before v9 is.
  TextColumn get fieldName => text().named('field_name').nullable()();
  TextColumn get sampleLabel => text().named('sample_label').nullable()();
}
