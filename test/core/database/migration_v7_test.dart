// Migration tests for schema v6 -> v7 (the class distribution and the contract
// versions a classification was scored with, SPEC 0097).
//
// A v6-shaped database is built directly with `package:sqlite3` (its
// `user_version` pragma set to 6), then opened through [AppDatabase] so Drift
// runs `onUpgrade`. Mirrors `migration_v6_test.dart`.
//
// The three columns are nullable and arrive NULL on every existing row: a
// record saved before v7 never had them, and a tombstone keeps only what sync
// reads, so neither may be given a value it never had.
import 'dart:io';

import 'package:drift/drift.dart' show QueryRow, Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:visiosoil_app/core/database/app_database.dart';

void main() {
  group('migration v6 -> v7 (class distribution and contract versions)', () {
    late Directory tempDir;
    late File dbFile;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('visiosoil_mig_v7');
      dbFile = File('${tempDir.path}/visiosoil_v6.db');
      _seedV6Database(dbFile.path);
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('schema_version_is_seven', () {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);

      expect(db.schemaVersion, 7);
    });

    test('migration_v6_to_v7_adds_the_columns_as_null', () async {
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
        expect(stored.read<String?>('class_distribution'), isNull, reason: uuid);
        expect(stored.read<String?>('model_version'), isNull, reason: uuid);
        expect(stored.read<String?>('dataset_version'), isNull, reason: uuid);
      }

      // Every other column keeps its value.
      final live = await row('uuid-live');
      expect(live.read<String?>('address'), 'Fazenda Boa Vista');
      expect(live.read<String?>('texture_class'), 'Argilosa');
      expect(live.read<double?>('confidence_score'), 0.87);
      expect(live.read<String>('image_path'), '/live.jpg');
      final deleted = await row('uuid-deleted');
      expect(deleted.read<String>('image_path'), isEmpty);
      expect(deleted.read<String?>('remote_id'), 'remote-deleted');

      // The upgrade itself stamps the new version on the file.
      final version =
          await db.customSelect('PRAGMA user_version').getSingle();
      expect(version.read<int>('user_version'), 7);
    });
  });
}

/// Creates a v6-shaped database holding one live record and one tombstone that
/// SPEC 0093 already erased, and stamps `user_version` to 6 so Drift runs only
/// the v6 -> v7 step.
void _seedV6Database(String path) {
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
      'confidence_score) VALUES '
      "('uuid-live', '/live.jpg', -22.9, -47.06, 'Fazenda Boa Vista', "
      "'2026-01-01T09:30:00.000Z', '2026-01-01T12:00:00.000Z', 0, "
      "'Argilosa', 0.87);",
    );
    raw.execute(
      'INSERT INTO soil_records (uuid, remote_id, image_path, timestamp, '
      'updated_at, deleted) VALUES '
      "('uuid-deleted', 'remote-deleted', '', '2026-02-02T00:00:00.000Z', "
      "'2026-02-02T00:00:00.000Z', 1);",
    );
    raw.execute('PRAGMA user_version = 6;');
  } finally {
    raw.dispose();
  }
}
