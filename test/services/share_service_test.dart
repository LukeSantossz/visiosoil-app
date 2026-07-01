// Tests for [ShareService]: the native share flow that composes a PNG card,
// writes it to a temporary directory, hands it to `share_plus`, and cleans the
// directory up afterward. The platform share sheet is replaced by a fake
// [SharePlatform] injected through the public `SharePlatform.instance` seam, so
// no production seam is added to [ShareService].
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:share_plus_platform_interface/share_plus_platform_interface.dart';
import 'package:visiosoil_app/core/services/share_service.dart';
import 'package:visiosoil_app/models/soil_record.dart';

/// Fake [SharePlatform] that records the share call and, at share time,
/// captures whether the shared card file still exists — so a test can assert
/// the card is written before the share and its directory removed after it.
class RecordingSharePlatform extends SharePlatform {
  ShareParams? receivedParams;
  String? sharedCardPath;
  bool cardExistedAtShareTime = false;
  bool shouldThrow = false;

  void reset() {
    receivedParams = null;
    sharedCardPath = null;
    cardExistedAtShareTime = false;
    shouldThrow = false;
  }

  @override
  Future<ShareResult> share(ShareParams params) async {
    receivedParams = params;
    final files = params.files;
    if (files != null && files.isNotEmpty) {
      sharedCardPath = files.first.path;
      cardExistedAtShareTime = File(files.first.path).existsSync();
    }
    if (shouldThrow) {
      throw Exception('platform share failed');
    }
    return const ShareResult('ok', ShareResultStatus.success);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const service = ShareService();
  late RecordingSharePlatform platform;
  late Directory sourceDir;

  setUpAll(() {
    // `SharePlus.instance` memoizes `SharePlatform.instance` on first use, so a
    // single fake is installed once and reconfigured per test via [reset].
    platform = RecordingSharePlatform();
    SharePlatform.instance = platform;
  });

  setUp(() {
    platform.reset();
    sourceDir = Directory.systemTemp.createTempSync('visiosoil_share_test');
  });

  tearDown(() {
    if (sourceDir.existsSync()) sourceDir.deleteSync(recursive: true);
  });

  File writePhoto() {
    final bytes = img.encodePng(img.Image(width: 4, height: 4));
    return File(p.join(sourceDir.path, 'photo.png'))..writeAsBytesSync(bytes);
  }

  SoilRecord recordFor(String imagePath) => SoilRecord(
        id: 7,
        imagePath: imagePath,
        latitude: -23.5,
        longitude: -46.6,
        address: 'São Paulo, SP',
        timestamp: DateTime.utc(2026, 1, 2, 14, 30).toIso8601String(),
        textureClass: 'Argilosa',
        confidenceScore: 0.91,
      );

  test('deletes_temp_dir_after_successful_share', () async {
    final photo = writePhoto();

    await service.shareRecord(recordFor(photo.path));

    expect(platform.cardExistedAtShareTime, isTrue);
    final cardDir = File(platform.sharedCardPath!).parent;
    expect(cardDir.existsSync(), isFalse);
  });

  test('deletes_temp_dir_and_rethrows_when_platform_share_throws', () async {
    final photo = writePhoto();
    platform.shouldThrow = true;

    await expectLater(
      () => service.shareRecord(recordFor(photo.path)),
      throwsA(isA<Exception>()),
    );

    expect(platform.cardExistedAtShareTime, isTrue);
    final cardDir = File(platform.sharedCardPath!).parent;
    expect(cardDir.existsSync(), isFalse);
  });

  test('shares_caption_only_and_creates_no_temp_artifacts_when_photo_is_missing',
      () async {
    final missingPath = p.join(sourceDir.path, 'missing.png');

    await service.shareRecord(recordFor(missingPath));

    expect(platform.receivedParams, isNotNull);
    expect(platform.receivedParams!.files, anyOf(isNull, isEmpty));
    expect(platform.receivedParams!.text, isNotNull);
    expect(platform.sharedCardPath, isNull);
  });
}
