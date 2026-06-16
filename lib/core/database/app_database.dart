import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:visiosoil_app/core/database/tables/soil_records_table.dart';
import 'package:visiosoil_app/core/database/tables/sync_queue_table.dart';

part 'app_database.g.dart';

/// VisioSoil local database (SQLite + Drift).
///
/// Holds the [SoilRecords] table and the [SyncQueue] outbox. Future tables must
/// be added to the `tables` array and accompanied by a bump in [schemaVersion]
/// with the corresponding migration in [migration].
@DriftDatabase(tables: [SoilRecords, SyncQueue])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  /// Constructor used in tests to inject an in-memory [QueryExecutor].
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (migrator) async {
          await migrator.createAll();
        },
        onUpgrade: (migrator, from, to) async {
          if (from < 2) {
            // v1 -> v2: adds texture classification columns
            await migrator.addColumn(soilRecords, soilRecords.textureClass);
            await migrator.addColumn(soilRecords, soilRecords.confidenceScore);
          }
          if (from < 3) {
            // v2 -> v3: offline-first sync foundation.
            await _migrateToV3(migrator);
          }
        },
      );

  /// Adds sync metadata to `soil_records`, backfills existing rows, and creates
  /// the `sync_queue` outbox.
  ///
  /// `uuid` and `updated_at` cannot be added as NOT NULL columns to a populated
  /// table in SQLite, so they are added nullable, backfilled per row, then a
  /// unique index enforces `uuid`. `remote_id`, `sync_status`, and `deleted`
  /// carry defaults and migrate directly.
  Future<void> _migrateToV3(Migrator migrator) async {
    await migrator.addColumn(soilRecords, soilRecords.remoteId);
    await migrator.addColumn(soilRecords, soilRecords.syncStatus);
    await migrator.addColumn(soilRecords, soilRecords.deleted);

    await customStatement('ALTER TABLE soil_records ADD COLUMN uuid TEXT');
    await customStatement('ALTER TABLE soil_records ADD COLUMN updated_at TEXT');

    const generator = Uuid();
    final existing =
        await customSelect('SELECT id, timestamp FROM soil_records').get();
    for (final row in existing) {
      await customStatement(
        'UPDATE soil_records SET uuid = ?, updated_at = ? WHERE id = ?',
        [generator.v4(), row.read<String>('timestamp'), row.read<int>('id')],
      );
    }

    await customStatement(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_soil_records_uuid '
      'ON soil_records (uuid)',
    );

    await migrator.createTable(syncQueue);
  }
}

QueryExecutor _openConnection() {
  // `driftDatabase` takes care of the documents directory path, lazy opening,
  // and the appropriate isolate on each platform.
  return driftDatabase(name: 'visiosoil');
}
