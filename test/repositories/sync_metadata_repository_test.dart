// Tests for the sync metadata behavior added to [DriftSoilRecordRepository]:
// UUID assignment, outbox enqueueing, tombstone deletes, and read filtering.
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visiosoil_app/core/data/repositories/drift_soil_record_repository.dart';
import 'package:visiosoil_app/core/database/app_database.dart';
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

      expect(await repo.count(), 1);
      expect((await repo.getAll()).map((r) => r.id), [b.id]);
      expect((await repo.getLatest())?.id, b.id);
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
}
