// Migration tests for schema v1 -> v2 (texture classification columns).
//
// A v1-shaped database is built directly with `package:sqlite3` (its
// `user_version` pragma set to 1), then opened through [AppDatabase] so Drift
// runs `onUpgrade`. This exercises the real migration path with real data,
// mirroring `migration_v3_test.dart` and `migration_v4_test.dart`.
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:visiosoil_app/core/database/app_database.dart';

void main() {
  group('migration v1 -> v2 (texture classification columns)', () {
    late Directory tempDir;
    late File dbFile;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('visiosoil_mig_v2');
      dbFile = File('${tempDir.path}/visiosoil_v1.db');
      _seedV1Database(dbFile.path);
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('v1_to_v2_migration_adds_texture_class_and_confidence_score_columns',
        () async {
      final db = AppDatabase.forTesting(NativeDatabase(dbFile));
      addTearDown(db.close);

      // Force the migration to run before inspecting the schema.
      await db.customSelect('SELECT 1').get();

      final columns =
          await db.customSelect("PRAGMA table_info('soil_records')").get();
      final names = columns.map((r) => r.read<String>('name')).toList();

      expect(
        names,
        containsAll(<String>['texture_class', 'confidence_score']),
        reason: 'the v2 migration must add both classification columns',
      );
    });

    test('v1_to_v2_migration_preserves_a_pre_existing_row', () async {
      final db = AppDatabase.forTesting(NativeDatabase(dbFile));
      addTearDown(db.close);

      final rows = await db
          .customSelect(
            'SELECT image_path, texture_class, confidence_score '
            'FROM soil_records ORDER BY id',
          )
          .get();

      expect(rows.length, 1, reason: 'the pre-existing row must survive');
      expect(rows.single.read<String>('image_path'), '/legacy-a.jpg');
      expect(
        rows.single.readNullable<String>('texture_class'),
        isNull,
        reason: 'the added column defaults to null for legacy rows',
      );
      expect(
        rows.single.readNullable<double>('confidence_score'),
        isNull,
        reason: 'the added column defaults to null for legacy rows',
      );
    });
  });
}

/// Creates a v1-shaped `soil_records` table (before the texture classification
/// columns) with a single row and stamps `user_version` to 1 so Drift runs the
/// v1 -> v2 step of `onUpgrade`.
void _seedV1Database(String path) {
  final raw = sqlite3.open(path);
  try {
    raw.execute('''
      CREATE TABLE soil_records (
        id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
        image_path TEXT NOT NULL,
        latitude REAL,
        longitude REAL,
        address TEXT,
        timestamp TEXT NOT NULL
      );
    ''');
    raw.execute(
      "INSERT INTO soil_records (image_path, timestamp) "
      "VALUES ('/legacy-a.jpg', '2026-01-01T00:00:00.000Z');",
    );
    raw.execute('PRAGMA user_version = 1;');
  } finally {
    raw.dispose();
  }
}
