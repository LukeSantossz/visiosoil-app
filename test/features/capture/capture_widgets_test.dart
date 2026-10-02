// Direct widget tests for the capture screen's extracted widgets (#120):
// CaptureImagePreview, CameraPermissionDeniedView, and CaptureActions.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:visiosoil_app/core/features/capture/widgets/camera_permission_denied_view.dart';
import 'package:visiosoil_app/core/features/capture/widgets/capture_actions.dart';
import 'package:visiosoil_app/core/features/capture/widgets/capture_image_preview.dart';
import 'package:visiosoil_app/core/constants/app_strings.dart';
import 'package:visiosoil_app/core/features/capture/widgets/location_rationale.dart';
import 'package:visiosoil_app/core/services/classification_report.dart';
import 'package:visiosoil_app/core/services/inference_service.dart';
import 'package:visiosoil_app/core/services/permission_service.dart';
import 'package:visiosoil_app/core/utils/formatters.dart';
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

    // GPS can answer while the address lookup cannot, offline above all; the
    // chip then shows the coordinates the record will keep (SPEC 0114).
    Widget locatedAt({String? address, double? latitude, double? longitude}) =>
        host(CaptureImagePreview(
          image: sampleImage,
          isLoading: false,
          isClassifying: false,
          address: address,
          latitude: latitude,
          longitude: longitude,
        ));

    testWidgets('the_preview_shows_coordinates_when_only_the_address_failed',
        (tester) async {
      await tester.pumpWidget(locatedAt(
        address: AppStrings.addressUnavailable,
        latitude: -23.5,
        longitude: -46.6,
      ));

      expect(find.text(Formatters.coordinates(-23.5, -46.6)), findsOneWidget);
      expect(find.text(AppStrings.addressUnavailable), findsNothing);
    });

    testWidgets('the_preview_keeps_its_fallback_without_a_location',
        (tester) async {
      await tester.pumpWidget(locatedAt());

      expect(find.text('Sem localização'), findsOneWidget);
    });

    testWidgets('the_preview_shows_a_resolved_address', (tester) async {
      await tester.pumpWidget(locatedAt(
        address: 'São Paulo',
        latitude: -23.5,
        longitude: -46.6,
      ));

      expect(find.text('São Paulo'), findsOneWidget);
      expect(find.text(Formatters.coordinates(-23.5, -46.6)), findsNothing);
    });

    // The chip names the cause, and only a cause a second run can fix offers
    // that run (SPEC 0105).
    Widget failedWith(ClassificationFailureCause cause, VoidCallback onRetry) =>
        host(CaptureImagePreview(
          image: sampleImage,
          isLoading: false,
          isClassifying: false,
          classificationFailed: true,
          classificationFailureCause: cause,
          onRetryClassification: onRetry,
        ));

    testWidgets('a_retake_cause_offers_no_retry', (tester) async {
      var retries = 0;
      await tester.pumpWidget(failedWith(
          ClassificationFailureCause.sheetNotFound, () => retries++));

      await tester.tap(find.text('Folha A4 não encontrada · tire outra foto'));
      await tester.pump();

      expect(retries, 0);
      expect(find.byKey(const Key('retryClassification')), findsNothing);
    });

    testWidgets('a_transient_cause_offers_a_retry', (tester) async {
      var retries = 0;
      await tester.pumpWidget(
          failedWith(ClassificationFailureCause.timeout, () => retries++));

      await tester
          .tap(find.text('Análise não terminou · tocar para tentar de novo'));
      await tester.pump();

      expect(retries, 1);
    });
  });

  group('CameraPermissionDeniedView', () {
    testWidgets('denied offers a retry', (tester) async {
      await tester.pumpWidget(host(CameraPermissionDeniedView(
        status: AppPermissionStatus.denied,
        onRetry: () {},
      )));

      expect(find.text('Acesso à câmera necessário'), findsOneWidget);
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

      expect(find.text('Câmera restrita'), findsOneWidget);
      expect(
        tester
            .widget<PermissionDeniedView>(find.byType(PermissionDeniedView))
            .onRetry,
        isNull,
      );
    });
  });

  group('CaptureActions', () {
    // Before a capture, while location is not granted, one line says why the
    // app will ask for it: Android's dialog carries no word from the app
    // (SPEC 0099).
    Widget actions({
      required bool hasImage,
      required AppPermissionStatus location,
    }) =>
        host(CaptureActions(
          hasImage: hasImage,
          isBusy: false,
          onCapture: () {},
          onSave: () {},
          onDiscard: () {},
          checkLocationPermission: () async => location,
        ));

    testWidgets(
        'the_location_line_shows_before_a_capture_while_location_is_not_granted',
        (tester) async {
      await tester.pumpWidget(
          actions(hasImage: false, location: AppPermissionStatus.denied));
      await tester.pump();

      expect(find.text(LocationRationale.message), findsOneWidget);
    });

    testWidgets('the_location_line_is_hidden_once_location_is_granted',
        (tester) async {
      await tester.pumpWidget(
          actions(hasImage: false, location: AppPermissionStatus.granted));
      await tester.pump();

      expect(find.text(LocationRationale.message), findsNothing);
    });

    testWidgets('the_location_line_is_hidden_once_a_photograph_exists',
        (tester) async {
      await tester.pumpWidget(
          actions(hasImage: true, location: AppPermissionStatus.denied));
      await tester.pump();

      expect(find.text(LocationRationale.message), findsNothing);
    });

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
      expect(find.text('Salvar registro'), findsNothing);
    });

    testWidgets('shows save and discard once an image exists', (tester) async {
      await tester.pumpWidget(host(CaptureActions(
        hasImage: true,
        isBusy: false,
        onCapture: () {},
        onSave: () {},
        onDiscard: () {},
      )));

      expect(find.text('Salvar registro'), findsOneWidget);
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
          (w) => w is VisioButton && w.label == 'Salvar registro',
        ),
      );
      expect(saveButton.onPressed, isNull,
          reason: 'a busy save button must be disabled');
    });
  });
}
