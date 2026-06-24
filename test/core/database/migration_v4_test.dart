// Migration tests for schema v3 -> v4 (management tips read-through cache).
//
// A v3-shaped database is built directly with `package:sqlite3` (its
// `user_version` pragma set to 3), then opened through [AppDatabase] so Drift
// runs `onUpgrade`. This exercises the real migration path with real data,
// mirroring `migration_v3_test.dart`.
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:visiosoil_app/core/database/app_database.dart';

void main() {
  group('migration v3 -> v4 (management tips cache)', () {
    late Directory tempDir;
    late File dbFile;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('visiosoil_mig_v4');
      dbFile = File('${tempDir.path}/visiosoil_v3.db');
      _seedV3Database(dbFile.path);
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('migration_v3_to_v4_creates_management_tips_table', () async {
      final db = AppDatabase.forTesting(NativeDatabase(dbFile));
      addTearDown(db.close);

      // Force the migration to run before inspecting the schema.
      await db.customSelect('SELECT 1').get();

      final tables = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type = 'table' "
            "AND name = 'management_tips'",
          )
          .get();

      expect(
        tables,
        isNotEmpty,
        reason: 'management_tips table must exist after the v4 migration',
      );
    });

    test('migration_v3_to_v4_preserves_existing_soil_records', () async {
      final db = AppDatabase.forTesting(NativeDatabase(dbFile));
      addTearDown(db.close);

      final rows = await db
          .customSelect('SELECT image_path FROM soil_records ORDER BY id')
          .get();

      expect(
        rows.map((r) => r.read<String>('image_path')).toList(),
        ['/legacy-a.jpg', '/legacy-b.jpg'],
        reason: 'both v3 rows must survive the v4 migration',
      );
    });
  });
}

/// Creates a v3-shaped database (sync foundation already applied) with two rows
/// and stamps `user_version` to 3 so Drift runs only the v3 -> v4 step.
void _seedV3Database(String path) {
  final raw = sqlite3.open(path);
  try {
    raw.execute('''
      CREATE TABLE soil_records (
        id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
        uuid TEXT NOT NULL,
        remote_id TEXT,
        sync_status TEXT NOT NULL DEFAULT 'pending',
        image_path TEXT NOT NULL,
        latitude REAL,
        longitude REAL,
        address TEXT,
        timestamp TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted INTEGER NOT NULL DEFAULT 0,
        texture_class TEXT,
        confidence_score REAL
      );
    ''');
    raw.execute(
      'CREATE UNIQUE INDEX idx_soil_records_uuid ON soil_records (uuid);',
    );
    raw.execute('''
      CREATE TABLE sync_queue (
        id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
        record_uuid TEXT NOT NULL,
        operation TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'pending',
        created_at TEXT NOT NULL
      );
    ''');
    raw.execute(
      "INSERT INTO soil_records (uuid, image_path, timestamp, updated_at) "
      "VALUES ('uuid-a', '/legacy-a.jpg', '2026-01-01T00:00:00.000Z', "
      "'2026-01-01T00:00:00.000Z');",
    );
    raw.execute(
      "INSERT INTO soil_records (uuid, image_path, timestamp, updated_at) "
      "VALUES ('uuid-b', '/legacy-b.jpg', '2026-02-02T00:00:00.000Z', "
      "'2026-02-02T00:00:00.000Z');",
    );
    raw.execute('PRAGMA user_version = 3;');
  } finally {
    raw.dispose();
  }
}
