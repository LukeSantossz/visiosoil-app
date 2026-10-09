// Acceptance criteria of SPEC 0149: a record's field and sample labels are
// written trimmed, a blank one is stored as none, an edit is marked for sync,
// a record pulled from the backend carries them, and history search finds a
// record by either label.
import 'package:drift/drift.dart' show QueryRow;
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
  late DateTime now;

  const createdAt = '2026-01-01T12:00:00.000Z';
  const editedAt = '2026-02-03T04:05:06.000Z';

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

  Future<SoilRecord> saved({String? address = 'Fazenda Boa Vista'}) =>
      repo.create(
        SoilRecord(
          imagePath: '/img.jpg',
          address: address,
          timestamp: '2026-01-01T09:30:00.000Z',
        ),
      );

  Future<QueryRow> storedRow(int id) => db
      .customSelect('SELECT * FROM soil_records WHERE id = $id')
      .getSingle();

  Future<List<QueryRow>> queue() => db
      .customSelect('SELECT * FROM sync_queue ORDER BY id')
      .get();

  test('updating_labels_stores_them_trimmed', () async {
    final record = await saved();

    await repo.updateLabels(
      record.id!,
      fieldName: '  Talhão 3 ',
      sampleLabel: ' A1',
    );

    final read = await repo.getById(record.id!);
    expect(read!.fieldName, 'Talhão 3');
    expect(read.sampleLabel, 'A1');
    final row = await storedRow(record.id!);
    expect(row.read<String?>('field_name'), 'Talhão 3');
    expect(row.read<String?>('sample_label'), 'A1');
  });

  test('a_blank_label_is_stored_as_none', () async {
    final record = await saved();
    await repo.updateLabels(
      record.id!,
      fieldName: 'Talhão 3',
      sampleLabel: 'A1',
    );

    await repo.updateLabels(record.id!, fieldName: '', sampleLabel: '   ');

    final row = await storedRow(record.id!);
    expect(row.read<String?>('field_name'), isNull);
    expect(row.read<String?>('sample_label'), isNull);
    expect((await repo.getById(record.id!))!.hasLabels, isFalse);
  });

  test('updating_labels_marks_the_record_for_sync', () async {
    final record = await saved();
    final queuedAtCreate = (await queue()).length;
    now = DateTime.parse(editedAt);

    await repo.updateLabels(record.id!, fieldName: 'Talhão 3');

    final row = await storedRow(record.id!);
    expect(row.read<String>('updated_at'), editedAt);
    final added = (await queue()).skip(queuedAtCreate).toList();
    expect(added, hasLength(1));
    expect(added.single.read<String>('record_uuid'), record.uuid);
    expect(added.single.read<String>('operation'), 'upsert');
    expect(added.single.read<String>('created_at'), editedAt);
  });

  test('updating_a_missing_or_deleted_record_writes_nothing', () async {
    final deleted = await saved();
    await repo.deleteById(deleted.id!);
    final before = await storedRow(deleted.id!);
    final queuedBefore = (await queue()).length;
    now = DateTime.parse(editedAt);

    await repo.updateLabels(deleted.id!, fieldName: 'Talhão 3');
    await repo.updateLabels(9999, fieldName: 'Talhão 3');

    final after = await storedRow(deleted.id!);
    expect(after.read<String?>('field_name'), isNull);
    expect(after.read<String>('updated_at'), before.read<String>('updated_at'));
    expect(await queue(), hasLength(queuedBefore));
  });

  test('a_pulled_record_writes_its_labels', () async {
    final store = SyncLocalStore(db);
    const remote = SoilRecord(
      uuid: 'uuid-remote',
      remoteId: 'remote-1',
      imagePath: '/remote.jpg',
      timestamp: '2026-01-02T08:00:00.000Z',
      updatedAt: '2026-01-02T08:00:00.000Z',
      fieldName: 'Talhão 3',
      sampleLabel: 'A1',
    );

    await store.insertFromRemote(remote);
    var stored = await store.findByUuid('uuid-remote');
    expect(stored!.fieldName, 'Talhão 3');
    expect(stored.sampleLabel, 'A1');

    await store.applyRemote(
      remote.copyWith(
        updatedAt: '2026-01-03T08:00:00.000Z',
        fieldName: 'Talhão 4',
        sampleLabel: 'B2',
      ),
    );
    stored = await store.findByUuid('uuid-remote');
    expect(stored!.fieldName, 'Talhão 4');
    expect(stored.sampleLabel, 'B2');
  });

  group('search_matches_a_label', () {
    Future<List<int>> found(String term) async => (await repo
            .watchFiltered(searchTerm: term)
            .first)
        .map((record) => record.id!)
        .toList();

    test('by field name, with no address', () async {
      final record = await saved(address: null);
      await repo.updateLabels(record.id!, fieldName: 'Talhão Norte');

      expect(await found('norte'), [record.id]);
    });

    test('by sample label, with no address', () async {
      final record = await saved(address: null);
      await repo.updateLabels(record.id!, sampleLabel: 'Amostra B7');

      expect(await found('B7'), [record.id]);
      expect(await found('b7'), [record.id]);
    });

    test('still by address', () async {
      final record = await saved();
      await repo.updateLabels(record.id!, fieldName: 'Talhão 3');

      expect(await found('boa vista'), [record.id]);
    });

    test('nothing when no column holds the term', () async {
      final record = await saved();
      await repo.updateLabels(
        record.id!,
        fieldName: 'Talhão 3',
        sampleLabel: 'A1',
      );

      expect(await found('pivô'), isEmpty);
    });
  });
}
