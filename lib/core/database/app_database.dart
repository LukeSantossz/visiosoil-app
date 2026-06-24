import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:visiosoil_app/core/database/tables/management_tips_table.dart';
import 'package:visiosoil_app/core/database/tables/soil_records_table.dart';
import 'package:visiosoil_app/core/database/tables/sync_queue_table.dart';

part 'app_database.g.dart';

/// VisioSoil local database (SQLite + Drift).
///
/// Holds the [SoilRecords] table, the [SyncQueue] outbox, and the
/// [ManagementTips] read-through cache. Future tables must be added to the
/// `tables` array and accompanied by a bump in [schemaVersion] with the
/// corresponding migration in [migration].
@DriftDatabase(tables: [SoilRecords, SyncQueue, ManagementTips])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  /// Constructor used in tests to inject an in-memory [QueryExecutor].
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 4;

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
          if (from < 4) {
            // v3 -> v4: management tips read-through cache (new table only).
            await migrator.createTable(managementTips);
          }
        },
      );

  /// Adds sync metadata to `soil_records`, backfills existing rows, creates the
  /// `sync_queue` outbox, and enqueues each legacy record for its first sync.
  ///
  /// `uuid` and `updated_at` cannot be added as NOT NULL columns to a populated
  /// table in SQLite, so they are added nullable, backfilled per row, then a
  /// unique index enforces `uuid`. `remote_id`, `sync_status`, and `deleted`
  /// carry defaults and migrate directly. Backfilled `updated_at` values are
  /// normalized to a canonical UTC instant, and each migrated record gets an
  /// `upsert` outbox entry so it is not stranded outside the sync path.
  Future<void> _migrateToV3(Migrator migrator) async {
    await migrator.addColumn(soilRecords, soilRecords.remoteId);
    await migrator.addColumn(soilRecords, soilRecords.syncStatus);
    await migrator.addColumn(soilRecords, soilRecords.deleted);

    await customStatement('ALTER TABLE soil_records ADD COLUMN uuid TEXT');
    await customStatement('ALTER TABLE soil_records ADD COLUMN updated_at TEXT');

    // The outbox must exist before the backfill so legacy records can be
    // enqueued in the same pass.
    await migrator.createTable(syncQueue);

    const generator = Uuid();
    final existing =
        await customSelect('SELECT id, timestamp FROM soil_records').get();
    for (final row in existing) {
      final uuid = generator.v4();
      // Legacy timestamps were written timezone-naive; normalize to a canonical
      // UTC instant so last-write-wins ordering is identical across devices.
      final updatedAt = _toUtcInstant(row.read<String>('timestamp'));
      await customStatement(
        'UPDATE soil_records SET uuid = ?, updated_at = ? WHERE id = ?',
        [uuid, updatedAt, row.read<int>('id')],
      );
      // SyncEngine only pushes rows present in the outbox, so a legacy record
      // without an entry would never upload on first sync.
      await customStatement(
        'INSERT INTO sync_queue (record_uuid, operation, status, created_at) '
        'VALUES (?, ?, ?, ?)',
        [uuid, 'upsert', 'pending', updatedAt],
      );
    }

    await customStatement(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_soil_records_uuid '
      'ON soil_records (uuid)',
    );
  }

  /// Returns the canonical UTC ISO-8601 form of a possibly timezone-naive
  /// timestamp; an unparseable value is returned unchanged so the migration
  /// never aborts on unexpected legacy data.
  String _toUtcInstant(String value) {
    final parsed = DateTime.tryParse(value);
    return parsed == null ? value : parsed.toUtc().toIso8601String();
  }
}

QueryExecutor _openConnection() {
  // `driftDatabase` takes care of the documents directory path, lazy opening,
  // and the appropriate isolate on each platform.
  return driftDatabase(name: 'visiosoil');
}
