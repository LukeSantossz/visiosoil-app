// Acceptance criteria of SPEC 0148: a record keeps the horizontal accuracy of
// its GPS fix, reads back what it stored, and a record pulled from the backend
// carries it too.
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visiosoil_app/core/data/repositories/drift_soil_record_repository.dart';
import 'package:visiosoil_app/core/data/sync/sync_local_store.dart';
import 'package:visiosoil_app/core/database/app_database.dart';
import 'package:visiosoil_app/models/soil_record.dart';

import '../support/fake_image_storage_service.dart';

void main() {
  late AppDatabase db;
  late DriftSoilRecordRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = DriftSoilRecordRepository(db, imageStorage: FakeImageStorageService());
  });

  tearDown(() async {
    await db.close();
  });

  Future<double?> storedAccuracy(int id) async => (await db
          .customSelect(
            'SELECT horizontal_accuracy FROM soil_records WHERE id = $id',
          )
          .getSingle())
      .read<double?>('horizontal_accuracy');

  test('a_located_record_keeps_its_accuracy', () async {
    final saved = await repo.create(
      const SoilRecord(
        imagePath: '/img.jpg',
        latitude: -22.9,
        longitude: -47.06,
        timestamp: '2026-01-01T09:30:00.000Z',
        horizontalAccuracy: 4.2,
      ),
    );

    final read = await repo.getById(saved.id!);
    expect(read!.horizontalAccuracy, 4.2);
    expect(await storedAccuracy(saved.id!), 4.2);
  });

  test('a_record_without_accuracy_keeps_none', () async {
    final saved = await repo.create(
      const SoilRecord(
        imagePath: '/img.jpg',
        latitude: -22.9,
        longitude: -47.06,
        timestamp: '2026-01-01T09:30:00.000Z',
      ),
    );

    final read = await repo.getById(saved.id!);
    expect(read!.horizontalAccuracy, isNull);
    expect(await storedAccuracy(saved.id!), isNull);
  });

  test('a_pulled_record_writes_its_accuracy', () async {
    final store = SyncLocalStore(db);
    const remote = SoilRecord(
      uuid: 'uuid-remote',
      remoteId: 'remote-1',
      imagePath: '/remote.jpg',
      latitude: -22.9,
      longitude: -47.06,
      timestamp: '2026-01-02T08:00:00.000Z',
      updatedAt: '2026-01-02T08:00:00.000Z',
      horizontalAccuracy: 12.5,
    );

    await store.insertFromRemote(remote);
    var stored = await store.findByUuid('uuid-remote');
    expect(stored!.horizontalAccuracy, 12.5);

    await store.applyRemote(
      remote.copyWith(
        updatedAt: '2026-01-03T08:00:00.000Z',
        horizontalAccuracy: 3.0,
      ),
    );
    stored = await store.findByUuid('uuid-remote');
    expect(stored!.horizontalAccuracy, 3.0);
  });
}
