// Acceptance criteria of SPEC 0173: a record saved without a classification
// keeps why, reads back what it stored, reads a name it does not know as none,
// and a delete erases it.
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visiosoil_app/core/data/repositories/drift_soil_record_repository.dart';
import 'package:visiosoil_app/core/data/sync/sync_local_store.dart';
import 'package:visiosoil_app/core/database/app_database.dart';
import 'package:visiosoil_app/core/services/classification_report.dart';
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

  Future<String?> storedCause(int id) async => (await db
          .customSelect(
            'SELECT classification_failure FROM soil_records WHERE id = $id',
          )
          .getSingle())
      .read<String?>('classification_failure');

  test('a_failed_capture_keeps_its_cause', () async {
    final failed = await repo.create(
      const SoilRecord(
        imagePath: '/img.jpg',
        timestamp: '2026-10-19T15:00:00.000Z',
        classificationFailure: ClassificationFailureCause.photographTooCoarse,
      ),
    );
    final classified = await repo.create(
      const SoilRecord(
        imagePath: '/img.jpg',
        timestamp: '2026-10-19T15:01:00.000Z',
        textureClass: 'Argilosa',
        confidenceScore: 0.9,
      ),
    );

    expect(await storedCause(failed.id!), 'photographTooCoarse');
    expect(
      (await repo.getById(failed.id!))!.classificationFailure,
      ClassificationFailureCause.photographTooCoarse,
    );
    expect(await storedCause(classified.id!), isNull);
    expect((await repo.getById(classified.id!))!.classificationFailure, isNull);
  });

  test('an_unknown_cause_reads_as_null', () async {
    final saved = await repo.create(
      const SoilRecord(
        imagePath: '/img.jpg',
        timestamp: '2026-10-19T15:00:00.000Z',
      ),
    );
    await db.customStatement(
      "UPDATE soil_records SET classification_failure = 'retiredCause' "
      'WHERE id = ${saved.id}',
    );

    expect((await repo.getById(saved.id!))!.classificationFailure, isNull);
  });

  test('a_tombstone_erases_the_cause', () async {
    final saved = await repo.create(
      const SoilRecord(
        imagePath: '/img.jpg',
        timestamp: '2026-10-19T15:00:00.000Z',
        classificationFailure: ClassificationFailureCause.sheetCropped,
      ),
    );

    await repo.deleteById(saved.id!);

    expect(await storedCause(saved.id!), isNull);
  });

  // A record pulled from the backend, or the backend's version winning a
  // merge, carries its own cause, as every other field does.
  test('a_pulled_record_writes_its_cause', () async {
    final store = SyncLocalStore(db);
    const remote = SoilRecord(
      uuid: 'uuid-remote',
      remoteId: 'remote-1',
      imagePath: '/remote.jpg',
      timestamp: '2026-10-19T15:00:00.000Z',
      updatedAt: '2026-10-19T15:00:00.000Z',
      classificationFailure: ClassificationFailureCause.sheetNotFound,
    );

    await store.insertFromRemote(remote);
    var stored = await store.findByUuid('uuid-remote');
    expect(stored!.classificationFailure, ClassificationFailureCause.sheetNotFound);

    await store.applyRemote(
      remote.copyWith(
        updatedAt: '2026-10-20T08:00:00.000Z',
        classificationFailure: ClassificationFailureCause.sheetCropped,
      ),
    );
    stored = await store.findByUuid('uuid-remote');
    expect(stored!.classificationFailure, ClassificationFailureCause.sheetCropped);
  });
}
