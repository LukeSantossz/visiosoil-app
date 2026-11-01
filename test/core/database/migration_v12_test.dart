// Migration tests for schema v11 -> v12 (the capture conditions, SPEC 0240).
//
// A v11-shaped database is built directly with `package:sqlite3` (its
// `user_version` pragma set to 11), then opened through [AppDatabase] so Drift
// runs `onUpgrade`. Mirrors `migration_v11_test.dart`.
//
// The three columns are nullable: every row, tombstones included, arrives
// with none, and nothing is enqueued.
import 'dart:io';

import 'package:drift/drift.dart' show QueryRow, Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:visiosoil_app/core/database/app_database.dart';

void main() {
  group('migration v11 -> v12 (capture conditions)', () {
    late Directory tempDir;
    late File dbFile;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('visiosoil_mig_v12');
      dbFile = File('${tempDir.path}/visiosoil_v11.db');
      _seedV11Database(dbFile.path);
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    Future<QueryRow> row(AppDatabase db, String uuid) => db
        .customSelect(
          'SELECT * FROM soil_records WHERE uuid = ?',
          variables: [Variable.withString(uuid)],
        )
        .getSingle();

    test('schema_version_is_twelve', () {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);

      expect(db.schemaVersion, 12);
    });

    test('migrates_v11_to_v12_with_null_conditions', () async {
      final db = AppDatabase.forTesting(NativeDatabase(dbFile));
      addTearDown(db.close);

      for (final uuid in ['uuid-live', 'uuid-deleted']) {
        final stored = await row(db, uuid);
        expect(stored.read<double?>('capture_lux'), isNull, reason: uuid);
        expect(
          stored.read<double?>('capture_distance_mm'),
          isNull,
          reason: uuid,
        );
        expect(stored.read<bool?>('capture_sharp'), isNull, reason: uuid);
      }

      // Every other column keeps its value.
      final live = await row(db, 'uuid-live');
      expect(live.read<String?>('texture_class'), 'Argilosa');
      expect(live.read<double?>('horizontal_accuracy'), 4.2);
      expect(live.read<String?>('sample_label'), 'A1');
      expect(live.read<String?>('true_texture_class'), 'Media');

      final version = await db.customSelect('PRAGMA user_version').getSingle();
      expect(version.read<int>('user_version'), 12);

      final queue = await db.customSelect('SELECT * FROM sync_queue').get();
      expect(queue, isEmpty);
    });
  });
}

/// Creates a v11-shaped database holding a live record and a tombstone, and
/// stamps `user_version` to 11 so Drift runs only the v11 -> v12 step.
void _seedV11Database(String path) {
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
        confidence_score REAL,
        class_distribution TEXT,
        model_version TEXT,
        dataset_version TEXT,
        horizontal_accuracy REAL,
        field_name TEXT,
        sample_label TEXT,
        classification_failure TEXT,
        true_texture_class TEXT
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
    raw.execute('''
      CREATE TABLE management_tips (
        record_uuid TEXT NOT NULL PRIMARY KEY,
        payload_json TEXT NOT NULL,
        retrieved_at TEXT NOT NULL,
        corpus_version TEXT
      );
    ''');
    raw.execute(
      'INSERT INTO soil_records (uuid, image_path, timestamp, updated_at, '
      'texture_class, horizontal_accuracy, sample_label, true_texture_class) '
      "VALUES ('uuid-live', '/img.jpg', '2026-01-01T09:30:00.000Z', "
      "'2026-01-01T12:00:00.000Z', 'Argilosa', 4.2, 'A1', 'Media');",
    );
    raw.execute(
      'INSERT INTO soil_records (uuid, image_path, timestamp, updated_at, '
      "deleted) VALUES ('uuid-deleted', '', '2026-01-01T09:30:00.000Z', "
      "'2026-01-02T12:00:00.000Z', 1);",
    );
    raw.execute('PRAGMA user_version = 11;');
  } finally {
    raw.dispose();
  }
}
