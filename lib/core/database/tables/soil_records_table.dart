import 'package:drift/drift.dart';

/// Tabela Drift para registros de solo.
///
/// O nome explícito da tabela (`soil_records`) evita colisão com o nome da
/// classe Dart e segue a convenção snake_case do SQLite.
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
