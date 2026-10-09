// Migration tests for schema v8 -> v9 (a record's field and sample labels,
// SPEC 0149).
//
// A v8-shaped database is built directly with `package:sqlite3` (its
// `user_version` pragma set to 8), then opened through [AppDatabase] so Drift
// runs `onUpgrade`. Mirrors `migration_v8_test.dart`.
//
// The columns are nullable and arrive NULL on every existing row: a record
// saved before v9 was never labelled, and a tombstone keeps only what sync
// reads, so neither may be given a label it never had.
import 'dart:io';

import 'package:drift/drift.dart' show QueryRow, Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:visiosoil_app/core/database/app_database.dart';

void main() {
  group('migration v8 -> v9 (field and sample labels)', () {
    late Directory tempDir;
    late File dbFile;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('visiosoil_mig_v9');
      dbFile = File('${tempDir.path}/visiosoil_v8.db');
      _seedV8Database(dbFile.path);
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('schema_version_is_nine', () {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);

      expect(db.schemaVersion, 9);
    });

    test('migration_v8_to_v9_adds_the_columns_as_null', () async {
      final db = AppDatabase.forTesting(NativeDatabase(dbFile));
      addTearDown(db.close);

      Future<QueryRow> row(String uuid) => db
          .customSelect(
            'SELECT * FROM soil_records WHERE uuid = ?',
            variables: [Variable.withString(uuid)],
          )
          .getSingle();

      for (final uuid in ['uuid-live', 'uuid-deleted']) {
        final stored = await row(uuid);
        expect(stored.read<String?>('field_name'), isNull, reason: uuid);
        expect(stored.read<String?>('sample_label'), isNull, reason: uuid);
      }

      // Every other column keeps its value.
      final live = await row('uuid-live');
      expect(live.read<double?>('latitude'), -22.9);
      expect(live.read<double?>('longitude'), -47.06);
      expect(live.read<String?>('address'), 'Fazenda Boa Vista');
      expect(live.read<String?>('texture_class'), 'Argilosa');
      expect(live.read<double?>('confidence_score'), 0.87);
      expect(live.read<String?>('model_version'), '1.0.0');
      expect(live.read<String?>('dataset_version'), 'v1');
      expect(live.read<double?>('horizontal_accuracy'), 4.2);
      expect(live.read<String>('image_path'), '/live.jpg');
      final deleted = await row('uuid-deleted');
      expect(deleted.read<String>('image_path'), isEmpty);
      expect(deleted.read<String?>('remote_id'), 'remote-deleted');

      // The upgrade itself stamps the new version on the file.
      final version =
          await db.customSelect('PRAGMA user_version').getSingle();
      expect(version.read<int>('user_version'), 9);
    });
  });
}

/// Creates a v8-shaped database holding one live record and one erased
/// tombstone, and stamps `user_version` to 8 so Drift runs only the v8 -> v9
/// step.
void _seedV8Database(String path) {
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
        horizontal_accuracy REAL
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
      'INSERT INTO soil_records (uuid, image_path, latitude, longitude, '
      'address, timestamp, updated_at, deleted, texture_class, '
      'confidence_score, model_version, dataset_version, '
      'horizontal_accuracy) VALUES '
      "('uuid-live', '/live.jpg', -22.9, -47.06, 'Fazenda Boa Vista', "
      "'2026-01-01T09:30:00.000Z', '2026-01-01T12:00:00.000Z', 0, "
      "'Argilosa', 0.87, '1.0.0', 'v1', 4.2);",
    );
    raw.execute(
      'INSERT INTO soil_records (uuid, remote_id, image_path, timestamp, '
      'updated_at, deleted) VALUES '
      "('uuid-deleted', 'remote-deleted', '', '2026-02-02T00:00:00.000Z', "
      "'2026-02-02T00:00:00.000Z', 1);",
    );
    raw.execute('PRAGMA user_version = 8;');
  } finally {
    raw.dispose();
  }
}
