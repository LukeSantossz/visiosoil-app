// Migration tests for schema v5 -> v6 (erasing the content of tombstones
// written before SPEC 0093).
//
// A v5-shaped database is built directly with `package:sqlite3` (its
// `user_version` pragma set to 5), then opened through [AppDatabase] so Drift
// runs `onUpgrade`. Mirrors `migration_v5_test.dart`.
//
// The step changes no table's shape. It applies to old tombstones the scrub a
// delete now performs: a tombstone keeps only what sync reads.
import 'dart:io';

import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:visiosoil_app/core/database/app_database.dart';

void main() {
  group('migration v5 -> v6 (erase tombstone content)', () {
    late Directory tempDir;
    late File dbFile;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('visiosoil_mig_v6');
      dbFile = File('${tempDir.path}/visiosoil_v5.db');
      _seedV5Database(dbFile.path);
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('schema_version_is_six', () {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);

      expect(db.schemaVersion, 6);
    });

    test('migration_v5_to_v6_erases_existing_tombstones', () async {
      final db = AppDatabase.forTesting(NativeDatabase(dbFile));
      addTearDown(db.close);

      final row = await db
          .customSelect(
            'SELECT * FROM soil_records WHERE uuid = ?',
            variables: [Variable.withString('uuid-deleted')],
          )
          .getSingle();
      expect(row.read<double?>('latitude'), isNull);
      expect(row.read<double?>('longitude'), isNull);
      expect(row.read<String?>('address'), isNull);
      expect(row.read<String?>('texture_class'), isNull);
      expect(row.read<double?>('confidence_score'), isNull);
      expect(row.read<String>('image_path'), isEmpty);
      expect(row.read<String>('timestamp'), row.read<String>('updated_at'));
      // What sync reads survives.
      expect(row.read<int>('deleted'), 1);
      expect(row.read<String?>('remote_id'), 'remote-deleted');
      expect(row.read<String>('updated_at'), '2026-02-02T00:00:00.000Z');

      final tips = await db
          .customSelect(
            'SELECT record_uuid FROM management_tips WHERE record_uuid = ?',
            variables: [Variable.withString('uuid-deleted')],
          )
          .get();
      expect(tips, isEmpty);
    });

    test('migration_v5_to_v6_keeps_live_records_and_their_tips', () async {
      final db = AppDatabase.forTesting(NativeDatabase(dbFile));
      addTearDown(db.close);

      final row = await db
          .customSelect(
            'SELECT * FROM soil_records WHERE uuid = ?',
            variables: [Variable.withString('uuid-live')],
          )
          .getSingle();
      expect(row.read<double?>('latitude'), -22.9);
      expect(row.read<double?>('longitude'), -47.06);
      expect(row.read<String?>('address'), 'Fazenda Boa Vista');
      expect(row.read<String?>('texture_class'), 'Argilosa');
      expect(row.read<double?>('confidence_score'), 0.87);
      expect(row.read<String>('image_path'), '/live.jpg');
      expect(row.read<String>('timestamp'), '2026-01-01T09:30:00.000Z');

      final tips = await db
          .customSelect(
            'SELECT payload_json, corpus_version FROM management_tips '
            'WHERE record_uuid = ?',
            variables: [Variable.withString('uuid-live')],
          )
          .getSingle();
      expect(tips.read<String>('payload_json'), '{"live":true}');
      expect(tips.read<String?>('corpus_version'), 'corpus-1');
    });
  });
}

/// Creates a v5-shaped database holding one live record and one tombstone that
/// still carries its content, each with cached tips, and stamps `user_version`
/// to 5 so Drift runs only the v5 -> v6 step.
void _seedV5Database(String path) {
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
      'INSERT INTO soil_records (uuid, remote_id, image_path, latitude, '
      'longitude, address, timestamp, updated_at, deleted, texture_class, '
      'confidence_score) VALUES '
      "('uuid-deleted', 'remote-deleted', '/deleted.jpg', -23.5, -46.6, "
      "'Sítio Santa Luzia', '2026-01-15T08:00:00.000Z', "
      "'2026-02-02T00:00:00.000Z', 1, 'Arenosa', 0.61);",
    );
    raw.execute(
      'INSERT INTO management_tips (record_uuid, payload_json, retrieved_at, '
      "corpus_version) VALUES ('uuid-live', '{\"live\":true}', "
      "'2026-01-01T12:00:00.000Z', 'corpus-1');",
    );
    raw.execute(
      'INSERT INTO management_tips (record_uuid, payload_json, retrieved_at, '
      "corpus_version) VALUES ('uuid-deleted', '{\"deleted\":true}', "
      "'2026-01-15T08:00:00.000Z', 'corpus-1');",
    );
    raw.execute('PRAGMA user_version = 5;');
  } finally {
    raw.dispose();
  }
}
