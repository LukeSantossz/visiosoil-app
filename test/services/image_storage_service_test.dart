import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:visiosoil_app/core/services/image_storage_service.dart';

void main() {
  group('DefaultImageStorageService', () {
    late Directory baseDir;
    late Directory sourceDir;
    late DefaultImageStorageService service;

    setUp(() {
      baseDir = Directory.systemTemp.createTempSync('visiosoil_base');
      sourceDir = Directory.systemTemp.createTempSync('visiosoil_src');
      service = DefaultImageStorageService(baseDirectory: () async => baseDir);
    });

    tearDown(() {
      if (baseDir.existsSync()) baseDir.deleteSync(recursive: true);
      if (sourceDir.existsSync()) sourceDir.deleteSync(recursive: true);
    });

    File writeSource(String name, List<int> bytes) {
      final file = File(p.join(sourceDir.path, name))..writeAsBytesSync(bytes);
      return file;
    }

    test('saveCapturedImage_copies_source_into_soil_images_subdir_of_base',
        () async {
      final source = writeSource('photo.jpg', [1, 2, 3]);

      final stored = await service.saveCapturedImage(source, recordUuid: 'uuid-1');

      expect(p.dirname(stored), p.join(baseDir.path, 'soil_images'));
      expect(File(stored).existsSync(), isTrue);
    });

    test('saveCapturedImage_returns_path_whose_file_exists_with_bytes_equal_to_source',
        () async {
      final source = writeSource('photo.jpg', [10, 20, 30, 40]);

      final stored = await service.saveCapturedImage(source, recordUuid: 'uuid-2');

      expect(File(stored).readAsBytesSync(), [10, 20, 30, 40]);
    });

    test('saveCapturedImage_names_file_with_recordUuid_and_preserves_source_extension',
        () async {
      final source = writeSource('photo.png', [1]);

      final stored = await service.saveCapturedImage(source, recordUuid: 'abc');

      expect(p.basename(stored), 'abc.png');
    });

    test('saveCapturedImage_falls_back_to_jpg_extension_when_source_has_no_extension',
        () async {
      final source = writeSource('photo', [1]);

      final stored = await service.saveCapturedImage(source, recordUuid: 'abc');

      expect(p.basename(stored), 'abc.jpg');
    });

    test('saveCapturedImage_throws_when_source_file_does_not_exist', () async {
      final missing = File(p.join(sourceDir.path, 'missing.jpg'));

      await expectLater(
        () => service.saveCapturedImage(missing, recordUuid: 'x'),
        throwsA(isA<FileSystemException>()),
      );
    });

    test('saveCapturedImage_rejects_recordUuid_with_path_separators', () async {
      final source = writeSource('photo.jpg', [1]);

      await expectLater(
        () => service.saveCapturedImage(source, recordUuid: '../evil'),
        throwsA(isA<ArgumentError>()),
      );
      await expectLater(
        () => service.saveCapturedImage(source, recordUuid: r'..\evil'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('deleteImage_removes_the_file_at_the_given_path', () async {
      final source = writeSource('photo.jpg', [1, 2, 3]);
      final stored = await service.saveCapturedImage(source, recordUuid: 'gone');
      expect(File(stored).existsSync(), isTrue);

      await service.deleteImage(stored);

      expect(File(stored).existsSync(), isFalse);
    });

    test('deleteImage_is_a_noop_when_the_file_is_already_absent', () async {
      final absent = p.join(baseDir.path, 'soil_images', 'missing.jpg');

      await service.deleteImage(absent);

      expect(File(absent).existsSync(), isFalse);
    });

    test('saveCapturedImage_throws_filesystemexception_when_target_path_already_exists',
        () async {
      final first = writeSource('first.jpg', [1, 1, 1]);
      await service.saveCapturedImage(first, recordUuid: 'dup');

      final second = writeSource('second.jpg', [2, 2, 2]);
      await expectLater(
        () => service.saveCapturedImage(second, recordUuid: 'dup'),
        throwsA(isA<FileSystemException>()),
      );
    });

    test('saveCapturedImage_preserves_the_existing_file_when_it_refuses_to_overwrite',
        () async {
      final first = writeSource('first.jpg', [1, 1, 1]);
      final stored = await service.saveCapturedImage(first, recordUuid: 'dup');

      final second = writeSource('second.jpg', [2, 2, 2]);
      try {
        await service.saveCapturedImage(second, recordUuid: 'dup');
      } on FileSystemException {
        // expected: the write refuses to overwrite.
      }

      expect(File(stored).readAsBytesSync(), [1, 1, 1]);
    });
  });
}
