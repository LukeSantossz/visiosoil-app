// Tests for the sync metadata behavior added to [DriftSoilRecordRepository]:
// UUID assignment, outbox enqueueing, tombstone deletes, and read filtering.
import 'dart:io';

import 'package:drift/drift.dart' show QueryRow, Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visiosoil_app/core/data/repositories/drift_soil_record_repository.dart';
import 'package:visiosoil_app/core/database/app_database.dart';
import 'package:visiosoil_app/models/class_score.dart';
import 'package:visiosoil_app/models/soil_record.dart';

import '../support/fake_image_storage_service.dart';

void main() {
  group('DriftSoilRecordRepository sync metadata', () {
    late AppDatabase db;
    late DriftSoilRecordRepository repo;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      repo = DriftSoilRecordRepository(db, imageStorage: FakeImageStorageService());
    });

    tearDown(() async {
      await db.close();
    });

    SoilRecord sample({String imagePath = '/img.jpg'}) => SoilRecord(
          imagePath: imagePath,
          timestamp: DateTime.utc(2026, 1, 1).toIso8601String(),
        );

    final uuidV4Pattern = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    );

    test('create_assigns_uuid_v4_and_sets_sync_metadata', () async {
      final saved = await repo.create(sample());

      expect(saved.uuid, isNotNull);
      expect(uuidV4Pattern.hasMatch(saved.uuid!), isTrue);
      expect(saved.syncStatus, 'pending');
      expect(saved.updatedAt, isNotNull);
      expect(saved.deleted, isFalse);
    });

    test('create_enqueues_a_pending_upsert_operation', () async {
      final saved = await repo.create(sample());

      final ops = await db
          .customSelect('SELECT record_uuid, operation, status FROM sync_queue')
          .get();

      expect(ops.length, 1);
      expect(ops.single.read<String>('record_uuid'), saved.uuid);
      expect(ops.single.read<String>('operation'), 'upsert');
      expect(ops.single.read<String>('status'), 'pending');
    });

    test('delete_by_id_writes_tombstone_and_enqueues_delete', () async {
      final saved = await repo.create(sample());

      await repo.deleteById(saved.id!);

      // The row is NOT physically removed; it carries a tombstone.
      final raw = await db
          .customSelect(
            'SELECT deleted, updated_at FROM soil_records WHERE id = ${saved.id}',
          )
          .getSingle();
      expect(raw.read<int>('deleted'), 1);

      // A delete operation is enqueued for the record's uuid.
      final ops = await db
          .customSelect(
            "SELECT operation FROM sync_queue WHERE record_uuid = '${saved.uuid}'",
          )
          .get();
      expect(ops.map((o) => o.read<String>('operation')), contains('delete'));

      // Read paths hide the tombstoned record.
      expect(await repo.getById(saved.id!), isNull);
    });

    test('tombstoned_records_are_excluded_from_reads', () async {
      final a = await repo.create(sample(imagePath: '/a.jpg'));
      final b = await repo.create(sample(imagePath: '/b.jpg'));

      await repo.deleteById(a.id!);

      expect((await repo.getAll()).map((r) => r.id), [b.id]);
      final filtered = await repo.watchFiltered().first;
      expect(filtered.map((r) => r.id), [b.id]);
    });

    test('outbox_persists_pending_operations_across_reopen', () async {
      final dir = Directory.systemTemp.createTempSync('visiosoil_outbox');
      final file = File('${dir.path}/db.sqlite');
      addTearDown(() => dir.deleteSync(recursive: true));

      var openDb = AppDatabase.forTesting(NativeDatabase(file));
      await DriftSoilRecordRepository(openDb, imageStorage: FakeImageStorageService())
          .create(sample());
      await openDb.close();

      openDb = AppDatabase.forTesting(NativeDatabase(file));
      addTearDown(openDb.close);
      final ops = await openDb.customSelect('SELECT id FROM sync_queue').get();
      expect(ops.length, 1);
    });
  });

  // A tombstone keeps only what sync reads; everything the user captured is
  // erased when the record is deleted (SPEC 0093).
  group('DriftSoilRecordRepository tombstone erasure', () {
    late AppDatabase db;
    late DriftSoilRecordRepository repo;
    late DateTime now;

    const createdAt = '2026-01-01T12:00:00.000Z';
    const deletedAt = '2026-03-04T05:06:07.000Z';

    setUp(() {
      now = DateTime.parse(createdAt);
      db = AppDatabase.forTesting(NativeDatabase.memory());
      repo = DriftSoilRecordRepository(
        db,
        clock: () => now,
        imageStorage: FakeImageStorageService(),
      );
    });

    tearDown(() async {
      await db.close();
    });

    SoilRecord captured({String address = 'Fazenda Boa Vista'}) => SoilRecord(
          imagePath: '/img.jpg',
          latitude: -22.9,
          longitude: -47.06,
          address: address,
          timestamp: '2026-01-01T09:30:00.000Z',
          textureClass: 'Argilosa',
          confidenceScore: 0.87,
          classDistribution: const [
            ClassScore(label: 'Arenosa', probability: 0.03),
            ClassScore(label: 'Media', probability: 0.06),
            ClassScore(label: 'Muito Argilosa', probability: 0.04),
            ClassScore(label: 'Argilosa', probability: 0.87),
          ],
          modelVersion: '1.0.0',
          datasetVersion: 'v1',
        );

    Future<QueryRow> storedRow(String uuid) => db
        .customSelect(
          'SELECT * FROM soil_records WHERE uuid = ?',
          variables: [Variable.withString(uuid)],
        )
        .getSingle();

    void expectErased(QueryRow row) {
      expect(row.read<double?>('latitude'), isNull);
      expect(row.read<double?>('longitude'), isNull);
      expect(row.read<String?>('address'), isNull);
      expect(row.read<String?>('texture_class'), isNull);
      expect(row.read<double?>('confidence_score'), isNull);
      // SPEC 0097: what scored the photograph describes it, too.
      expect(row.read<String?>('class_distribution'), isNull);
      expect(row.read<String?>('model_version'), isNull);
      expect(row.read<String?>('dataset_version'), isNull);
      expect(row.read<String>('image_path'), isEmpty);
      expect(row.read<String>('timestamp'), row.read<String>('updated_at'));
    }

    Future<void> cacheTips(String uuid) => db.customStatement(
          'INSERT INTO management_tips (record_uuid, payload_json, retrieved_at) '
          "VALUES (?, '{}', ?)",
          [uuid, createdAt],
        );

    test('delete_by_id_erases_the_record_content', () async {
      final saved = await repo.create(captured());
      now = DateTime.parse(deletedAt);

      await repo.deleteById(saved.id!);

      expectErased(await storedRow(saved.uuid!));
    });

    test('a_deleted_record_erases_its_distribution_and_versions', () async {
      final saved = await repo.create(captured());
      // Guards the test: the columns held something to erase.
      final before = await storedRow(saved.uuid!);
      expect(before.read<String?>('class_distribution'), isNotNull);
      expect(before.read<String?>('model_version'), '1.0.0');
      now = DateTime.parse(deletedAt);

      await repo.deleteById(saved.id!);

      final row = await storedRow(saved.uuid!);
      expect(row.read<String?>('class_distribution'), isNull);
      expect(row.read<String?>('model_version'), isNull);
      expect(row.read<String?>('dataset_version'), isNull);
    });

    test('delete_keeps_what_sync_reads', () async {
      final saved = await repo.create(captured());
      now = DateTime.parse(deletedAt);

      await repo.deleteById(saved.id!);

      final row = await storedRow(saved.uuid!);
      expect(row.read<String>('uuid'), saved.uuid);
      expect(row.read<int>('deleted'), 1);
      expect(row.read<String>('sync_status'), 'pending');
      expect(row.read<String>('updated_at'), deletedAt);
      final ops = await db
          .customSelect(
            'SELECT operation FROM sync_queue WHERE record_uuid = ?',
            variables: [Variable.withString(saved.uuid!)],
          )
          .get();
      expect(ops.map((o) => o.read<String>('operation')), contains('delete'));
    });

    test('delete_by_ids_erases_only_the_selected_records', () async {
      final a = await repo.create(captured(address: 'A'));
      final b = await repo.create(captured(address: 'B'));
      final kept = await repo.create(captured(address: 'Kept'));

      await repo.deleteByIds([a.id!, b.id!]);

      expectErased(await storedRow(a.uuid!));
      expectErased(await storedRow(b.uuid!));
      final untouched = await storedRow(kept.uuid!);
      expect(untouched.read<double?>('latitude'), -22.9);
      expect(untouched.read<double?>('longitude'), -47.06);
      expect(untouched.read<String?>('address'), 'Kept');
      expect(untouched.read<String?>('texture_class'), 'Argilosa');
      expect(untouched.read<double?>('confidence_score'), 0.87);
      expect(untouched.read<String>('image_path'), isNotEmpty);
      expect(untouched.read<String>('timestamp'), '2026-01-01T09:30:00.000Z');
    });

    test('delete_all_erases_every_record', () async {
      await repo.create(captured(address: 'A'));
      await repo.create(captured(address: 'B'));

      await repo.deleteAll();

      final holding = await db
          .customSelect(
            'SELECT id FROM soil_records WHERE latitude IS NOT NULL '
            'OR longitude IS NOT NULL OR address IS NOT NULL '
            'OR texture_class IS NOT NULL OR confidence_score IS NOT NULL',
          )
          .get();
      expect(holding, isEmpty);
      final rows = await db.customSelect('SELECT uuid FROM soil_records').get();
      expect(rows, hasLength(2));
    });

    test('delete_removes_the_record_cached_tips', () async {
      final deleted = await repo.create(captured(address: 'Deleted'));
      final kept = await repo.create(captured(address: 'Kept'));
      await cacheTips(deleted.uuid!);
      await cacheTips(kept.uuid!);

      await repo.deleteById(deleted.id!);

      final tips = await db
          .customSelect('SELECT record_uuid FROM management_tips')
          .get();
      expect(tips.map((t) => t.read<String>('record_uuid')), [kept.uuid]);
    });
  });
}
