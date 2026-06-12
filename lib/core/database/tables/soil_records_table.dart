import 'package:drift/drift.dart';

/// Drift table for soil records.
///
/// The explicit table name (`soil_records`) avoids collision with the Dart
/// class name and follows the SQLite snake_case convention.
@DataClassName('SoilRecordRow')
class SoilRecords extends Table {
  @override
  String get tableName => 'soil_records';

  IntColumn get id => integer().autoIncrement()();
  TextColumn get imagePath => text().named('image_path')();
  RealColumn get latitude => real().nullable()();
  RealColumn get longitude => real().nullable()();
  TextColumn get address => text().nullable()();
  TextColumn get timestamp => text()();
  TextColumn get textureClass => text().named('texture_class').nullable()();
  RealColumn get confidenceScore => real().named('confidence_score').nullable()();
}
