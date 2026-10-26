import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:share_plus_platform_interface/share_plus_platform_interface.dart';
import 'package:visiosoil_app/core/services/share_service.dart';
import 'package:visiosoil_app/models/soil_record.dart';

class _Platform extends SharePlatform {
  String? path;
  Uint8List? bytes;
  bool fails = false;
  @override
  Future<ShareResult> share(ShareParams params) async {
    path = params.files!.single.path;
    bytes = await File(path!).readAsBytes();
    if (fails) throw Exception('sharing unavailable');
    return const ShareResult('done', ShareResultStatus.success);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final platform = _Platform();
  setUpAll(() => SharePlatform.instance = platform);
  setUp(() {
    platform.path = null;
    platform.bytes = null;
    platform.fails = false;
  });
  test(
    'CSV contains chosen columns and cleans temporary directory after sharing',
    () async {
      await const ShareService().shareExport(
        [
          const SoilRecord(
            imagePath: '',
            timestamp: '2026-10-24',
            textureClass: 'Argilosa',
            confidenceScore: .82,
            latitude: -17.79,
          ),
        ],
        includeDate: false,
        includeLocation: false,
        includePhotos: false,
      );
      expect(utf8.decode(platform.bytes!), contains('Argilosa'));
      expect(utf8.decode(platform.bytes!), isNot(contains('Latitude')));
      expect(Directory(File(platform.path!).parent.path).existsSync(), isFalse);
    },
  );
  test(
    'ZIP includes CSV and selected photos; source files survive cleanup',
    () async {
      final directory = Directory.current.createTempSync('.export-test-');
      addTearDown(() => directory.deleteSync(recursive: true));
      final photo = File('${directory.path}/sample.jpg')
        ..writeAsBytesSync([1, 2, 3]);
      await const ShareService().shareExport(
        [SoilRecord(imagePath: photo.path, timestamp: '2026-10-24')],
        includeDate: true,
        includeLocation: true,
        includePhotos: true,
      );
      final archive = ZipDecoder().decodeBytes(platform.bytes!);
      expect(archive.files.map((file) => file.name), [
        'analises.csv',
        'fotos/amostra_1.jpg',
      ]);
      expect(utf8.decode(archive.files.first.content), contains('Latitude'));
      expect(archive.files.last.content, [1, 2, 3]);
      expect(photo.existsSync(), isTrue);
      expect(File(platform.path!).existsSync(), isFalse);
    },
  );
  test(
    'a failed share propagates and still removes its temporary directory',
    () async {
      platform.fails = true;
      await expectLater(
        const ShareService().shareExport(
          [],
          includeDate: true,
          includeLocation: false,
          includePhotos: false,
        ),
        throwsException,
      );
      expect(File(platform.path!).parent.existsSync(), isFalse);
    },
  );
  test(
    'missing selected photo fails rather than exporting a partial archive',
    () async {
      await expectLater(
        const ShareService().shareExport(
          [
            const SoilRecord(
              imagePath: '/missing-visiosoil-photo.jpg',
              timestamp: '',
            ),
          ],
          includeDate: true,
          includeLocation: false,
          includePhotos: true,
        ),
        throwsA(isA<FileSystemException>()),
      );
      expect(platform.path, isNull);
    },
  );
}
