// Acceptance criteria of SPEC 0240: a record keeps the light, distance and
// focus its shot was taken with, reads back what it stored, a delete erases
// them, and a record pulled from the backend carries them too.
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
    repo = DriftSoilRecordRepository(
      db,
      imageStorage: FakeImageStorageService(),
    );
  });

  tearDown(() async {
    await db.close();
  });

  Future<({double? lux, double? distanceMm, bool? sharp})> stored(
    int id,
  ) async {
    final row = await db
        .customSelect(
          'SELECT capture_lux, capture_distance_mm, capture_sharp '
          'FROM soil_records WHERE id = $id',
        )
        .getSingle();
    return (
      lux: row.read<double?>('capture_lux'),
      distanceMm: row.read<double?>('capture_distance_mm'),
      sharp: row.read<bool?>('capture_sharp'),
    );
  }

  test('create_keeps_the_conditions', () async {
    final saved = await repo.create(
      const SoilRecord(
        imagePath: '/img.jpg',
        timestamp: '2026-10-31T09:30:00.000Z',
        captureLux: 1483.5,
        captureDistanceMm: 339.2,
        captureSharp: true,
      ),
    );

    final read = await repo.getById(saved.id!);
    expect(read!.captureLux, 1483.5);
    expect(read.captureDistanceMm, 339.2);
    expect(read.captureSharp, isTrue);
  });

  test('create_keeps_null_conditions', () async {
    final saved = await repo.create(
      const SoilRecord(
        imagePath: '/img.jpg',
        timestamp: '2026-10-31T09:30:00.000Z',
      ),
    );

    final read = await repo.getById(saved.id!);
    expect(read!.captureLux, isNull);
    expect(read.captureDistanceMm, isNull);
    expect(read.captureSharp, isNull);
  });

  test('delete_erases_the_conditions', () async {
    final saved = await repo.create(
      const SoilRecord(
        imagePath: '/img.jpg',
        timestamp: '2026-10-31T09:30:00.000Z',
        captureLux: 1483.5,
        captureDistanceMm: 339.2,
        captureSharp: false,
      ),
    );

    await repo.deleteById(saved.id!);

    final row = await stored(saved.id!);
    expect(row.lux, isNull);
    expect(row.distanceMm, isNull);
    expect(row.sharp, isNull);
  });

  test('sync_apply_carries_the_conditions', () async {
    final store = SyncLocalStore(db);
    const remote = SoilRecord(
      uuid: 'uuid-remote',
      remoteId: 'remote-1',
      imagePath: '/remote.jpg',
      timestamp: '2026-10-30T08:00:00.000Z',
      updatedAt: '2026-10-30T08:00:00.000Z',
      captureLux: 87.4,
      captureDistanceMm: 410,
      captureSharp: false,
    );

    await store.insertFromRemote(remote);
    var local = await store.findByUuid('uuid-remote');
    expect(local!.captureLux, 87.4);
    expect(local.captureDistanceMm, 410);
    expect(local.captureSharp, isFalse);

    await store.applyRemote(
      remote.copyWith(
        updatedAt: '2026-10-31T08:00:00.000Z',
        captureLux: 1480,
        captureDistanceMm: 339,
        captureSharp: true,
      ),
    );
    local = await store.findByUuid('uuid-remote');
    expect(local!.captureLux, 1480);
    expect(local.captureDistanceMm, 339);
    expect(local.captureSharp, isTrue);
  });
}
