// Direct widget tests for the capture screen's extracted widgets (#120):
// CaptureImagePreview, CameraPermissionDeniedView, and CaptureActions.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
import 'package:visiosoil_app/core/theme/app_motion.dart';
import 'package:visiosoil_app/core/utils/formatters.dart';
import 'package:visiosoil_app/core/widgets/permission_denied_view.dart';
import 'package:visiosoil_app/core/widgets/visio_button.dart';

import '../../support/large_text.dart';

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

  // At 200 % text on a phone, the capture widgets still lay out, and a chip's
  // address is not cut (SPEC 0121).
  group('large text', () {
    testWidgets('capture_scales_to_200_percent', (tester) async {
      useLargeTextOnAPhone(tester);

      for (final hasImage in [false, true]) {
        await tester.pumpWidget(host(CaptureActions(
          hasImage: hasImage,
          isBusy: false,
          onCapture: () {},
          onSave: () {},
          onDiscard: () {},
          checkLocationPermission: () async => AppPermissionStatus.denied,
        )));
        await tester.pump();
        expect(tester.takeException(), isNull, reason: 'hasImage: $hasImage');
      }
    });

    // The address appears nowhere else on capture, so a long one is shown
    // whole at 200 %, not cut.
    testWidgets('capture_chip_is_not_cut', (tester) async {
      useLargeTextOnAPhone(tester);
      const address =
          'Estrada Municipal PIR-020, km 12, Bairro Santa Olímpia, Piracicaba, SP';

      await tester.pumpWidget(host(CaptureImagePreview(
        image: sampleImage,
        isLoading: false,
        isClassifying: false,
        address: address,
        latitude: -22.7,
        longitude: -47.6,
      )));

      expect(
        tester.renderObject<RenderParagraph>(find.text(address))
            .didExceedMaxLines,
        isFalse,
      );
      expect(tester.takeException(), isNull);
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

    // The first camera request carries the app's own reason too, shown
    // before "Câmera" is tapped, which is what starts the request (SPEC 0115).
    Widget cameraActions({
      bool hasImage = false,
      Future<AppPermissionStatus> Function()? camera,
    }) =>
        host(CaptureActions(
          hasImage: hasImage,
          isBusy: false,
          onCapture: () {},
          onSave: () {},
          onDiscard: () {},
          checkCameraPermission: camera,
          checkLocationPermission: () async => AppPermissionStatus.denied,
        ));

    testWidgets('permission_priming_precedes_system_dialog', (tester) async {
      await tester.pumpWidget(
          cameraActions(camera: () async => AppPermissionStatus.denied));
      await tester.pump();

      expect(find.text(_cameraLine), findsOneWidget);
      expect(
        tester.getTopLeft(find.text(_cameraLine)).dy,
        lessThan(tester.getTopLeft(find.text(LocationRationale.message)).dy),
        reason: 'the camera is asked for first, so its line comes first',
      );
    });

    testWidgets('the_camera_line_is_hidden_once_the_camera_is_granted',
        (tester) async {
      await tester.pumpWidget(
          cameraActions(camera: () async => AppPermissionStatus.granted));
      await tester.pump();

      expect(find.text(_cameraLine), findsNothing);
    });

    testWidgets('the_camera_line_is_hidden_when_the_status_is_unreadable',
        (tester) async {
      await tester.pumpWidget(cameraActions(
          camera: () async => throw Exception('plugin unavailable')));
      await tester.pump();

      expect(find.text(_cameraLine), findsNothing);
    });

    testWidgets('the_camera_line_is_hidden_once_a_photograph_exists',
        (tester) async {
      await tester.pumpWidget(cameraActions(
          hasImage: true, camera: () async => AppPermissionStatus.denied));
      await tester.pump();

      expect(find.text(_cameraLine), findsNothing);
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

  // SPEC 0118: the retry chip is a labelled button with a 48 dp target, and
  // Discard keeps 24 dp from Save.
  testWidgets('retry_chip_is_accessible', (tester) async {
    final semantics = tester.ensureSemantics();
    var retries = 0;
    await tester.pumpWidget(host(CaptureImagePreview(
      image: sampleImage,
      isLoading: false,
      isClassifying: false,
      classificationFailed: true,
      classificationFailureCause: ClassificationFailureCause.timeout,
      onRetryClassification: () => retries++,
    )));

    const label = 'Análise não terminou · tocar para tentar de novo';
    final chip = find.bySemanticsLabel(label);
    expect(chip, findsOneWidget);
    expect(tester.getSemantics(chip), isSemantics(isButton: true));
    expect(
      tester.getSize(find.byKey(const Key('retryClassification'))).height,
      greaterThanOrEqualTo(48),
    );
    await tester.tap(find.byKey(const Key('retryClassification')));
    expect(retries, 1);
    semantics.dispose();
  });

  testWidgets('destructive_separated', (tester) async {
    await tester.pumpWidget(host(CaptureActions(
      hasImage: true,
      isBusy: false,
      onCapture: () {},
      onSave: () {},
      onDiscard: () {},
    )));

    Rect button(String label) => tester.getRect(find.byWidgetPredicate(
          (w) => w is VisioButton && w.label == label,
        ));
    expect(
      button('Descartar').top - button('Salvar registro').bottom,
      greaterThanOrEqualTo(24),
    );
  });

  // Capture's status chips crossfade over AppMotion.base, and the screen
  // reader hears only the new label (SPEC 0134).
  group('status chip crossfade', () {
    Widget inPhase(ClassificationPhase phase) => host(CaptureImagePreview(
          image: sampleImage,
          isLoading: false,
          isClassifying: true,
          classificationPhase: phase,
        ));

    Widget locating({required bool isLoading}) => host(CaptureImagePreview(
          image: sampleImage,
          isLoading: isLoading,
          isClassifying: false,
          address: 'Fazenda Boa Vista',
        ));

    testWidgets('phase_label_crossfades', (tester) async {
      await tester.pumpWidget(inPhase(ClassificationPhase.readingPhotograph));
      await tester.pumpWidget(inPhase(ClassificationPhase.findingSheet));
      await tester.pump(AppMotion.base ~/ 2);
      expect(find.text('Lendo a foto...'), findsOneWidget);
      expect(find.text('Procurando a folha A4...'), findsOneWidget);

      await tester.pump(AppMotion.base);
      expect(find.text('Lendo a foto...'), findsNothing);
      expect(find.text('Procurando a folha A4...'), findsOneWidget);
    });

    testWidgets('the location chip crossfades too', (tester) async {
      await tester.pumpWidget(locating(isLoading: true));
      await tester.pumpWidget(locating(isLoading: false));
      await tester.pump(AppMotion.base ~/ 2);
      expect(find.text('Localizando...'), findsOneWidget);
      expect(find.text('Fazenda Boa Vista'), findsOneWidget);

      await tester.pump(AppMotion.base);
      expect(find.text('Localizando...'), findsNothing);
      expect(find.text('Fazenda Boa Vista'), findsOneWidget);
    });

    // Retry, then the same failure within the crossfade: the returning label
    // is a new chip, not a clash with the one still fading out.
    testWidgets('a_label_back_mid_crossfade_is_a_new_chip', (tester) async {
      await tester.pumpWidget(inPhase(ClassificationPhase.readingPhotograph));
      await tester.pumpWidget(inPhase(ClassificationPhase.findingSheet));
      await tester.pump(AppMotion.base ~/ 4);
      await tester.pumpWidget(inPhase(ClassificationPhase.readingPhotograph));
      await tester.pump(AppMotion.base ~/ 4);
      expect(tester.takeException(), isNull);

      await tester.pump(AppMotion.base);
      expect(find.text('Lendo a foto...'), findsOneWidget);
      expect(find.text('Procurando a folha A4...'), findsNothing);
    });

    testWidgets('crossfade_announces_only_the_new_label', (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(inPhase(ClassificationPhase.readingPhotograph));
      await tester.pumpWidget(inPhase(ClassificationPhase.findingSheet));
      await tester.pump(AppMotion.base ~/ 2);

      expect(find.text('Lendo a foto...'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('Lendo a foto')), findsNothing);
      expect(
        find.bySemanticsLabel(RegExp('Procurando a folha A4')),
        findsOneWidget,
      );
      semantics.dispose();
    });

    testWidgets('fading_chip_takes_no_tap', (tester) async {
      var retries = 0;
      Widget preview({required bool retrying}) => host(CaptureImagePreview(
            image: sampleImage,
            isLoading: false,
            isClassifying: retrying,
            classificationFailed: !retrying,
            onRetryClassification: () => retries++,
          ));
      await tester.pumpWidget(preview(retrying: false));
      await tester.pumpWidget(preview(retrying: true));
      await tester.pump(AppMotion.base ~/ 2);

      expect(find.byKey(const Key('retryClassification')), findsOneWidget);
      await tester.tap(
        find.byKey(const Key('retryClassification')),
        warnIfMissed: false,
      );
      expect(retries, 0);
    });

    testWidgets('crossfade_respects_reduced_motion', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      await tester.pumpWidget(inPhase(ClassificationPhase.readingPhotograph));
      await tester.pumpWidget(inPhase(ClassificationPhase.findingSheet));
      await tester.pump();

      expect(find.text('Lendo a foto...'), findsNothing);
      expect(find.text('Procurando a folha A4...'), findsOneWidget);
    });
  });
}

/// The camera rationale's pt-BR copy (SPEC 0115). Kept in step with
/// `CameraRationale.message`.
const _cameraLine =
    'A câmera fotografa a amostra sobre a folha A4 para classificar a textura '
    'do solo.';
