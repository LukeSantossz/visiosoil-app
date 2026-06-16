import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:visiosoil_app/core/features/capture/capture_screen.dart';
import 'package:visiosoil_app/core/services/inference_service.dart';
import 'package:visiosoil_app/core/services/permission_service.dart';
import 'package:visiosoil_app/providers/inference_provider.dart';

class _FakeInference extends InferenceService {
  _FakeInference(this._handler);

  final Future<InferenceResult?> Function(String imagePath) _handler;

  @override
  Future<InferenceResult?> classify(String imagePath) => _handler(imagePath);
}

void main() {
  late String samplePath;

  setUpAll(() {
    final dir = Directory.systemTemp.createTempSync('capture_screen_test');
    final file = File('${dir.path}/sample.png');
    file.writeAsBytesSync(img.encodePng(img.Image(width: 8, height: 8)));
    samplePath = file.path;
  });

  Widget buildScreen({
    required CameraImagePicker pickFromCamera,
    required LocationResolver locate,
    required Future<InferenceResult?> Function(String) classify,
  }) {
    return ProviderScope(
      overrides: [
        inferenceServiceProvider.overrideWithValue(_FakeInference(classify)),
      ],
      child: MaterialApp(
        home: CaptureScreen(
          pickFromCamera: pickFromCamera,
          locate: locate,
          checkCameraPermission: () async => AppPermissionStatus.granted,
          requestCameraPermission: () async => AppPermissionStatus.granted,
        ),
      ),
    );
  }

  // Flushes the permission -> pick -> setImage -> start-futures async chain.
  Future<void> capture(WidgetTester tester) async {
    await tester.tap(find.text('Câmera'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
  }

  testWidgets('a camera picker failure shows a snackbar and keeps the screen',
      (tester) async {
    await tester.pumpWidget(buildScreen(
      pickFromCamera: () async => throw PlatformException(code: 'camera_error'),
      locate: () async => null,
      classify: (_) async => null,
    ));

    await capture(tester);

    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.text('Câmera'), findsOneWidget);
  });

  testWidgets('a failed classification shows a retry affordance',
      (tester) async {
    await tester.pumpWidget(buildScreen(
      pickFromCamera: () async => XFile(samplePath),
      locate: () async => null,
      classify: (_) async => null,
    ));

    await capture(tester);

    expect(find.byKey(const Key('retryClassification')), findsOneWidget);
  });

  testWidgets('tapping retry reruns classification and shows the result',
      (tester) async {
    var calls = 0;
    await tester.pumpWidget(buildScreen(
      pickFromCamera: () async => XFile(samplePath),
      locate: () async => null,
      classify: (_) async {
        calls++;
        if (calls == 1) return null;
        return const InferenceResult(
          textureClass: 'Argilosa',
          confidenceScore: 0.9,
        );
      },
    ));

    await capture(tester);
    expect(find.byKey(const Key('retryClassification')), findsOneWidget);

    await tester.tap(find.byKey(const Key('retryClassification')));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }

    expect(find.textContaining('Argilosa'), findsOneWidget);
  });

  testWidgets('a hanging classification times out and shows the retry affordance',
      (tester) async {
    final never = Completer<InferenceResult?>();
    await tester.pumpWidget(buildScreen(
      pickFromCamera: () async => XFile(samplePath),
      locate: () async => null,
      classify: (_) => never.future,
    ));

    await capture(tester);
    expect(find.byKey(const Key('retryClassification')), findsNothing);

    await tester.pump(const Duration(seconds: 21));

    expect(find.byKey(const Key('retryClassification')), findsOneWidget);
  });

  testWidgets('a late result from a discarded capture does not overwrite a newer one',
      (tester) async {
    final firstClassify = Completer<InferenceResult?>();
    var calls = 0;
    await tester.pumpWidget(buildScreen(
      pickFromCamera: () async => XFile(samplePath),
      locate: () async => null,
      classify: (_) {
        calls++;
        if (calls == 1) return firstClassify.future;
        return Future.value(
          const InferenceResult(textureClass: 'Media', confidenceScore: 0.7),
        );
      },
    ));

    await capture(tester);
    await tester.tap(find.text('Descartar'));
    await tester.pump();
    await capture(tester);

    firstClassify.complete(
      const InferenceResult(textureClass: 'Argilosa', confidenceScore: 0.9),
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }

    expect(find.textContaining('Media'), findsOneWidget);
    expect(find.textContaining('Argilosa'), findsNothing);
  });
}
