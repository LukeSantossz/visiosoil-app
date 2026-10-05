// Tests for the backend-agnostic [SyncEngine]: outbox draining, last-write-wins
// by `updated_at`, and delete-wins tombstone semantics. The engine runs against
// a real in-memory database and an in-memory [RemoteSyncBackend] fake.
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visiosoil_app/core/data/repositories/drift_soil_record_repository.dart';
import 'package:visiosoil_app/core/data/sync/remote_sync_backend.dart';
import 'package:visiosoil_app/core/data/sync/sync_local_store.dart';
import 'package:visiosoil_app/core/database/app_database.dart';
import 'package:visiosoil_app/core/services/sync_engine.dart';
import 'package:visiosoil_app/models/soil_record.dart';

import '../support/fake_image_storage_service.dart';

class _FakeBackend implements RemoteSyncBackend {
  final List<SoilRecord> pushed = [];
  final List<SoilRecord> deleted = [];
  List<SoilRecord> toPull = [];

  @override
  Future<String> pushRecord(SoilRecord record) async {
    pushed.add(record);
    return 'remote-${record.uuid}';
  }

  @override
  Future<void> deleteRecord(SoilRecord record) async => deleted.add(record);

  @override
  Future<List<SoilRecord>> pullRecords() async => toPull;

  @override
  Future<String> uploadBlob(String uuid, List<int> bytes) async => 'blob-$uuid';

  @override
  Future<List<int>> downloadBlob(String remoteId) async => const <int>[];
}

