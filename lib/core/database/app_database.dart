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
  int get schemaVersion => 9;

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
          if (from >= 4 && from < 5) {
            // v4 -> v5: which corpus release answered. Nullable, so existing
            // rows keep their data and read as stale rather than claiming a
            // currency they never had.
            //
            // Guarded by `from >= 4` and not only by `from < 5`: the step above
            // calls `createTable`, which creates the table from **today's**
            // definition, so a database older than v4 already arrives here with
            // the column. Adding it again is a `duplicate column name` error,
            // which is how this guard was found.
            await migrator.addColumn(
                managementTips, managementTips.corpusVersion);
          }
          if (from < 6) {
            // v5 -> v6: no table changes shape. Tombstones written before
            // SPEC 0093 still hold what the user captured.
            await _eraseTombstoneContent();
          }
          if (from < 7) {
            // v6 -> v7: the class distribution and the contract versions that
            // scored it (SPEC 0097). No earlier step recreates `soil_records`,
            // so every path adds these once. Nullable, so every existing row,
            // tombstones included, arrives with none, which is what it has; the
            // v6 erase above cannot name them, since they do not exist yet.
            await migrator.addColumn(soilRecords, soilRecords.classDistribution);
            await migrator.addColumn(soilRecords, soilRecords.modelVersion);
            await migrator.addColumn(soilRecords, soilRecords.datasetVersion);
          }
          if (from < 8) {
            // v7 -> v8: the horizontal accuracy of the GPS fix (SPEC 0148).
            // Nullable, so every existing row, tombstones included, arrives
            // with none, as for v7; the v6 erase cannot name it either.
            await migrator.addColumn(
                soilRecords, soilRecords.horizontalAccuracy);
          }
          if (from < 9) {
            // v8 -> v9: the field and sample labels (SPEC 0149). Nullable,
            // so every existing row, tombstones included, arrives unlabelled.
            await migrator.addColumn(soilRecords, soilRecords.fieldName);
            await migrator.addColumn(soilRecords, soilRecords.sampleLabel);
          }
        },
      );

  /// Erases the content of every tombstoned record and drops its cached tips,
  /// as a delete has done since SPEC 0093, so a tombstone keeps only what sync
  /// reads: its uuid, remote id, flag and deletion instant. `timestamp` is NOT
  /// NULL, so it takes the deletion instant, which `updated_at` holds.
  Future<void> _eraseTombstoneContent() async {
    await customStatement(
      "UPDATE soil_records SET image_path = '', latitude = NULL, "
      'longitude = NULL, address = NULL, timestamp = updated_at, '
      'texture_class = NULL, confidence_score = NULL WHERE deleted = 1',
    );
    await customStatement(
      'DELETE FROM management_tips WHERE record_uuid IN '
      '(SELECT uuid FROM soil_records WHERE deleted = 1)',
    );
  }

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
