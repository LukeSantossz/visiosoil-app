// Tests for [ImagePreviewScreen]'s image viewer: the broken-image fallback is
// now provided by `Image.file`'s `errorBuilder` instead of a synchronous
// `existsSync()` pre-check. The private `_ImageViewer` is exercised through the
// public screen, with `soilRecordByIdProvider` overridden to supply the record.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:visiosoil_app/core/features/preview/image_preview_screen.dart';
import 'package:visiosoil_app/models/soil_record.dart';
import 'package:visiosoil_app/providers/soil_record_repository_provider.dart';

void main() {
  late Directory tempDir;
  late String imagePath;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('visiosoil_preview_test');
    imagePath = (File(p.join(tempDir.path, 'photo.png'))
          ..writeAsBytesSync(img.encodePng(img.Image(width: 4, height: 4))))
        .path;
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  SoilRecord record() => SoilRecord(
        id: 1,
        imagePath: imagePath,
        timestamp: DateTime.utc(2026, 1, 2, 14, 30).toIso8601String(),
      );

  Future<void> pumpPreview(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          soilRecordByIdProvider.overrideWith((ref, id) async => record()),
        ],
        child: MaterialApp(home: const ImagePreviewScreen(recordId: 1)),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'preview_image_file_has_error_builder_rendering_broken_image_fallback',
    (tester) async {
      await pumpPreview(tester);

      final image = tester.widget<Image>(find.byType(Image));
      expect(image.errorBuilder, isNotNull);

      final fallback = image.errorBuilder!(
        tester.element(find.byType(Image)),
        Exception('load failed'),
        null,
      );
      expect(fallback, isA<Icon>());
      expect((fallback as Icon).icon, Icons.broken_image);
    },
  );
}
