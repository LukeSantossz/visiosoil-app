// Migration tests for schema v4 -> v5 (the corpus version the cache answered
// with).
//
// A v4-shaped database is built directly with `package:sqlite3` (its
// `user_version` pragma set to 4), then opened through [AppDatabase] so Drift
// runs `onUpgrade`. Mirrors `migration_v4_test.dart`.
//
// The column is nullable rather than defaulted on purpose: a row cached before
// v5 genuinely has no known version, and a fabricated default would claim
// currency the row does not have.
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:visiosoil_app/core/database/app_database.dart';

void main() {
  group('migration v4 -> v5 (corpus version)', () {
    late Directory tempDir;
    late File dbFile;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('visiosoil_mig_v5');
      dbFile = File('${tempDir.path}/visiosoil_v4.db');
      _seedV4Database(dbFile.path);
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('schema_version_is_five', () {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);

      expect(db.schemaVersion, 5);
    });

    test('migration_v4_to_v5_adds_the_corpus_version_column', () async {
      final db = AppDatabase.forTesting(NativeDatabase(dbFile));
      addTearDown(db.close);
      await db.customSelect('SELECT 1').get();

      final columns =
          await db.customSelect("PRAGMA table_info('management_tips')").get();

      expect(
        columns.map((r) => r.read<String>('name')),
        contains('corpus_version'),
      );
    });

    test('v4_database_migrates_with_its_rows_intact', () async {
      final db = AppDatabase.forTesting(NativeDatabase(dbFile));
      addTearDown(db.close);

      final rows = await db
          .customSelect(
            'SELECT record_uuid, payload_json, retrieved_at '
            'FROM management_tips ORDER BY record_uuid',
          )
          .get();

      expect(rows.map((r) => r.read<String>('record_uuid')).toList(),
          ['uuid-a', 'uuid-b']);
      expect(rows.first.read<String>('payload_json'), contains('legacy-a'));
      expect(rows.first.read<String>('retrieved_at'),
          '2026-01-01T00:00:00.000Z');
    });

    test('a_pre_v5_row_has_a_null_corpus_version', () async {
      final db = AppDatabase.forTesting(NativeDatabase(dbFile));
      addTearDown(db.close);

      final rows = await db
          .customSelect('SELECT corpus_version FROM management_tips')
          .get();

      // Null, not an empty string: an empty string is a value, and a pre-v5 row
      // would then claim to have been produced by a corpus named "".
      for (final row in rows) {
        expect(row.read<String?>('corpus_version'), isNull);
      }
    });

    test('a_database_older_than_v4_reaches_v5_without_a_duplicate_column',
        () async {
      // The v4 step calls `createTable`, which builds the table from today's
      // definition — so a pre-v4 database already has `corpus_version` when the
      // v5 step runs. Adding it again is a `duplicate column name` error, and
      // this is the path that proves the guard.
      final v3File = File('${tempDir.path}/visiosoil_v3.db');
      _seedV3Database(v3File.path);

      final db = AppDatabase.forTesting(NativeDatabase(v3File));
      addTearDown(db.close);

      final columns =
          await db.customSelect("PRAGMA table_info('management_tips')").get();
      final names = columns.map((r) => r.read<String>('name')).toList();

      expect(names, contains('corpus_version'));
      expect(names.where((n) => n == 'corpus_version'), hasLength(1));
    });

    test('migration_v4_to_v5_preserves_existing_soil_records', () async {
      final db = AppDatabase.forTesting(NativeDatabase(dbFile));
      addTearDown(db.close);

      final rows = await db
          .customSelect('SELECT image_path FROM soil_records ORDER BY id')
          .get();

      expect(rows.map((r) => r.read<String>('image_path')).toList(),
          ['/legacy-a.jpg']);
    });
  });
}

/// Creates a v4-shaped database with two cached tips rows and stamps
/// `user_version` to 4 so Drift runs only the v4 -> v5 step.
void _seedV4Database(String path) {
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
        retrieved_at TEXT NOT NULL
      );
    ''');
    raw.execute(
      "INSERT INTO soil_records (uuid, image_path, timestamp, updated_at) "
      "VALUES ('uuid-a', '/legacy-a.jpg', '2026-01-01T00:00:00.000Z', "
      "'2026-01-01T00:00:00.000Z');",
    );
    raw.execute(
      "INSERT INTO management_tips (record_uuid, payload_json, retrieved_at) "
      "VALUES ('uuid-a', '{\"legacy-a\":true}', '2026-01-01T00:00:00.000Z');",
    );
    raw.execute(
      "INSERT INTO management_tips (record_uuid, payload_json, retrieved_at) "
      "VALUES ('uuid-b', '{\"legacy-b\":true}', '2026-02-02T00:00:00.000Z');",
    );
    raw.execute('PRAGMA user_version = 4;');
  } finally {
    raw.dispose();
  }
}

/// Creates a v3-shaped database — no `management_tips` table at all — so the
/// upgrade runs the v4 create *and* the v5 step in one pass.
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
    raw.execute('PRAGMA user_version = 3;');
  } finally {
    raw.dispose();
  }
}
