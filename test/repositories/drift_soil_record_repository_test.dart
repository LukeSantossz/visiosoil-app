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
      String? address = 'São Paulo',
    }) {
      return SoilRecord(
        imagePath: imagePath,
        latitude: -23.5,
        longitude: -46.6,
        address: address,
        timestamp: ts ?? DateTime.utc(2026, 1, 1).toIso8601String(),
        textureClass: textureClass,
        confidenceScore: confidenceScore,
      );
    }

    Directory makeTempDir(String prefix) {
      final dir = Directory.systemTemp.createTempSync(prefix);
      addTearDown(() {
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });
      return dir;
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

    test('deleteById_removes_the_record_image_file_from_durable_storage',
        () async {
      final baseDir = makeTempDir('visiosoil_delbase');
      final sourceDir = makeTempDir('visiosoil_delsrc');
      final source = File(p.join(sourceDir.path, 'photo.jpg'))
        ..writeAsBytesSync([1, 2, 3]);
      final realRepo = DriftSoilRecordRepository(
        db,
        imageStorage:
            DefaultImageStorageService(baseDirectory: () async => baseDir),
      );

      final saved = await realRepo.create(sample(imagePath: source.path));
      expect(File(saved.imagePath).existsSync(), isTrue);

      await realRepo.deleteById(saved.id!);

      expect(File(saved.imagePath).existsSync(), isFalse);
    });

    test('deleteByIds_removes_every_selected_record_image_file', () async {
      final baseDir = makeTempDir('visiosoil_delbase');
      final sourceDir = makeTempDir('visiosoil_delsrc');
      final realRepo = DriftSoilRecordRepository(
        db,
        imageStorage:
            DefaultImageStorageService(baseDirectory: () async => baseDir),
      );
      Future<SoilRecord> createWith(String name) async {
        final src = File(p.join(sourceDir.path, name))..writeAsBytesSync([1]);
        return realRepo.create(sample(imagePath: src.path));
      }

      final a = await createWith('a.jpg');
      final b = await createWith('b.jpg');
      final c = await createWith('c.jpg');

      await realRepo.deleteByIds([a.id!, c.id!]);

      expect(File(a.imagePath).existsSync(), isFalse);
      expect(File(c.imagePath).existsSync(), isFalse);
      expect(File(b.imagePath).existsSync(), isTrue);
    });

    test('deleteAll_removes_all_record_image_files', () async {
      final baseDir = makeTempDir('visiosoil_delbase');
      final sourceDir = makeTempDir('visiosoil_delsrc');
      final realRepo = DriftSoilRecordRepository(
        db,
        imageStorage:
            DefaultImageStorageService(baseDirectory: () async => baseDir),
      );
      Future<SoilRecord> createWith(String name) async {
        final src = File(p.join(sourceDir.path, name))..writeAsBytesSync([1]);
        return realRepo.create(sample(imagePath: src.path));
      }

      final a = await createWith('a.jpg');
      final b = await createWith('b.jpg');

      await realRepo.deleteAll();

      expect(File(a.imagePath).existsSync(), isFalse);
      expect(File(b.imagePath).existsSync(), isFalse);
    });

    test('tombstone_survives_when_an_image_file_delete_throws_io_error',
        () async {
      final saved = await repo.create(sample());
      storage.throwOnDelete = true;

      // A real I/O failure on the file delete must not abort the committed
      // tombstone or rethrow: deleteById completes normally. The failure is
      // surfaced via developer.log — observability verified by review, not
      // interceptable here without a logger seam the ADR deliberately omits.
      await repo.deleteById(saved.id!);

      expect(await repo.getById(saved.id!), isNull);
      expect(storage.deletedPaths, isNotEmpty);
    });

    test('deleteAll_continues_deleting_remaining_images_when_one_delete_throws',
        () async {
      final selectiveStorage = FakeImageStorageService(uniqueStoredPaths: true);
      final selectiveRepo =
          DriftSoilRecordRepository(db, imageStorage: selectiveStorage);
      final a = await selectiveRepo.create(sample());
      final b = await selectiveRepo.create(sample());
      final c = await selectiveRepo.create(sample());
      // Only b's file delete fails; a and c must still be deleted.
      selectiveStorage.throwDeleteForPaths.add(b.imagePath);

      await selectiveRepo.deleteAll();

      // Every record was tombstoned despite the one failure...
      expect(await selectiveRepo.count(), 0);
      // ...and every image delete was attempted — b's failure did not stop the
      // loop from reaching a and c.
      expect(
        selectiveStorage.deletedPaths,
        containsAll(<String>[a.imagePath, b.imagePath, c.imagePath]),
      );
    });

    // Reads the current snapshot of a reactive query without a fixed delay:
    // Drift emits the query result on subscription, so `.first` resolves as
    // soon as that first event arrives.
    Future<List<int>> filteredIds({
      String? textureClass,
      String? searchTerm,
    }) async {
      final records = await repo
          .watchFiltered(textureClass: textureClass, searchTerm: searchTerm)
          .first;
      return records.map((r) => r.id!).toList();
    }

    test('watchFiltered by textureClass returns only rows of that class',
        () async {
      final argiloso =
          await repo.create(sample(imagePath: '/a.jpg', textureClass: 'Argiloso'));
      await repo.create(sample(imagePath: '/b.jpg', textureClass: 'Arenoso'));
      await repo.create(sample(imagePath: '/c.jpg')); // null texture class

      expect(await filteredIds(textureClass: 'Argiloso'), [argiloso.id]);
    });

    test('watchFiltered by searchTerm matches the address case-insensitively',
        () async {
      final saoPaulo =
          await repo.create(sample(imagePath: '/a.jpg', address: 'São Paulo'));
      await repo.create(sample(imagePath: '/b.jpg', address: 'Rio de Janeiro'));

      expect(await filteredIds(searchTerm: 'paulo'), [saoPaulo.id]);
      expect(await filteredIds(searchTerm: 'PAULO'), [saoPaulo.id]);
    });

    test('watchFiltered combines textureClass and searchTerm with AND semantics',
        () async {
      final match = await repo.create(sample(
          imagePath: '/a.jpg', textureClass: 'Argiloso', address: 'São Paulo'));
      // Matches the class but not the term.
      await repo.create(sample(
          imagePath: '/b.jpg',
          textureClass: 'Argiloso',
          address: 'Rio de Janeiro'));
      // Matches the term but not the class.
      await repo.create(sample(
          imagePath: '/c.jpg', textureClass: 'Arenoso', address: 'São Paulo'));

      expect(
        await filteredIds(textureClass: 'Argiloso', searchTerm: 'paulo'),
        [match.id],
      );
    });

    test(
        'watchFiltered with an empty searchTerm and null textureClass behaves like watchAll',
        () async {
      await repo.create(sample(imagePath: '/a.jpg', address: 'São Paulo'));
      await repo.create(sample(imagePath: '/b.jpg', address: 'Curitiba'));

      final all = (await repo.watchAll().first).map((r) => r.id).toList();

      // No arguments, empty strings, and null are all the no-filter path.
      expect(await filteredIds(), all);
      expect(await filteredIds(searchTerm: '', textureClass: ''), all);
      expect(
        await filteredIds(searchTerm: null, textureClass: null),
        all,
      );
    });

    test(
        'watchFiltered strips SQL wildcards so % and _ in the term are not treated as wildcards',
        () async {
      // `_` matches any single character in SQL LIKE; the sanitizer removes it.
      final ab = await repo.create(sample(imagePath: '/a.jpg', address: 'ab'));
      await repo.create(sample(imagePath: '/b.jpg', address: 'a_b'));

      // Searching a literal 'axb' matches neither stored address.
      expect(await filteredIds(searchTerm: 'axb'), isEmpty);

      // 'a_b' is sanitized to 'ab': it matches the literal 'ab' row and NOT the
      // 'a_b' row. An unsanitized wildcard would have matched the reverse, so
      // this discriminates the strip from a real LIKE wildcard.
      expect(await filteredIds(searchTerm: 'a_b'), [ab.id]);

      // A term of only wildcards sanitizes to empty, so no address filter is
      // applied and every row is returned (same set as watchAll). Documents
      // current behavior: a bare '%' does not scope the results down.
      final all = (await repo.watchAll().first).map((r) => r.id).toList();
      expect(await filteredIds(searchTerm: '%'), all);
    });

    test(
        'getDistinctTextureClasses de-duplicates and excludes null and empty classes',
        () async {
      await repo.create(sample(imagePath: '/a.jpg', textureClass: 'Argiloso'));
      await repo.create(sample(imagePath: '/b.jpg', textureClass: 'Argiloso'));
      await repo.create(sample(imagePath: '/c.jpg', textureClass: 'Arenoso'));
      await repo.create(sample(imagePath: '/d.jpg', textureClass: null));
      await repo.create(sample(imagePath: '/e.jpg', textureClass: ''));

      final classes = await repo.getDistinctTextureClasses();

      expect(classes, unorderedEquals(<String>['Argiloso', 'Arenoso']));
    });
  });
}
