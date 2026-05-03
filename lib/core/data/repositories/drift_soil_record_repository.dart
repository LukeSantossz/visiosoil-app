import 'package:drift/drift.dart';
import 'package:visiosoil_app/core/data/repositories/soil_record_repository.dart';
import 'package:visiosoil_app/core/database/app_database.dart';
import 'package:visiosoil_app/models/soil_record.dart';

/// Implementação de [SoilRecordRepository] baseada em Drift/SQLite.
///
/// Concentra toda a conversão entre linhas Drift ([SoilRecordRow]) e o modelo
/// de domínio [SoilRecord]. Nenhum tipo específico do Drift escapa por esta
/// fronteira.
class DriftSoilRecordRepository implements SoilRecordRepository {
  DriftSoilRecordRepository(this._db);

  final AppDatabase _db;

  @override
  Future<SoilRecord> create(SoilRecord record) async {
    final id = await _db.into(_db.soilRecords).insert(
          SoilRecordsCompanion.insert(
            imagePath: record.imagePath,
            latitude: Value(record.latitude),
            longitude: Value(record.longitude),
            address: Value(record.address),
            timestamp: record.timestamp,
            textureClass: Value(record.textureClass),
            confidenceScore: Value(record.confidenceScore),
          ),
        );
    return record.copyWith(id: id);
  }

  @override
  Future<SoilRecord?> getById(int id) async {
    final row = await (_db.select(_db.soilRecords)
          ..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    return row == null ? null : _toDomain(row);
  }

  @override
  Stream<List<SoilRecord>> watchAll() {
    final query = _db.select(_db.soilRecords)
      ..orderBy([
        (t) => OrderingTerm(expression: t.id, mode: OrderingMode.desc),
      ]);
    return query.watch().map((rows) => rows.map(_toDomain).toList());
  }

  @override
  Future<List<SoilRecord>> getAll() async {
    final query = _db.select(_db.soilRecords)
      ..orderBy([
        (t) => OrderingTerm(expression: t.id, mode: OrderingMode.desc),
      ]);
    final rows = await query.get();
    return rows.map(_toDomain).toList();
  }

  @override
  Future<SoilRecord?> getLatest() async {
    final query = _db.select(_db.soilRecords)
      ..orderBy([
        (t) => OrderingTerm(expression: t.id, mode: OrderingMode.desc),
      ])
      ..limit(1);
    final row = await query.getSingleOrNull();
    return row == null ? null : _toDomain(row);
  }

  @override
  Future<int> count() async {
    final countExp = _db.soilRecords.id.count();
    final query = _db.selectOnly(_db.soilRecords)..addColumns([countExp]);
    final row = await query.getSingle();
    return row.read(countExp) ?? 0;
  }

  @override
  Future<void> deleteById(int id) async {
    await (_db.delete(_db.soilRecords)..where((t) => t.id.equals(id))).go();
  }

  @override
  Future<void> deleteByIds(List<int> ids) async {
    if (ids.isEmpty) return;
    await (_db.delete(_db.soilRecords)..where((t) => t.id.isIn(ids))).go();
  }

  SoilRecord _toDomain(SoilRecordRow row) => SoilRecord(
        id: row.id,
        imagePath: row.imagePath,
        latitude: row.latitude,
        longitude: row.longitude,
        address: row.address,
        timestamp: row.timestamp,
        textureClass: row.textureClass,
        confidenceScore: row.confidenceScore,
      );
}
