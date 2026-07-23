// Direct widget tests for the capture screen's extracted widgets (#120):
// CaptureImagePreview, CameraPermissionDeniedView, and CaptureActions.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:visiosoil_app/core/features/capture/widgets/camera_permission_denied_view.dart';
import 'package:visiosoil_app/core/features/capture/widgets/capture_actions.dart';
import 'package:visiosoil_app/core/features/capture/widgets/capture_image_preview.dart';
import 'package:visiosoil_app/core/services/inference_service.dart';
import 'package:visiosoil_app/core/services/permission_service.dart';
import 'package:visiosoil_app/core/widgets/permission_denied_view.dart';
import 'package:visiosoil_app/core/widgets/visio_button.dart';

Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  late File sampleImage;

  setUpAll(() {
    final dir = Directory.systemTemp.createTempSync('capture_widgets_test');
    sampleImage = File('${dir.path}/sample.png')
      ..writeAsBytesSync(img.encodePng(img.Image(width: 8, height: 8)));
  });

  group('CaptureImagePreview', () {
    testWidgets('shows the placeholder when there is no image', (tester) async {
      await tester.pumpWidget(host(const CaptureImagePreview(
        image: null,
        isLoading: false,
        isClassifying: false,
      )));

      expect(find.text('Selecione uma imagem'), findsOneWidget);
    });

    testWidgets('shows loading chips while locating and classifying',
        (tester) async {
      await tester.pumpWidget(host(CaptureImagePreview(
        image: sampleImage,
        isLoading: true,
        isClassifying: true,
      )));

      expect(find.text('Localizando...'), findsOneWidget);
      expect(find.text('Classificando...'), findsOneWidget);
    });

    testWidgets('shows the result chip and, on failure, a retry chip',
        (tester) async {
      await tester.pumpWidget(host(CaptureImagePreview(
        image: sampleImage,
        isLoading: false,
        isClassifying: false,
        classificationResult:
            const InferenceResult(textureClass: 'Argilosa', confidenceScore: 0.9),
      )));
      expect(find.textContaining('Argilosa'), findsOneWidget);

      await tester.pumpWidget(host(CaptureImagePreview(
        image: sampleImage,
        isLoading: false,
        isClassifying: false,
        classificationFailed: true,
      )));
      expect(find.byKey(const Key('retryClassification')), findsOneWidget);
    });
  });

  group('CameraPermissionDeniedView', () {
    testWidgets('denied offers a retry', (tester) async {
      await tester.pumpWidget(host(CameraPermissionDeniedView(
        status: AppPermissionStatus.denied,
        onRetry: () {},
      )));

      expect(find.text('Acesso a camera necessario'), findsOneWidget);
      expect(
        tester
            .widget<PermissionDeniedView>(find.byType(PermissionDeniedView))
            .onRetry,
        isNotNull,
      );
    });

    testWidgets('restricted shows its own copy and no retry', (tester) async {
      await tester.pumpWidget(host(CameraPermissionDeniedView(
        status: AppPermissionStatus.restricted,
        onRetry: () {},
      )));

      expect(find.text('Camera restrita'), findsOneWidget);
      expect(
        tester
            .widget<PermissionDeniedView>(find.byType(PermissionDeniedView))
            .onRetry,
        isNull,
      );
    });
  });

  group('CaptureActions', () {
    testWidgets('shows the camera button before an image exists',
        (tester) async {
      await tester.pumpWidget(host(CaptureActions(
        hasImage: false,
        isBusy: false,
        onCapture: () {},
        onSave: () {},
        onDiscard: () {},
      )));

      expect(find.text('Câmera'), findsOneWidget);
      expect(find.text('Salvar Registro'), findsNothing);
    });

    testWidgets('shows save and discard once an image exists', (tester) async {
      await tester.pumpWidget(host(CaptureActions(
        hasImage: true,
        isBusy: false,
        onCapture: () {},
        onSave: () {},
        onDiscard: () {},
      )));

      expect(find.text('Salvar Registro'), findsOneWidget);
      expect(find.text('Descartar'), findsOneWidget);
    });

    testWidgets('save is disabled while busy', (tester) async {
      await tester.pumpWidget(host(CaptureActions(
        hasImage: true,
        isBusy: true,
        onCapture: () {},
        onSave: () {},
        onDiscard: () {},
      )));

      // While busy the Save button hides its label and shows a spinner, so
      // assert the disabled state through the widget's own onPressed.
      final saveButton = tester.widget<VisioButton>(
        find.byWidgetPredicate(
          (w) => w is VisioButton && w.label == 'Salvar Registro',
        ),
      );
      expect(saveButton.onPressed, isNull,
          reason: 'a busy save button must be disabled');
    });
  });
}
