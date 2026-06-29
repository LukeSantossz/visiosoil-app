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
  });
}
