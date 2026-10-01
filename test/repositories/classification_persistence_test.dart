// Acceptance criteria of SPEC 0097: a record keeps the class distribution and
// the contract versions that scored it, reads back what it stored, and a
// record pulled from the backend carries them too.
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visiosoil_app/core/data/repositories/drift_soil_record_repository.dart';
import 'package:visiosoil_app/core/data/sync/sync_local_store.dart';
import 'package:visiosoil_app/core/database/app_database.dart';
import 'package:visiosoil_app/models/class_score.dart';
import 'package:visiosoil_app/models/soil_record.dart';

import '../support/fake_image_storage_service.dart';

/// In the contract's class order, which is how a record stores it: Media leads
/// on probability and still sits second.
const _classDistribution = [
  ClassScore(label: 'Arenosa', probability: 0.12),
  ClassScore(label: 'Media', probability: 0.61),
  ClassScore(label: 'Muito Argilosa', probability: 0.07),
  ClassScore(label: 'Argilosa', probability: 0.2),
];

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

  const classified = SoilRecord(
    imagePath: '/img.jpg',
    timestamp: '2026-01-01T09:30:00.000Z',
    textureClass: 'Media',
    confidenceScore: 0.61,
    classDistribution: _classDistribution,
    modelVersion: '1.0.0',
    datasetVersion: 'v1',
  );

  Future<String?> storedDistribution(int id) async => (await db
          .customSelect(
            'SELECT class_distribution FROM soil_records WHERE id = $id',
          )
          .getSingle())
      .read<String?>('class_distribution');

  test('a_classified_record_keeps_its_distribution_and_versions', () async {
    final saved = await repo.create(classified);

    final read = await repo.getById(saved.id!);
    expect(read!.classDistribution, _classDistribution);
    expect(read.modelVersion, '1.0.0');
    expect(read.datasetVersion, 'v1');

    // Stored in the order given, the contract's, and never renormalised.
    expect(jsonDecode((await storedDistribution(saved.id!))!), [
      {'label': 'Arenosa', 'probability': 0.12},
      {'label': 'Media', 'probability': 0.61},
      {'label': 'Muito Argilosa', 'probability': 0.07},
      {'label': 'Argilosa', 'probability': 0.2},
    ]);
  });

  test('an_unclassified_record_keeps_none', () async {
    final saved = await repo.create(
      const SoilRecord(imagePath: '/img.jpg', timestamp: '2026-01-01T09:30:00Z'),
    );

    final read = await repo.getById(saved.id!);
    expect(read!.classDistribution, isNull);
    expect(read.modelVersion, isNull);
    expect(read.datasetVersion, isNull);
    expect(await storedDistribution(saved.id!), isNull);
  });

  test('a_malformed_stored_distribution_reads_as_none', () async {
    final saved = await repo.create(classified);

    for (final corrupt in [
      '{not json',
      '{"label": "Media"}',
      '[{"label": 3, "probability": 0.5}]',
      '[{"label": "Media"}]',
    ]) {
      await db.customStatement(
        'UPDATE soil_records SET class_distribution = ? WHERE id = ?',
        [corrupt, saved.id],
      );

      final read = await repo.getById(saved.id!);
      expect(read!.classDistribution, isNull, reason: corrupt);
      // The rest of the record still reads.
      expect(read.textureClass, 'Media', reason: corrupt);
      expect(read.confidenceScore, 0.61, reason: corrupt);
      expect(read.modelVersion, '1.0.0', reason: corrupt);
    }
  });

  test('a_pulled_record_writes_its_distribution', () async {
    final store = SyncLocalStore(db);
    const remote = SoilRecord(
      uuid: 'uuid-remote',
      remoteId: 'remote-1',
      imagePath: '/remote.jpg',
      timestamp: '2026-01-02T08:00:00.000Z',
      updatedAt: '2026-01-02T08:00:00.000Z',
      textureClass: 'Media',
      confidenceScore: 0.61,
      classDistribution: _classDistribution,
      modelVersion: '1.0.0',
      datasetVersion: 'v1',
    );

    await store.insertFromRemote(remote);
    var stored = await store.findByUuid('uuid-remote');
    expect(stored!.classDistribution, _classDistribution);
    expect(stored.modelVersion, '1.0.0');
    expect(stored.datasetVersion, 'v1');

    const newer = [
      ClassScore(label: 'Arenosa', probability: 0.7),
      ClassScore(label: 'Media', probability: 0.1),
      ClassScore(label: 'Muito Argilosa', probability: 0.1),
      ClassScore(label: 'Argilosa', probability: 0.1),
    ];
    await store.applyRemote(
      remote.copyWith(
        updatedAt: '2026-01-03T08:00:00.000Z',
        textureClass: 'Arenosa',
        confidenceScore: 0.7,
        classDistribution: newer,
        modelVersion: '1.1.0',
        datasetVersion: 'v2',
      ),
    );
    stored = await store.findByUuid('uuid-remote');
    expect(stored!.classDistribution, newer);
    expect(stored.modelVersion, '1.1.0');
    expect(stored.datasetVersion, 'v2');
  });
}
