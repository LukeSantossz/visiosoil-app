// Migration tests for schema v2 -> v3 (offline-first sync foundation).
//
// A v2-shaped database is built directly with `package:sqlite3` (its
// `user_version` pragma set to 2), then opened through [AppDatabase] so Drift
// runs `onUpgrade`. This exercises the real migration path with real data,
// rather than asserting against the generated schema in isolation.
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:visiosoil_app/core/database/app_database.dart';

void main() {
  group('soil_records migration v2 -> v3', () {
    late Directory tempDir;
    late File dbFile;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('visiosoil_mig_v3');
      dbFile = File('${tempDir.path}/visiosoil_v2.db');
      _seedV2Database(dbFile.path);
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('migration_v2_to_v3_adds_sync_columns_without_data_loss', () async {
      final db = AppDatabase.forTesting(NativeDatabase(dbFile));
      addTearDown(db.close);

      final rows = await db
          .customSelect(
            'SELECT id, image_path, uuid, remote_id, sync_status, '
            'updated_at, deleted FROM soil_records ORDER BY id',
          )
          .get();

      expect(rows.length, 2, reason: 'both legacy rows must survive');
      expect(rows[0].read<String>('image_path'), '/legacy-a.jpg');
      expect(rows[1].read<String>('image_path'), '/legacy-b.jpg');
    });

    test('migration_backfills_uuid_and_updated_at_for_existing_rows', () async {
      final db = AppDatabase.forTesting(NativeDatabase(dbFile));
      addTearDown(db.close);

      final rows = await db
          .customSelect(
            'SELECT uuid, updated_at, sync_status, deleted, timestamp '
            'FROM soil_records ORDER BY id',
          )
          .get();

      final uuids = rows.map((r) => r.read<String>('uuid')).toList();
      for (final uuid in uuids) {
        expect(uuid, isNotEmpty);
        expect(uuid.length, 36, reason: 'canonical UUID v4 string length');
      }
      expect(uuids.toSet().length, uuids.length, reason: 'uuids are unique');

      for (final row in rows) {
        expect(row.read<String>('updated_at'), row.read<String>('timestamp'));
        expect(row.read<String>('sync_status'), 'pending');
        expect(row.read<int>('deleted'), 0);
      }
    });

    test('migration_enforces_uuid_uniqueness_with_index', () async {
      final db = AppDatabase.forTesting(NativeDatabase(dbFile));
      addTearDown(db.close);
      // Force the migration to run before inspecting the schema.
      await db.customSelect('SELECT 1').get();

      final indexes = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type = 'index' "
            "AND tbl_name = 'soil_records'",
          )
          .get();

      final names = indexes.map((r) => r.read<String>('name')).toList();
      expect(
        names.any((n) => n.contains('uuid')),
        isTrue,
        reason: 'a unique index on uuid must exist after migration',
      );
    });
  });
}

/// Creates a v2-shaped `soil_records` table with two rows and stamps the
/// database `user_version` to 2 so Drift treats it as a v2 schema.
void _seedV2Database(String path) {
  final raw = sqlite3.open(path);
  try {
    raw.execute('''
      CREATE TABLE soil_records (
        id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
        image_path TEXT NOT NULL,
        latitude REAL,
        longitude REAL,
        address TEXT,
        timestamp TEXT NOT NULL,
        texture_class TEXT,
        confidence_score REAL
      );
    ''');
    raw.execute(
      "INSERT INTO soil_records (image_path, timestamp) "
      "VALUES ('/legacy-a.jpg', '2026-01-01T00:00:00.000Z');",
    );
    raw.execute(
      "INSERT INTO soil_records (image_path, timestamp) "
      "VALUES ('/legacy-b.jpg', '2026-02-02T00:00:00.000Z');",
    );
    raw.execute('PRAGMA user_version = 2;');
  } finally {
    raw.dispose();
  }
}
