// Migration tests for schema v10 -> v11 (the true class, SPEC 0220).
//
// A v10-shaped database is built directly with `package:sqlite3` (its
// `user_version` pragma set to 10), then opened through [AppDatabase] so Drift
// runs `onUpgrade`. Mirrors `migration_v10_test.dart`.
//
// The column is nullable. A live record whose label names one of the model's
// classes gets that class; every other row, tombstones included, gets none,
// and every label is left as it was.
import 'dart:io';

import 'package:drift/drift.dart' show QueryRow, Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:visiosoil_app/core/database/app_database.dart';

void main() {
  group('migration v10 -> v11 (true class)', () {
    late Directory tempDir;
    late File dbFile;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('visiosoil_mig_v11');
      dbFile = File('${tempDir.path}/visiosoil_v10.db');
      _seedV10Database(dbFile.path);
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

    test('schema_version_is_eleven', () {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);

      expect(db.schemaVersion, 11);
    });

    test('migration_v11_adds_the_true_class', () async {
      final db = AppDatabase.forTesting(NativeDatabase(dbFile));
      addTearDown(db.close);

      for (final uuid in ['uuid-unlabelled', 'uuid-plain-label']) {
        final stored = await row(db, uuid);
        expect(stored.read<String?>('true_texture_class'), isNull,
            reason: uuid);
      }

      // Every other column keeps its value.
      final plain = await row(db, 'uuid-plain-label');
      expect(plain.read<String?>('field_name'), 'Talhão 3');
      expect(plain.read<String?>('texture_class'), 'Argilosa');
      expect(plain.read<String?>('classification_failure'), isNull);

      final version = await db.customSelect('PRAGMA user_version').getSingle();
      expect(version.read<int>('user_version'), 11);
    });

    test('migration_v11_backfills_a_class_from_the_labels', () async {
      final db = AppDatabase.forTesting(NativeDatabase(dbFile));
      addTearDown(db.close);

      final field = await row(db, 'uuid-field-argilosa');
      expect(field.read<String?>('true_texture_class'), 'Argilosa');
      expect(field.read<String?>('field_name'), ' argilosa ');

      final media = await row(db, 'uuid-sample-media');
      expect(media.read<String?>('true_texture_class'), 'Media');
      expect(media.read<String?>('sample_label'), 'Média');

      final muito = await row(db, 'uuid-sample-muito');
      expect(muito.read<String?>('true_texture_class'), 'Muito Argilosa');
      expect(muito.read<String?>('sample_label'), 'Muito Argilosa');

      // Both labels naming the same class is no conflict.
      final both = await row(db, 'uuid-both-same');
      expect(both.read<String?>('true_texture_class'), 'Arenosa');
    });

    test('migration_v11_leaves_conflicting_labels_alone', () async {
      final db = AppDatabase.forTesting(NativeDatabase(dbFile));
      addTearDown(db.close);

      final stored = await row(db, 'uuid-conflict');
      expect(stored.read<String?>('true_texture_class'), isNull);
      expect(stored.read<String?>('field_name'), 'Arenosa');
      expect(stored.read<String?>('sample_label'), 'Argilosa');
    });

    test('migration_v11_skips_tombstones', () async {
      final db = AppDatabase.forTesting(NativeDatabase(dbFile));
      addTearDown(db.close);

      final stored = await row(db, 'uuid-deleted');
      expect(stored.read<String?>('true_texture_class'), isNull);
    });

    test('migration_v11_enqueues_nothing', () async {
      final db = AppDatabase.forTesting(NativeDatabase(dbFile));
      addTearDown(db.close);

      final queue = await db.customSelect('SELECT * FROM sync_queue').get();
      expect(queue, isEmpty);
    });
  });
}

/// Creates a v10-shaped database holding labelled, unlabelled, conflicting
/// and tombstoned records, and stamps `user_version` to 10 so Drift runs only
/// the v10 -> v11 step.
void _seedV10Database(String path) {
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
        classification_failure TEXT
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
    void insert(
      String uuid, {
      String? fieldName,
      String? sampleLabel,
      bool deleted = false,
    }) {
      raw.execute(
        'INSERT INTO soil_records (uuid, image_path, timestamp, updated_at, '
        'deleted, texture_class, field_name, sample_label) VALUES '
        "(?, '/img.jpg', '2026-01-01T09:30:00.000Z', "
        "'2026-01-01T12:00:00.000Z', ?, 'Argilosa', ?, ?);",
        [uuid, deleted ? 1 : 0, fieldName, sampleLabel],
      );
    }

    insert('uuid-unlabelled');
    insert('uuid-plain-label', fieldName: 'Talhão 3', sampleLabel: '12');
    insert('uuid-field-argilosa', fieldName: ' argilosa ');
    insert('uuid-sample-media', sampleLabel: 'Média');
    insert('uuid-sample-muito', sampleLabel: 'Muito Argilosa');
    insert('uuid-both-same', fieldName: 'arenosa', sampleLabel: 'Arenosa');
    insert('uuid-conflict', fieldName: 'Arenosa', sampleLabel: 'Argilosa');
    insert('uuid-deleted', fieldName: 'Argilosa', deleted: true);
    raw.execute('PRAGMA user_version = 10;');
  } finally {
    raw.dispose();
  }
}
