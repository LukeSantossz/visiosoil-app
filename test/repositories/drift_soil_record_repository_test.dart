// Tests for [DriftSoilRecordRepository] using an in-memory SQLite database.
//
// Runs on the Dart VM (no device) — `NativeDatabase.memory()` needs the
// native SQLite library. On CI (Linux/macOS/Windows) this works out of the
// box because `sqlite3_flutter_libs` ships the shared library; on hosts
// without SQLite on the PATH, installing the OS `sqlite3` package may be required.
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:visiosoil_app/core/data/repositories/drift_soil_record_repository.dart';
import 'package:visiosoil_app/core/database/app_database.dart';
import 'package:visiosoil_app/core/services/image_storage_service.dart';
import 'package:visiosoil_app/models/soil_record.dart';

import '../support/fake_image_storage_service.dart';

void main() {
  group('DriftSoilRecordRepository', () {
    late AppDatabase db;
    late DriftSoilRecordRepository repo;
    late FakeImageStorageService storage;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      storage = FakeImageStorageService();
      repo = DriftSoilRecordRepository(db, imageStorage: storage);
    });

    tearDown(() async {
      await db.close();
    });

    SoilRecord sample({
      String imagePath = '/img.jpg',
      String? ts,
      String? textureClass,
      double? confidenceScore,
    }) {
      return SoilRecord(
        imagePath: imagePath,
        latitude: -23.5,
        longitude: -46.6,
        address: 'São Paulo',
        timestamp: ts ?? DateTime.utc(2026, 1, 1).toIso8601String(),
        textureClass: textureClass,
        confidenceScore: confidenceScore,
      );
    }

    test('create assigns id, persists the stable path, and keeps the other fields',
        () async {
      final saved = await repo.create(sample());

      expect(saved.id, isNotNull);
      expect(saved.imagePath, '/stable/stored.jpg');
      expect(storage.savedSources, ['/img.jpg']);
      expect(saved.latitude, -23.5);
      expect(saved.longitude, -46.6);
      expect(saved.address, 'São Paulo');
    });

    test(
        'create_persists_and_returns_the_stable_path_from_storage_service_not_the_source_path',
        () async {
      final saved = await repo.create(sample(imagePath: '/cache/transient.jpg'));

      expect(saved.imagePath, '/stable/stored.jpg');
      expect(saved.imagePath, isNot('/cache/transient.jpg'));
      expect(storage.savedSources, ['/cache/transient.jpg']);

      final fetched = await repo.getById(saved.id!);
      expect(fetched!.imagePath, '/stable/stored.jpg');
    });

    test('create_propagates_and_inserts_no_row_when_storage_service_throws',
        () async {
      storage.throwOnSave = true;

      await expectLater(
        repo.create(sample()),
        throwsA(isA<FileSystemException>()),
      );
      expect(await repo.count(), 0);
    });

    test('create persiste campos de classificação de textura', () async {
      final saved = await repo.create(sample(
        textureClass: 'Franco-Argiloso',
        confidenceScore: 0.92,
      ));

      expect(saved.textureClass, 'Franco-Argiloso');
      expect(saved.confidenceScore, 0.92);

      final fetched = await repo.getById(saved.id!);
      expect(fetched!.textureClass, 'Franco-Argiloso');
      expect(fetched.confidenceScore, 0.92);
    });

    test('getById roundtrip retorna o registro salvo', () async {
      final saved = await repo.create(sample());
      final fetched = await repo.getById(saved.id!);

      expect(fetched, isNotNull);
      expect(fetched!.id, saved.id);
      expect(fetched.imagePath, saved.imagePath);
    });

    test('getById retorna null quando o id não existe', () async {
      expect(await repo.getById(999), isNull);
    });

    test('getAll retorna do mais recente ao mais antigo', () async {
      final first = await repo.create(sample(imagePath: '/a.jpg'));
      final second = await repo.create(sample(imagePath: '/b.jpg'));
      final third = await repo.create(sample(imagePath: '/c.jpg'));

      final all = await repo.getAll();

      expect(all.map((r) => r.id).toList(), [third.id, second.id, first.id]);
    });

    test('getLatest retorna o registro mais recente ou null', () async {
      expect(await repo.getLatest(), isNull);

      await repo.create(sample(imagePath: '/a.jpg'));
      final second = await repo.create(sample(imagePath: '/b.jpg'));

      final latest = await repo.getLatest();
      expect(latest?.id, second.id);
    });

    test('count reflete o total de registros', () async {
      expect(await repo.count(), 0);
      await repo.create(sample());
      await repo.create(sample());
      expect(await repo.count(), 2);
    });

    test('deleteById remove apenas o registro informado', () async {
      final a = await repo.create(sample(imagePath: '/a.jpg'));
      final b = await repo.create(sample(imagePath: '/b.jpg'));

      await repo.deleteById(a.id!);

      expect(await repo.getById(a.id!), isNull);
      expect(await repo.getById(b.id!), isNotNull);
    });

    test('deleteByIds remove em lote e ignora lista vazia', () async {
      final a = await repo.create(sample(imagePath: '/a.jpg'));
      final b = await repo.create(sample(imagePath: '/b.jpg'));
      final c = await repo.create(sample(imagePath: '/c.jpg'));

      await repo.deleteByIds([]); // no-op
      expect(await repo.count(), 3);

      await repo.deleteByIds([a.id!, c.id!]);

      expect(await repo.count(), 1);
      expect(await repo.getById(b.id!), isNotNull);
    });

    test('watchAll emite a lista atualizada após inserções e deleções',
        () async {
      final stream = repo.watchAll();
      final emissions = <List<SoilRecord>>[];
      final sub = stream.listen(emissions.add);

      // Waits for the first emission (empty list).
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final inserted = await repo.create(sample());
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await repo.deleteById(inserted.id!);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      await sub.cancel();

      expect(emissions.first, isEmpty);
      expect(
        emissions.any((list) => list.length == 1 && list.first.id == inserted.id),
        isTrue,
      );
      expect(emissions.last, isEmpty);
    });

    test('create_cleans_up_the_copied_file_when_the_db_write_fails', () async {
      final baseDir = Directory.systemTemp.createTempSync('visiosoil_failbase');
      addTearDown(() {
        if (baseDir.existsSync()) baseDir.deleteSync(recursive: true);
      });
      final sourceDir = Directory.systemTemp.createTempSync('visiosoil_failsrc');
      addTearDown(() {
        if (sourceDir.existsSync()) sourceDir.deleteSync(recursive: true);
      });
      final source = File(p.join(sourceDir.path, 'photo.jpg'))
        ..writeAsBytesSync([1, 2, 3]);

      final realRepo = DriftSoilRecordRepository(
        db,
        imageStorage:
            DefaultImageStorageService(baseDirectory: () async => baseDir),
      );
      // Force the DB write to fail while keeping the connection open: drop the
      // table so the insert throws "no such table". The group's `db` is
      // recreated for each test, so this stays isolated.
      await db.customStatement('DROP TABLE soil_records');

      await expectLater(
        realRepo.create(sample(imagePath: source.path)),
        throwsA(anything),
      );

      final soilImagesDir = Directory(p.join(baseDir.path, 'soil_images'));
      final remaining = soilImagesDir.existsSync()
          ? soilImagesDir.listSync()
          : <FileSystemEntity>[];
      expect(remaining, isEmpty);
    });
  });
}