void main() {
  group('SyncEngine', () {
    late AppDatabase db;
    late DriftSoilRecordRepository repo;
    late SyncLocalStore store;
    late _FakeBackend backend;
    late SyncEngine engine;

    var counter = 0;

    setUp(() {
      counter = 0;
      db = AppDatabase.forTesting(NativeDatabase.memory());
      repo = DriftSoilRecordRepository(
        db,
        uuidFactory: () => 'uuid-${++counter}',
        clock: () => DateTime.utc(2026, 1, 1, 12),
        imageStorage: FakeImageStorageService(),
      );
      store = SyncLocalStore(db);
      backend = _FakeBackend();
      engine = SyncEngine(localStore: store, backend: backend);
    });

    tearDown(() async {
      await db.close();
    });

    SoilRecord sample({String address = 'Local'}) => SoilRecord(
          imagePath: '/img.jpg',
          address: address,
          timestamp: DateTime.utc(2026, 1, 1).toIso8601String(),
        );

    test('sync_engine_drains_outbox_against_fake_backend', () async {
      final a = await repo.create(sample());
      final b = await repo.create(sample());

      await engine.sync();

      expect(
        backend.pushed.map((r) => r.uuid),
        containsAll(<String?>[a.uuid, b.uuid]),
      );
      expect(await store.pendingOperations(), isEmpty);
    });

    test('sync_engine_applies_last_write_wins_by_updated_at', () async {
      final local = await repo.create(sample(address: 'Local'));
      backend.toPull = [
        local.copyWith(
          address: 'Remote',
          updatedAt: DateTime.utc(2026, 1, 2).toIso8601String(),
        ),
      ];

      await engine.sync();

      final merged = await store.findByUuid(local.uuid!);
      expect(merged!.address, 'Remote');
    });

    test('sync_engine_keeps_local_when_remote_is_older', () async {
      final local = await repo.create(sample(address: 'Local'));
      backend.toPull = [
        local.copyWith(
          address: 'Remote',
          updatedAt: DateTime.utc(2025, 12, 31).toIso8601String(),
        ),
      ];

      await engine.sync();

      final merged = await store.findByUuid(local.uuid!);
      expect(merged!.address, 'Local');
    });

    test('sync_engine_applies_delete_wins_tombstone', () async {
      final local = await repo.create(sample());
      // Equal timestamp, remote tombstoned -> delete wins on the tie.
      backend.toPull = [local.copyWith(deleted: true)];

      await engine.sync();

      final merged = await store.findByUuid(local.uuid!);
      expect(merged!.deleted, isTrue);
    });

    test('sync_engine_propagates_local_tombstone_as_delete', () async {
      final local = await repo.create(sample());
      await repo.deleteById(local.id!);

      await engine.sync();

      expect(backend.deleted.map((r) => r.uuid), contains(local.uuid));
    });

    // A deleted record's content never reaches a backend, and its delete still
    // does (SPEC 0093).
    test('a_scrubbed_tombstone_still_syncs_its_delete', () async {
      final local = await repo.create(SoilRecord(
        imagePath: '/img.jpg',
        latitude: -22.9,
        longitude: -47.06,
        address: 'Fazenda Boa Vista',
        timestamp: DateTime.utc(2026, 1, 1, 9, 30).toIso8601String(),
        textureClass: 'Argilosa',
        confidenceScore: 0.87,
      ));
      await repo.deleteById(local.id!);

      await engine.sync();

      final sent = backend.deleted.single;
      expect(sent.uuid, local.uuid);
      expect(sent.deleted, isTrue);
      for (final record in [...backend.pushed, ...backend.deleted]) {
        expect(record.latitude, isNull);
        expect(record.longitude, isNull);
        expect(record.address, isNull);
        expect(record.textureClass, isNull);
        expect(record.confidenceScore, isNull);
        expect(record.imagePath, isEmpty);
      }
    });

    test('sync_engine_marks_tombstone_synced_after_delete_push', () async {
      final local = await repo.create(sample());
      // Drain the create first so only the delete op remains in the outbox;
      // otherwise the upsert op would mark the record synced and mask the gap.
      await engine.sync();
      await repo.deleteById(local.id!);

      await engine.sync();

      final merged = await store.findByUuid(local.uuid!);
      expect(merged!.syncStatus, 'synced');
    });

    test('sync_engine_orders_by_utc_instant_not_lexicographically', () async {
      final local = await repo.create(sample(address: 'Local'));
      // Local updated_at is '2026-01-01T12:00:00.000Z'. The remote is stamped
      // 10:00 at -05:00, i.e. 15:00Z — a LATER instant, yet lexicographically
      // '...10:00...' sorts before '...12:00...'. UTC ordering must win.
      backend.toPull = [
        local.copyWith(
          address: 'Remote',
          updatedAt: '2026-01-01T10:00:00.000-05:00',
        ),
      ];

      await engine.sync();

      final merged = await store.findByUuid(local.uuid!);
      expect(merged!.address, 'Remote');
    });

    // A push is decided against the remote version pulled first, by the same
    // last-write-wins as the merge, so a stale local operation never reaches
    // the backend (#88, SPEC 0136).
    group('compare before push', () {
      String day(int d) => DateTime.utc(2026, 1, d).toIso8601String();

      test('stale_upsert_is_not_pushed', () async {
        final local = await repo.create(sample(address: 'Local'));
        backend.toPull = [
          local.copyWith(address: 'Remote', updatedAt: day(2)),
        ];

        await engine.sync();

        expect(backend.pushed, isEmpty);
        expect(await store.pendingOperations(), isEmpty);
        final merged = await store.findByUuid(local.uuid!);
        expect(merged!.address, 'Remote');
      });

      test('stale_delete_is_not_pushed', () async {
        final local = await repo.create(sample(address: 'Local'));
        // Drain the create, so the delete is the only pending operation.
        await engine.sync();
        await repo.deleteById(local.id!);
        backend.toPull = [
          local.copyWith(address: 'Remote edit', updatedAt: day(2)),
        ];

        await engine.sync();

        expect(backend.deleted, isEmpty);
        expect(await store.pendingOperations(), isEmpty);
        final merged = await store.findByUuid(local.uuid!);
        expect(merged!.deleted, isFalse);
        expect(merged.address, 'Remote edit');
      });

      test('newer_local_still_pushes', () async {
        final local = await repo.create(sample(address: 'Local'));
        backend.toPull = [
          local.copyWith(
            address: 'Remote',
            updatedAt: DateTime.utc(2025, 12, 31).toIso8601String(),
          ),
        ];

        await engine.sync();

        expect(backend.pushed.map((r) => r.uuid), [local.uuid]);
        final merged = await store.findByUuid(local.uuid!);
        expect(merged!.address, 'Local');
      });

      test('a_tie_pushes_a_local_tombstone', () async {
        final local = await repo.create(sample(address: 'Local'));
        await engine.sync();
        await repo.deleteById(local.id!);
        final tombstone = await store.findByUuid(local.uuid!);
        // Same instant as the local delete, remote not deleted: the tombstone
        // wins the tie, so its delete is sent.
        backend.toPull = [
          local.copyWith(address: 'Remote', updatedAt: tombstone!.updatedAt),
        ];

        await engine.sync();

        expect(backend.deleted.map((r) => r.uuid), [local.uuid]);
        final merged = await store.findByUuid(local.uuid!);
        expect(merged!.deleted, isTrue);
      });

      test('report_counts_what_was_sent', () async {
        final stale = await repo.create(sample(address: 'Stale'));
        await repo.create(sample(address: 'Fresh'));
        backend.toPull = [
          stale.copyWith(address: 'Remote', updatedAt: day(2)),
        ];

        final report = await engine.sync();

        expect(report.pushed, 1);
        expect(report.pulled, 1);
      });
    });
  });
}
