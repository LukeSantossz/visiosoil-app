// Acceptance criteria of SPEC 0219 for the repository: `create` writes the
// labels it is given, and a capture saved when its photograph arrives has its
// classification and location written into it as they come.
import 'package:drift/drift.dart' show QueryRow;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visiosoil_app/core/data/repositories/drift_soil_record_repository.dart';
import 'package:visiosoil_app/core/database/app_database.dart';
import 'package:visiosoil_app/core/services/classification_report.dart';
import 'package:visiosoil_app/models/class_score.dart';
import 'package:visiosoil_app/models/soil_record.dart';

import '../support/fake_image_storage_service.dart';

void main() {
  late AppDatabase db;
  late DriftSoilRecordRepository repo;
  late DateTime now;

  const createdAt = '2026-01-01T12:00:00.000Z';
  const writtenAt = '2026-02-03T04:05:06.000Z';

  const distribution = [
    ClassScore(label: 'Argilosa', probability: 0.7),
    ClassScore(label: 'Muito argilosa', probability: 0.1),
    ClassScore(label: 'Média', probability: 0.15),
    ClassScore(label: 'Arenosa', probability: 0.05),
  ];

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

  // What capture creates when the photograph arrives: no class, no fix.
  Future<SoilRecord> arrived() => repo.create(
    const SoilRecord(
      imagePath: '/img.jpg',
      address: 'Endereço indisponível',
      timestamp: '2026-01-01T09:30:00.000Z',
    ),
  );

  Future<QueryRow> storedRow(int id) =>
      db.customSelect('SELECT * FROM soil_records WHERE id = $id').getSingle();

  Future<List<QueryRow>> queue() =>
      db.customSelect('SELECT * FROM sync_queue ORDER BY id').get();

  test('create_persists_the_labels', () async {
    final created = await repo.create(
      const SoilRecord(
        imagePath: '/img.jpg',
        timestamp: '2026-01-01T09:30:00.000Z',
        fieldName: ' Talhão 3 ',
        sampleLabel: '',
      ),
    );

    final row = await storedRow(created.id!);
    expect(row.read<String?>('field_name'), 'Talhão 3');
    expect(row.read<String?>('sample_label'), isNull);
    final read = await repo.getById(created.id!);
    expect(read!.fieldName, 'Talhão 3');
    expect(read.sampleLabel, isNull);
  });

  test('update_classification_writes_the_result', () async {
    final record = await arrived();
    final queuedAtCreate = (await queue()).length;
    now = DateTime.parse(writtenAt);

    await repo.updateClassification(
      record.id!,
      textureClass: 'Argilosa',
      confidenceScore: 0.7,
      classDistribution: distribution,
      modelVersion: '1.0.0',
      datasetVersion: 'v1',
    );

    final read = (await repo.getById(record.id!))!;
    expect(read.textureClass, 'Argilosa');
    expect(read.confidenceScore, 0.7);
    expect(read.classDistribution, distribution);
    expect(read.modelVersion, '1.0.0');
    expect(read.datasetVersion, 'v1');
    expect(read.classificationFailure, isNull);
    final row = await storedRow(record.id!);
    expect(row.read<String>('sync_status'), 'pending');
    expect(row.read<String>('updated_at'), writtenAt);
    final added = (await queue()).skip(queuedAtCreate).toList();
    expect(added, hasLength(1));
    expect(added.single.read<String>('record_uuid'), record.uuid);
    expect(added.single.read<String>('operation'), 'upsert');
  });

  test('update_classification_writes_the_cause', () async {
    final record = await arrived();

    await repo.updateClassification(
      record.id!,
      classificationFailure: ClassificationFailureCause.sheetNotFound,
    );

    final read = (await repo.getById(record.id!))!;
    expect(read.textureClass, isNull);
    expect(read.confidenceScore, isNull);
    expect(read.classificationFailure, ClassificationFailureCause.sheetNotFound);
  });

  test('update_location_writes_the_reading', () async {
    final record = await arrived();
    final queuedAtCreate = (await queue()).length;
    now = DateTime.parse(writtenAt);

    await repo.updateLocation(
      record.id!,
      latitude: -23.5,
      longitude: -46.6,
      horizontalAccuracy: 8.5,
      address: 'Fazenda Boa Vista',
    );

    final read = (await repo.getById(record.id!))!;
    expect(read.latitude, -23.5);
    expect(read.longitude, -46.6);
    expect(read.horizontalAccuracy, 8.5);
    expect(read.address, 'Fazenda Boa Vista');
    final row = await storedRow(record.id!);
    expect(row.read<String>('updated_at'), writtenAt);
    final added = (await queue()).skip(queuedAtCreate).toList();
    expect(added, hasLength(1));
    expect(added.single.read<String>('operation'), 'upsert');
  });

  test('updates_skip_a_tombstone', () async {
    final record = await arrived();
    await repo.deleteById(record.id!);
    final before = await storedRow(record.id!);
    final queuedBefore = (await queue()).length;
    now = DateTime.parse(writtenAt);

    await repo.updateClassification(
      record.id!,
      textureClass: 'Argilosa',
      confidenceScore: 0.7,
    );
    await repo.updateLocation(
      record.id!,
      latitude: -23.5,
      longitude: -46.6,
      address: 'Fazenda Boa Vista',
    );

    final after = await storedRow(record.id!);
    expect(after.read<String?>('texture_class'), isNull);
    expect(after.read<double?>('latitude'), isNull);
    expect(after.read<String>('updated_at'), before.read<String>('updated_at'));
    expect(await queue(), hasLength(queuedBefore));
  });
}
