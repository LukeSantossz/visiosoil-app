import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:visiosoil_app/core/constants/app_strings.dart';
import 'package:visiosoil_app/core/data/repositories/soil_record_repository.dart';
import 'package:visiosoil_app/core/features/capture/capture_guide_screen.dart';
import 'package:visiosoil_app/core/features/capture/capture_screen.dart';
import 'package:visiosoil_app/core/features/capture/capture_ui_state.dart';
import 'package:visiosoil_app/core/features/capture/widgets/capture_image_preview.dart';
import 'package:visiosoil_app/core/services/classification_report.dart';
import 'package:visiosoil_app/core/services/inference_service.dart';
import 'package:visiosoil_app/core/services/permission_service.dart';
import 'package:visiosoil_app/core/theme/app_motion.dart';
import 'package:visiosoil_app/core/utils/formatters.dart';
import 'package:visiosoil_app/core/widgets/visio_button.dart';
import 'package:visiosoil_app/models/class_score.dart';
import 'package:visiosoil_app/models/soil_record.dart';
import 'package:visiosoil_app/providers/capture_guide_store_provider.dart';
import 'package:visiosoil_app/providers/inference_provider.dart';
import 'package:visiosoil_app/providers/soil_record_repository_provider.dart';

import '../../support/fake_capture_guide_store.dart';
import '../../support/fake_soil_record_repository.dart';
import '../../support/guidelines.dart';
import '../../support/haptics_recorder.dart';

/// Answers with a report built from the handler's result: a result is `ok`,
/// and `null` stands for a run that failed. The cause is fixed because none of
/// these tests is about which one it was; the one that is sets its own.
class _FakeInference extends InferenceService {
  _FakeInference(this._handler, {this.cause = ClassificationFailureCause.timeout});

  final Future<InferenceResult?> Function(String imagePath) _handler;
  final ClassificationFailureCause cause;

  /// The `onPhase` each call received, in call order, so a test can post a
  /// phase as the isolate would (SPEC 0116).
  final List<ClassificationPhaseCallback?> phaseCallbacks = [];

  @override
  Future<ClassificationReport> classify(
    String imagePath, {
    Duration? timeout,
    InferenceIsolateEntry? entryPoint,
    ClassificationPhaseCallback? onPhase,
  }) async {
    phaseCallbacks.add(onPhase);
    final result = await _handler(imagePath);
    return result == null
        ? ClassificationReport.failed(cause)
        : ClassificationReport.ok(result);
  }
}

/// Holds every `create` until [_gate] completes, so a test can act while a
/// save is in flight.
class _GatedSoilRecordRepository extends FakeSoilRecordRepository {
  _GatedSoilRecordRepository(this._gate);

  final Future<void> _gate;

  @override
  Future<SoilRecord> create(SoilRecord record) async {
    final saved = super.create(record);
    await _gate;
    return saved;
  }
}

// A capture test is about what follows the camera, so the guide that precedes
// the first one is already seen; the guide's own tests seed it unseen
// (SPEC 0142).
Override _guideAlreadySeen() =>
    captureGuideStoreProvider.overrideWithValue(FakeCaptureGuideStore(seen: true));

// Every test captures the same sample file, so the harness never lets the
// screen delete it: a test that is about deletion passes its own deleter.
Future<void> _keepPickedFile(String _) async {}

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
    SoilRecordRepository? repository,
    PickedFileDeleter deletePickedFile = _keepPickedFile,
    String? initialImagePath,
    ClassificationFailureCause failureCause = ClassificationFailureCause.timeout,
    _FakeInference? inference,
    ThemeData? theme,
  }) {
    return ProviderScope(
      overrides: [
        _guideAlreadySeen(),
        inferenceServiceProvider.overrideWithValue(
            inference ?? _FakeInference(classify, cause: failureCause)),
        if (repository != null)
          soilRecordRepositoryProvider.overrideWithValue(repository),
      ],
      child: MaterialApp(
        theme: theme,
        home: CaptureScreen(
          pickFromCamera: pickFromCamera,
          locate: locate,
          checkCameraPermission: () async => AppPermissionStatus.granted,
          requestCameraPermission: () async => AppPermissionStatus.granted,
          deletePickedFile: deletePickedFile,
          initialImagePath: initialImagePath,
        ),
      ),
    );
  }

  // Same as buildScreen but inside a GoRouter, so a successful save has a
  // details route to open (SPEC 0132) and a route underneath to go back to.
  Widget buildRouted({
    required CameraImagePicker pickFromCamera,
    required LocationResolver locate,
    required Future<InferenceResult?> Function(String) classify,
    SoilRecordRepository? repository,
    PickedFileDeleter deletePickedFile = _keepPickedFile,
  }) {
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, _) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => context.push('/capture'),
                child: const Text('open capture'),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/capture',
          builder: (_, _) => CaptureScreen(
            pickFromCamera: pickFromCamera,
            locate: locate,
            checkCameraPermission: () async => AppPermissionStatus.granted,
            requestCameraPermission: () async => AppPermissionStatus.granted,
            deletePickedFile: deletePickedFile,
          ),
        ),
        GoRoute(
          path: '/details',
          builder: (_, state) => Scaffold(
            appBar: AppBar(),
            body: Text('DETAILS_STUB ${state.extra}'),
          ),
        ),
      ],
    );
    return ProviderScope(
      overrides: [
        _guideAlreadySeen(),
        inferenceServiceProvider.overrideWithValue(_FakeInference(classify)),
        if (repository != null)
          soilRecordRepositoryProvider.overrideWithValue(repository),
      ],
      child: MaterialApp.router(routerConfig: router),
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

  testWidgets('capture_screen_renders_a_failed_report_without_a_result',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        _guideAlreadySeen(),
        inferenceServiceProvider.overrideWithValue(_FakeInference(
          (_) async => null,
          cause: ClassificationFailureCause.sheetNotFound,
        )),
      ],
      child: MaterialApp(
        home: CaptureScreen(
          pickFromCamera: () async => XFile(samplePath),
          locate: () async => null,
          checkCameraPermission: () async => AppPermissionStatus.granted,
          requestCameraPermission: () async => AppPermissionStatus.granted,
        ),
      ),
    ));

    await capture(tester);

    // The cause's chip, which offers no retry (SPEC 0105), and no result.
    expect(find.text('Folha A4 não encontrada · tire outra foto'),
        findsOneWidget);
    expect(find.byKey(const Key('retryClassification')), findsNothing);
    for (final label in ['Arenosa', 'Argilosa', 'Media']) {
      expect(find.textContaining(label), findsNothing);
    }
    // The state class is private; `uiState` is its test-only view.
    final uiState =
        (tester.state(find.byType(CaptureScreen)) as dynamic).uiState
            as CaptureUiState;
    expect(uiState.classificationFailureCause,
        ClassificationFailureCause.sheetNotFound);
    expect(uiState.classificationResult, isNull);
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

  testWidgets(
      'a double tap on retry starts one classification, and retry works again '
      'once it settles', (tester) async {
    var calls = 0;
    var gate = Completer<InferenceResult?>();
    await tester.pumpWidget(buildScreen(
      pickFromCamera: () async => XFile(samplePath),
      locate: () async => null,
      classify: (_) {
        calls++;
        // The automatic run after capture fails, surfacing the retry chip.
        if (calls == 1) return Future<InferenceResult?>.value(null);
        return gate.future;
      },
    ));

    await capture(tester);
    expect(calls, 1);
    expect(find.byKey(const Key('retryClassification')), findsOneWidget);

    // Both taps land in the same frame: no pump has run in between, so the chip
    // is still in the tree for the second hit-test even though the first tap
    // already set the in-flight flag. This is the window the guard closes.
    await tester.tap(find.byKey(const Key('retryClassification')));
    await tester.tap(find.byKey(const Key('retryClassification')));
    await tester.pump();

    expect(calls, 2, reason: 'the second tap must be rejected while in flight');

    // Settle the retry as another failure, which brings the chip back once
    // the last one has faded out (SPEC 0134).
    gate.complete(null);
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    await tester.pump(AppMotion.base);
    expect(find.byKey(const Key('retryClassification')), findsOneWidget);

    // The guard must have cleared: a later tap is accepted.
    gate = Completer<InferenceResult?>();
    await tester.tap(find.byKey(const Key('retryClassification')));
    await tester.pump();

    expect(calls, 3, reason: 'the guard must clear once the run settles');

    gate.complete(null);
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
  });

  testWidgets('the screen applies no classification deadline of its own',
      (tester) async {
    final pending = Completer<InferenceResult?>();
    await tester.pumpWidget(buildScreen(
      pickFromCamera: () async => XFile(samplePath),
      locate: () async => null,
      classify: (_) => pending.future,
    ));

    await capture(tester);
    expect(find.byKey(const Key('retryClassification')), findsNothing);

    // Well past the 20s deadline the screen used to impose. The single deadline
    // now lives in InferenceService, which is the only layer holding the isolate
    // handle and so the only one that can stop the work rather than abandon it.
    await tester.pump(const Duration(seconds: 25));
    expect(find.byKey(const Key('retryClassification')), findsNothing,
        reason: 'the screen must wait for the service instead of timing out');

    // The service resolving to null — its own timeout, or a failed run — is
    // what surfaces the retry affordance.
    pending.complete(null);
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }

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

  // The chip names the step the isolate reports, not a timer (SPEC 0116).
  group('classification phases', () {
    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 10));
      }
    }

    testWidgets('phases_are_named', (tester) async {
      final gate = Completer<InferenceResult?>();
      final inference = _FakeInference((_) => gate.future);
      await tester.pumpWidget(buildScreen(
        pickFromCamera: () async => XFile(samplePath),
        locate: () async => null,
        classify: (_) => gate.future,
        inference: inference,
      ));

      await capture(tester);
      expect(find.text('Classificando...'), findsOneWidget);

      // Each phase crossfades into the next over AppMotion.base (SPEC 0134).
      inference.phaseCallbacks.single!(ClassificationPhase.findingSheet);
      await settle(tester);
      await tester.pump(AppMotion.base);
      expect(find.text('Procurando a folha A4...'), findsOneWidget);
      expect(find.text('Classificando...'), findsNothing);

      inference.phaseCallbacks.single!(ClassificationPhase.describingTexture);
      await settle(tester);
      await tester.pump(AppMotion.base);
      expect(find.text('Descrevendo a textura...'), findsOneWidget);
      expect(find.text('Procurando a folha A4...'), findsNothing);

      gate.complete(null);
      await settle(tester);
    });

    testWidgets('phase_changes_announced', (tester) async {
      final gate = Completer<InferenceResult?>();
      final inference = _FakeInference((_) => gate.future);
      await tester.pumpWidget(buildScreen(
        pickFromCamera: () async => XFile(samplePath),
        locate: () async => null,
        classify: (_) => gate.future,
        inference: inference,
      ));

      await capture(tester);
      inference.phaseCallbacks.single!(ClassificationPhase.scoring);
      await settle(tester);

      expect(
        find.ancestor(
          of: find.text('Calculando a classe...'),
          matching: find.byWidgetPredicate(
            (widget) => widget is Semantics && widget.properties.liveRegion == true,
          ),
        ),
        findsOneWidget,
      );

      gate.complete(null);
      await settle(tester);
    });

    testWidgets('a_superseded_capture_cannot_move_the_phase', (tester) async {
      final first = Completer<InferenceResult?>();
      final second = Completer<InferenceResult?>();
      var calls = 0;
      Future<InferenceResult?> classify(String _) =>
          ++calls == 1 ? first.future : second.future;
      final inference = _FakeInference(classify);
      await tester.pumpWidget(buildScreen(
        pickFromCamera: () async => XFile(samplePath),
        locate: () async => null,
        classify: classify,
        inference: inference,
      ));

      await capture(tester);
      await tester.tap(find.text('Descartar'));
      await tester.pump();
      await capture(tester);

      inference.phaseCallbacks.first!(ClassificationPhase.scoring);
      await settle(tester);
      expect(find.text('Calculando a classe...'), findsNothing);

      inference.phaseCallbacks.last!(ClassificationPhase.findingSheet);
      await settle(tester);
      expect(find.text('Procurando a folha A4...'), findsOneWidget);

      first.complete(null);
      second.complete(null);
      await settle(tester);
    });
  });

  testWidgets('a save failure shows an error snackbar and keeps the screen for retry',
      (tester) async {
    final repository = FakeSoilRecordRepository()..throwOnCreate = true;
    await tester.pumpWidget(buildScreen(
      pickFromCamera: () async => XFile(samplePath),
      locate: () async => null,
      classify: (_) async => null,
      repository: repository,
    ));

    await capture(tester);
    await tester.tap(find.text('Salvar registro'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }

    // Error feedback is shown; the image is kept and we did not navigate away
    // (the Save button only renders while an image is present on this screen).
    expect(
      find.text('Não foi possível salvar o registro. Tente novamente.'),
      findsOneWidget,
    );
    expect(find.text('Salvar registro'), findsOneWidget);

    // The Save button is re-enabled: a second tap retries the write.
    await tester.tap(find.text('Salvar registro'));
    await tester.pump();
    expect(repository.createCalls.length, 2);
  });

  // Location is optional, so Save waits for the classification and not for
  // the GPS (SPEC 0117).
  group('saving while locating', () {
    VisioButton saveButton(WidgetTester tester) => tester.widget<VisioButton>(
          find.byWidgetPredicate(
            (w) => w is VisioButton && w.label == 'Salvar registro',
          ),
        );

    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 10));
      }
    }

    testWidgets('save_not_gated_by_location', (tester) async {
      final repository = FakeSoilRecordRepository();
      final locateGate = Completer<LocationReading?>();
      await tester.pumpWidget(buildRouted(
        pickFromCamera: () async => XFile(samplePath),
        locate: () => locateGate.future,
        classify: (_) async =>
            const InferenceResult(textureClass: 'Media', confidenceScore: 0.7),
        repository: repository,
      ));

      await tester.tap(find.text('open capture'));
      await tester.pumpAndSettle();
      await capture(tester);
      expect(find.text('Localizando...'), findsOneWidget);
      expect(saveButton(tester).onPressed, isNotNull);

      await tester.tap(find.text('Salvar registro'));
      await settle(tester);
      await tester.pumpAndSettle();

      expect(repository.createCalls, hasLength(1));
      final saved = repository.createCalls.single;
      expect(saved.latitude, isNull);
      expect(saved.longitude, isNull);
      expect(saved.address, AppStrings.addressUnavailable);
      expect(saved.textureClass, 'Media');

      locateGate.complete(null);
      await tester.pumpAndSettle();
    });

    testWidgets('save_still_waits_for_the_classification', (tester) async {
      final classifyGate = Completer<InferenceResult?>();
      await tester.pumpWidget(buildScreen(
        pickFromCamera: () async => XFile(samplePath),
        locate: () async => (latitude: -23.5, longitude: -46.6, address: 'X'),
        classify: (_) => classifyGate.future,
      ));

      await capture(tester);
      await settle(tester);

      expect(saveButton(tester).onPressed, isNull);

      classifyGate.complete(null);
      await settle(tester);
    });

    // A retry and a save in the same frame: the save's callback is from the
    // last build, so it must check the state it runs against.
    testWidgets('a_save_tapped_right_after_a_retry_waits_for_it',
        (tester) async {
      final repository = FakeSoilRecordRepository();
      final locateGate = Completer<LocationReading?>();
      final retryGate = Completer<InferenceResult?>();
      var calls = 0;
      await tester.pumpWidget(buildScreen(
        pickFromCamera: () async => XFile(samplePath),
        locate: () => locateGate.future,
        classify: (_) => ++calls == 1 ? Future.value(null) : retryGate.future,
        repository: repository,
      ));

      await capture(tester);
      expect(find.byKey(const Key('retryClassification')), findsOneWidget);

      await tester.tap(find.byKey(const Key('retryClassification')));
      await tester.tap(find.text('Salvar registro'));
      await settle(tester);

      expect(repository.createCalls, isEmpty);

      retryGate.complete(null);
      locateGate.complete(null);
      await settle(tester);
    });

    testWidgets('a_late_reading_after_a_failed_save_is_kept', (tester) async {
      final repository = FakeSoilRecordRepository()..throwOnCreate = true;
      final locateGate = Completer<LocationReading?>();
      await tester.pumpWidget(buildScreen(
        pickFromCamera: () async => XFile(samplePath),
        locate: () => locateGate.future,
        classify: (_) async => null,
        repository: repository,
      ));

      await capture(tester);
      await tester.tap(find.text('Salvar registro'));
      await settle(tester);
      expect(repository.createCalls, hasLength(1));

      locateGate.complete(
        (latitude: -23.5, longitude: -46.6, address: 'São Paulo'),
      );
      await settle(tester);

      expect(find.text('São Paulo'), findsOneWidget);
    });
  });

  // A confirmed save replaces capture with the new record's details, given the
  // id `create` returned (SPEC 0132). The fake numbers records from 1.
  testWidgets('save_opens_details', (tester) async {
    final repository = FakeSoilRecordRepository();
    await tester.pumpWidget(buildRouted(
      pickFromCamera: () async => XFile(samplePath),
      locate: () async => null,
      classify: (_) async => null,
      repository: repository,
    ));

    await tester.tap(find.text('open capture'));
    await tester.pumpAndSettle();
    await capture(tester);
    await tester.tap(find.text('Salvar registro'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    await tester.pumpAndSettle();

    expect(repository.createCalls.length, 1);
    expect(find.text('Registro salvo com sucesso!'), findsOneWidget);
    expect(find.text('DETAILS_STUB 1'), findsOneWidget);
    expect(find.byType(CaptureScreen), findsNothing);

    // Capture was replaced, not covered: back returns to what opened it.
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('open capture'), findsOneWidget);
    expect(find.byType(CaptureScreen), findsNothing);
  });

  testWidgets('failed_save_stays', (tester) async {
    final repository = FakeSoilRecordRepository()..throwOnCreate = true;
    await tester.pumpWidget(buildRouted(
      pickFromCamera: () async => XFile(samplePath),
      locate: () async => null,
      classify: (_) async => null,
      repository: repository,
    ));

    await tester.tap(find.text('open capture'));
    await tester.pumpAndSettle();
    await capture(tester);
    await tester.tap(find.text('Salvar registro'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    await tester.pumpAndSettle();

    expect(
      find.text('Não foi possível salvar o registro. Tente novamente.'),
      findsOneWidget,
    );
    expect(find.text('Salvar registro'), findsOneWidget);
    expect(find.textContaining('DETAILS_STUB'), findsNothing);
  });

  // The photograph's return and a confirmed save each make one light haptic,
  // and a result arriving one medium (SPEC 0126).
  group('haptics', () {
    int count(List<String> haptics, String type) =>
        haptics.where((h) => h == 'HapticFeedbackType.$type').length;

    testWidgets('photograph_and_save_confirm', (tester) async {
      final haptics = recordHaptics(tester);
      await tester.pumpWidget(buildRouted(
        pickFromCamera: () async => XFile(samplePath),
        locate: () async => null,
        classify: (_) async => null,
        repository: FakeSoilRecordRepository(),
      ));
      await tester.tap(find.text('open capture'));
      await tester.pumpAndSettle();

      await capture(tester);
      expect(count(haptics, 'lightImpact'), 1);

      await tester.tap(find.text('Salvar registro'));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 10));
      }
      await tester.pumpAndSettle();
      expect(find.text('Registro salvo com sucesso!'), findsOneWidget);
      expect(count(haptics, 'lightImpact'), 2);
    });

    testWidgets('result_arrival', (tester) async {
      final haptics = recordHaptics(tester);
      await tester.pumpWidget(buildScreen(
        pickFromCamera: () async => XFile(samplePath),
        locate: () async => null,
        classify: (_) async => const InferenceResult(
          textureClass: 'Argilosa',
          confidenceScore: 0.9,
        ),
      ));

      await capture(tester);

      expect(count(haptics, 'mediumImpact'), 1);
    });

    testWidgets('result_arrival: a failure makes none', (tester) async {
      final haptics = recordHaptics(tester);
      await tester.pumpWidget(buildScreen(
        pickFromCamera: () async => XFile(samplePath),
        locate: () async => null,
        classify: (_) async => null,
      ));

      await capture(tester);

      expect(count(haptics, 'mediumImpact'), 0);
    });
  });

  testWidgets('saving_a_classified_capture_persists_the_distribution',
      (tester) async {
    // SPEC 0097. The result carries the distribution highest first; the record
    // keeps it in the contract's order, with the versions that scored it.
    const result = InferenceResult(
      textureClass: 'Media',
      confidenceScore: 0.61,
      distribution: [
        ClassScore(label: 'Media', probability: 0.61),
        ClassScore(label: 'Argilosa', probability: 0.2),
        ClassScore(label: 'Arenosa', probability: 0.12),
        ClassScore(label: 'Muito Argilosa', probability: 0.07),
      ],
      classes: ['Arenosa', 'Media', 'Muito Argilosa', 'Argilosa'],
      modelVersion: '1.0.0',
      datasetVersion: 'v1',
    );
    final repository = FakeSoilRecordRepository();
    await tester.pumpWidget(buildRouted(
      pickFromCamera: () async => XFile(samplePath),
      locate: () async => null,
      classify: (_) async => result,
      repository: repository,
    ));

    await tester.tap(find.text('open capture'));
    await tester.pumpAndSettle();
    await capture(tester);
    await tester.tap(find.text('Salvar registro'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    await tester.pumpAndSettle();

    final saved = repository.createCalls.single;
    expect(saved.textureClass, 'Media');
    expect(saved.classDistribution, const [
      ClassScore(label: 'Arenosa', probability: 0.12),
      ClassScore(label: 'Media', probability: 0.61),
      ClassScore(label: 'Muito Argilosa', probability: 0.07),
      ClassScore(label: 'Argilosa', probability: 0.2),
    ]);
    expect(saved.modelVersion, '1.0.0');
    expect(saved.datasetVersion, 'v1');
  });

  testWidgets('the default camera picker requests images without full metadata',
      (tester) async {
    // In a unit test ImagePickerPlatform.instance is MethodChannelImagePicker,
    // which invokes `pickImage` on this channel with a `requestFullMetadata`
    // arg. Intercept it to assert the flag the real default picker sends.
    const channel = MethodChannel('plugins.flutter.io/image_picker');
    Object? requestedFullMetadata;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (call) async {
        if (call.method == 'pickImage') {
          requestedFullMetadata =
              (call.arguments as Map)['requestFullMetadata'];
          return samplePath;
        }
        return null;
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));

    // pickFromCamera is left as the real default on purpose, so the capture
    // drives ImagePicker().pickImage down to the intercepted channel.
    await tester.pumpWidget(ProviderScope(
      overrides: [
        _guideAlreadySeen(),
        inferenceServiceProvider
            .overrideWithValue(_FakeInference((_) async => null)),
      ],
      child: MaterialApp(
        home: CaptureScreen(
          locate: () async => null,
          checkCameraPermission: () async => AppPermissionStatus.granted,
          requestCameraPermission: () async => AppPermissionStatus.granted,
        ),
      ),
    ));

    await capture(tester);

    expect(requestedFullMetadata, isFalse);
  });

  testWidgets('a denied camera permission shows the permission-denied view',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        _guideAlreadySeen(),
        inferenceServiceProvider
            .overrideWithValue(_FakeInference((_) async => null)),
      ],
      child: MaterialApp(
        home: CaptureScreen(
          pickFromCamera: () async => null,
          locate: () async => null,
          checkCameraPermission: () async => AppPermissionStatus.denied,
          requestCameraPermission: () async => AppPermissionStatus.denied,
        ),
      ),
    ));

    await capture(tester);

    expect(find.text('Acesso à câmera necessário'), findsOneWidget);
    expect(find.text('Câmera'), findsNothing);
  });

  testWidgets('the location chip shows loading, then the resolved address',
      (tester) async {
    final locateGate = Completer<LocationReading?>();
    await tester.pumpWidget(buildScreen(
      pickFromCamera: () async => XFile(samplePath),
      locate: () => locateGate.future,
      classify: (_) async => null,
    ));

    await capture(tester);
    expect(find.text('Localizando...'), findsOneWidget);

    locateGate.complete(
      (latitude: -23.5, longitude: -46.6, address: 'São Paulo'),
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    // The address crossfades in over AppMotion.base (SPEC 0134).
    await tester.pump(AppMotion.base);

    expect(find.text('São Paulo'), findsOneWidget);
    expect(find.text('Localizando...'), findsNothing);
  });

  testWidgets('the_capture_screen_shows_coordinates_when_geocoding_failed',
      (tester) async {
    await tester.pumpWidget(buildScreen(
      pickFromCamera: () async => XFile(samplePath),
      // Typed as the resolver's nullable reading, as `_defaultLocate` is, so
      // the screen's null-returning timeout fallback type-checks.
      locate: () => Future<LocationReading?>.value((
        latitude: -23.5,
        longitude: -46.6,
        address: AppStrings.addressUnavailable,
      )),
      classify: (_) async => null,
    ));

    await capture(tester);
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }

    expect(find.text(Formatters.coordinates(-23.5, -46.6)), findsOneWidget);
    expect(find.text(AppStrings.addressUnavailable), findsNothing);
  });

  // The picker's file carries the original EXIF, GPS included; the record
  // points at the durable copy, so the screen deletes the picker's file once
  // it is no longer needed (SPEC 0094).
  group('picked file', () {
    Future<void> openAndSave(WidgetTester tester) async {
      await tester.tap(find.text('open capture'));
      await tester.pumpAndSettle();
      await capture(tester);
      await tester.tap(find.text('Salvar registro'));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 10));
      }
      await tester.pumpAndSettle();
    }

    testWidgets('a_saved_capture_deletes_the_picker_file', (tester) async {
      final repository = FakeSoilRecordRepository();
      final deleted = <String>[];
      int? createsAtDeletion;
      await tester.pumpWidget(buildRouted(
        pickFromCamera: () async => XFile(samplePath),
        locate: () async => null,
        classify: (_) async => null,
        repository: repository,
        deletePickedFile: (path) async {
          deleted.add(path);
          createsAtDeletion = repository.createCalls.length;
        },
      ));

      await openAndSave(tester);

      expect(deleted, [samplePath]);
      expect(createsAtDeletion, 1);
    });

    testWidgets('a_failed_save_keeps_the_picker_file', (tester) async {
      final repository = FakeSoilRecordRepository()..throwOnCreate = true;
      final deleted = <String>[];
      await tester.pumpWidget(buildScreen(
        pickFromCamera: () async => XFile(samplePath),
        locate: () async => null,
        classify: (_) async => null,
        repository: repository,
        deletePickedFile: (path) async => deleted.add(path),
      ));

      await capture(tester);
      await tester.tap(find.text('Salvar registro'));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 10));
      }

      expect(repository.createCalls, hasLength(1));
      expect(deleted, isEmpty);
    });

    testWidgets('a_discarded_capture_deletes_the_picker_file', (tester) async {
      final deleted = <String>[];
      await tester.pumpWidget(buildScreen(
        pickFromCamera: () async => XFile(samplePath),
        locate: () async => null,
        classify: (_) async => null,
        deletePickedFile: (path) async => deleted.add(path),
      ));

      await capture(tester);
      await tester.tap(find.text('Descartar'));
      await tester.pump();

      expect(deleted, [samplePath]);
      expect(find.text('Câmera'), findsOneWidget);
    });

    testWidgets('a_discard_during_a_save_leaves_the_file_to_the_save',
        (tester) async {
      final gate = Completer<void>();
      final repository = _GatedSoilRecordRepository(gate.future);
      final deleted = <String>[];
      // Routed, because the save it lets finish opens details.
      await tester.pumpWidget(buildRouted(
        pickFromCamera: () async => XFile(samplePath),
        locate: () async => null,
        classify: (_) async => null,
        repository: repository,
        deletePickedFile: (path) async => deleted.add(path),
      ));

      await tester.tap(find.text('open capture'));
      await tester.pumpAndSettle();
      await capture(tester);
      await tester.tap(find.text('Salvar registro'));
      await tester.pump();
      await tester.tap(find.text('Descartar'));
      await tester.pump();

      expect(repository.createCalls, hasLength(1));
      expect(deleted, isEmpty);

      gate.complete();
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 10));
      }

      expect(deleted, [samplePath]);
    });

    testWidgets('a_failed_deletion_does_not_fail_the_save', (tester) async {
      final repository = FakeSoilRecordRepository();
      await tester.pumpWidget(buildRouted(
        pickFromCamera: () async => XFile(samplePath),
        locate: () async => null,
        classify: (_) async => null,
        repository: repository,
        deletePickedFile: (path) async =>
            throw FileSystemException('denied', path),
      ));

      await openAndSave(tester);

      expect(repository.createCalls, hasLength(1));
      expect(find.text('Registro salvo com sucesso!'), findsOneWidget);
      expect(find.text('DETAILS_STUB 1'), findsOneWidget);
    });

    test('the_default_deleter_removes_the_file_and_ignores_an_absent_one',
        () async {
      final dir = Directory.systemTemp.createTempSync('picked_file');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File('${dir.path}/picked.jpg')..writeAsBytesSync([1, 2, 3]);

      await deletePickedFile(file.path);
      expect(file.existsSync(), isFalse);

      await expectLater(deletePickedFile(file.path), completes);
    });
  });

  // Leaving capture discards its photograph as "Descartar" does, once the
  // page has left, so the next capture starts without it (SPEC 0146).
  group('leaving capture', () {
    Future<void> openAndCapture(WidgetTester tester) async {
      await tester.tap(find.text('open capture'));
      await tester.pumpAndSettle();
      await capture(tester);
      expect(find.text('Salvar registro'), findsOneWidget);
    }

    testWidgets('leaving_capture_discards_its_photograph', (tester) async {
      final deleted = <String>[];
      await tester.pumpWidget(buildRouted(
        pickFromCamera: () async => XFile(samplePath),
        locate: () async => null,
        classify: (_) async => null,
        deletePickedFile: (path) async => deleted.add(path),
      ));
      await openAndCapture(tester);

      await tester.pageBack();
      await tester.pump();
      // The photograph leaves with the page instead of blanking under it.
      expect(find.text('Salvar registro'), findsOneWidget);
      expect(deleted, isEmpty);

      await tester.pumpAndSettle();
      expect(find.byType(CaptureScreen), findsNothing);
      expect(deleted, [samplePath]);

      await tester.tap(find.text('open capture'));
      await tester.pumpAndSettle();
      expect(find.text('Câmera'), findsOneWidget);
      expect(find.text('Salvar registro'), findsNothing);
    });

    testWidgets('leaving_during_a_save_leaves_the_file_to_the_save',
        (tester) async {
      final gate = Completer<void>();
      final repository = _GatedSoilRecordRepository(gate.future);
      final deleted = <String>[];
      await tester.pumpWidget(buildRouted(
        pickFromCamera: () async => XFile(samplePath),
        locate: () async => null,
        classify: (_) async => null,
        repository: repository,
        deletePickedFile: (path) async => deleted.add(path),
      ));
      await openAndCapture(tester);

      await tester.tap(find.text('Salvar registro'));
      await tester.pump();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(CaptureScreen), findsNothing);
      expect(deleted, isEmpty);

      gate.complete();
      await tester.pumpAndSettle();

      expect(repository.createCalls, hasLength(1));
      expect(deleted, [samplePath]);
    });

    testWidgets('a_saved_capture_starts_the_next_one_clean', (tester) async {
      await tester.pumpWidget(buildRouted(
        pickFromCamera: () async => XFile(samplePath),
        locate: () async => null,
        classify: (_) async =>
            const InferenceResult(textureClass: 'Media', confidenceScore: 0.7),
        repository: FakeSoilRecordRepository(),
      ));
      await openAndCapture(tester);
      await tester.tap(find.text('Salvar registro'));
      await tester.pumpAndSettle();
      expect(find.text('DETAILS_STUB 1'), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('open capture'));
      await tester.pumpAndSettle();

      expect(find.text('Câmera'), findsOneWidget);
      expect(find.text('Salvar registro'), findsNothing);
      final uiState =
          (tester.state(find.byType(CaptureScreen)) as dynamic).uiState
              as CaptureUiState;
      expect(uiState.classificationResult, isNull);
    });
  });

  // A photograph can be replaced without discarding it first, and nothing
  // changes until the camera returns a new one (SPEC 0147).
  group('retake', () {
    late String retakePath;

    setUpAll(() {
      final dir = Directory.systemTemp.createTempSync('capture_retake_test');
      final file = File('${dir.path}/retake.png');
      file.writeAsBytesSync(img.encodePng(img.Image(width: 8, height: 8)));
      retakePath = file.path;
    });

    VisioButton retakeButton(WidgetTester tester) => tester.widget<VisioButton>(
          find.byWidgetPredicate(
            (w) => w is VisioButton && w.label == 'Tirar outra foto',
          ),
        );

    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 10));
      }
    }

    // Location and classification resolve a few frames after the photograph.
    Future<void> captureFirst(WidgetTester tester) async {
      await capture(tester);
      await settle(tester);
    }

    Future<void> retake(WidgetTester tester) async {
      await tester.tap(find.text('Tirar outra foto'));
      await settle(tester);
      await settle(tester);
    }

    CaptureUiState uiState(WidgetTester tester) =>
        (tester.state(find.byType(CaptureScreen)) as dynamic).uiState
            as CaptureUiState;

    String? shownPath(WidgetTester tester) => tester
        .widget<CaptureImagePreview>(find.byType(CaptureImagePreview))
        .image
        ?.path;

    // Each reading names its turn, so a test can tell a kept location from a
    // new one. Typed as the resolver's nullable reading, so the screen's
    // null-returning timeout fallback type-checks.
    LocationResolver countedLocate(List<int> count) => () {
          count[0]++;
          return Future<LocationReading?>.value(
            (latitude: -23.5, longitude: -46.6, address: 'Ponto ${count[0]}'),
          );
        };

    testWidgets('retake_replaces_the_photograph', (tester) async {
      final repository = FakeSoilRecordRepository();
      final picks = [samplePath, retakePath];
      final classified = <String>[];
      final locations = [0];
      final deleted = <String>[];
      await tester.pumpWidget(buildScreen(
        pickFromCamera: () async => XFile(picks.removeAt(0)),
        locate: countedLocate(locations),
        classify: (path) async {
          classified.add(path);
          return InferenceResult(
            textureClass: path == samplePath ? 'Arenosa' : 'Argilosa',
            confidenceScore: 0.8,
          );
        },
        repository: repository,
        deletePickedFile: (path) async => deleted.add(path),
      ));

      await captureFirst(tester);
      expect(uiState(tester).classificationResult?.textureClass, 'Arenosa');
      expect(uiState(tester).address, 'Ponto 1');

      await retake(tester);

      expect(shownPath(tester), retakePath);
      expect(classified, [samplePath, retakePath]);
      expect(locations[0], 2);
      expect(uiState(tester).classificationResult?.textureClass, 'Argilosa');
      expect(uiState(tester).address, 'Ponto 2');
      expect(deleted, [samplePath]);
      expect(repository.createCalls, isEmpty);
    });

    testWidgets('cancelling_a_retake_keeps_the_photograph', (tester) async {
      final picks = <String?>[samplePath, null];
      final classified = <String>[];
      final locations = [0];
      final deleted = <String>[];
      await tester.pumpWidget(buildScreen(
        pickFromCamera: () async {
          final path = picks.removeAt(0);
          return path == null ? null : XFile(path);
        },
        locate: countedLocate(locations),
        classify: (path) async {
          classified.add(path);
          return const InferenceResult(
              textureClass: 'Arenosa', confidenceScore: 0.8);
        },
        deletePickedFile: (path) async => deleted.add(path),
      ));

      await captureFirst(tester);
      final generation = uiState(tester).generation;
      await retake(tester);

      expect(picks, isEmpty, reason: 'the camera opened for the retake');
      expect(shownPath(tester), samplePath);
      expect(classified, [samplePath]);
      expect(locations[0], 1);
      expect(uiState(tester).generation, generation);
      expect(uiState(tester).classificationResult?.textureClass, 'Arenosa');
      expect(uiState(tester).address, 'Ponto 1');
      expect(deleted, isEmpty);
      expect(find.text('Salvar registro'), findsOneWidget);
    });

    testWidgets('a_failed_retake_keeps_the_photograph', (tester) async {
      var picks = 0;
      final locations = [0];
      final deleted = <String>[];
      await tester.pumpWidget(buildScreen(
        pickFromCamera: () async {
          if (++picks == 1) return XFile(samplePath);
          throw PlatformException(code: 'camera_error');
        },
        locate: countedLocate(locations),
        classify: (_) async =>
            const InferenceResult(textureClass: 'Arenosa', confidenceScore: 0.8),
        deletePickedFile: (path) async => deleted.add(path),
      ));

      await captureFirst(tester);
      await retake(tester);

      expect(picks, 2);
      expect(find.text('Não foi possível abrir a câmera.'), findsOneWidget);
      expect(shownPath(tester), samplePath);
      expect(uiState(tester).classificationResult?.textureClass, 'Arenosa');
      expect(uiState(tester).address, 'Ponto 1');
      expect(locations[0], 1);
      expect(deleted, isEmpty);
    });

    // The denied view would hide the photograph, and back from it would
    // discard it, so a refusal while one is held is a SnackBar instead.
    for (final refusal in [
      AppPermissionStatus.denied,
      AppPermissionStatus.permanentlyDenied,
    ]) {
      testWidgets('a_refused_retake_keeps_the_photograph (${refusal.name})',
          (tester) async {
        var camera = AppPermissionStatus.granted;
        var picks = 0;
        final deleted = <String>[];
        await tester.pumpWidget(ProviderScope(
          overrides: [
            _guideAlreadySeen(),
            inferenceServiceProvider.overrideWithValue(_FakeInference(
              (_) async => const InferenceResult(
                  textureClass: 'Arenosa', confidenceScore: 0.8),
            )),
          ],
          child: MaterialApp(
            home: CaptureScreen(
              pickFromCamera: () async {
                picks++;
                return XFile(samplePath);
              },
              locate: () => Future<LocationReading?>.value(
                (latitude: -23.5, longitude: -46.6, address: 'Ponto 1'),
              ),
              checkCameraPermission: () async => camera,
              requestCameraPermission: () async => camera,
              deletePickedFile: (path) async => deleted.add(path),
            ),
          ),
        ));

        await captureFirst(tester);
        camera = refusal;
        await retake(tester);

        expect(picks, 1);
        expect(find.text('Sem acesso à câmera. A foto atual foi mantida.'),
            findsOneWidget);
        expect(find.text('Acesso à câmera necessário'), findsNothing);
        expect(find.text('Salvar registro'), findsOneWidget);
        expect(shownPath(tester), samplePath);
        expect(uiState(tester).classificationResult?.textureClass, 'Arenosa');
        expect(uiState(tester).address, 'Ponto 1');
        expect(deleted, isEmpty);

        // Without a photograph, a refusal still leads to the denied view.
        await tester.tap(find.text('Descartar'));
        await tester.pump();
        await captureFirst(tester);
        expect(find.text('Acesso à câmera necessário'), findsOneWidget);
      });
    }

    testWidgets('retake_waits_for_the_classification_and_the_save',
        (tester) async {
      final gates = [
        Completer<InferenceResult?>(),
        Completer<InferenceResult?>(),
      ];
      var calls = 0;
      final picks = [samplePath, retakePath];
      final saveGate = Completer<void>();
      await tester.pumpWidget(buildRouted(
        pickFromCamera: () async => XFile(picks.removeAt(0)),
        locate: () async => null,
        classify: (_) => gates[calls++].future,
        repository: _GatedSoilRecordRepository(saveGate.future),
      ));
      await tester.tap(find.text('open capture'));
      await tester.pumpAndSettle();
      await captureFirst(tester);

      expect(retakeButton(tester).onPressed, isNull,
          reason: 'disabled while the classification runs');
      gates[0].complete(null);
      await settle(tester);
      expect(retakeButton(tester).onPressed, isNotNull,
          reason: 'enabled after a classification that failed');

      await retake(tester);
      expect(calls, 2);
      expect(retakeButton(tester).onPressed, isNull);
      gates[1].complete(
          const InferenceResult(textureClass: 'Media', confidenceScore: 0.7));
      await settle(tester);
      expect(retakeButton(tester).onPressed, isNotNull,
          reason: 'enabled after a classification that succeeded');

      await tester.tap(find.text('Salvar registro'));
      await tester.pump();
      expect(retakeButton(tester).onPressed, isNull,
          reason: 'disabled while a save is in flight');

      saveGate.complete();
      await tester.pumpAndSettle();
      expect(find.text('DETAILS_STUB 1'), findsOneWidget);
    });

    // A save tapped before the camera covers the screen still owns the
    // previous file, as it does against "Descartar" (SPEC 0094).
    testWidgets('a_retake_during_a_save_leaves_the_file_to_the_save',
        (tester) async {
      final pickGate = Completer<XFile?>();
      var picks = 0;
      final saveGate = Completer<void>();
      final deleted = <String>[];
      await tester.pumpWidget(buildRouted(
        pickFromCamera: () =>
            ++picks == 1 ? Future.value(XFile(samplePath)) : pickGate.future,
        locate: () async => null,
        classify: (_) async => null,
        repository: _GatedSoilRecordRepository(saveGate.future),
        deletePickedFile: (path) async => deleted.add(path),
      ));
      await tester.tap(find.text('open capture'));
      await tester.pumpAndSettle();
      await captureFirst(tester);

      await tester.tap(find.text('Tirar outra foto'));
      await tester.tap(find.text('Salvar registro'));
      await settle(tester);
      pickGate.complete(XFile(retakePath));
      await settle(tester);
      expect(shownPath(tester), retakePath);
      expect(deleted, isEmpty);

      saveGate.complete();
      await tester.pumpAndSettle();
      expect(deleted, [samplePath]);
    });

    testWidgets('saving_after_a_retake_saves_the_new_photograph',
        (tester) async {
      final repository = FakeSoilRecordRepository();
      final picks = [samplePath, retakePath];
      await tester.pumpWidget(buildRouted(
        pickFromCamera: () async => XFile(picks.removeAt(0)),
        locate: () async => null,
        classify: (path) async => path == samplePath
            ? const InferenceResult(textureClass: 'Arenosa', confidenceScore: 0.6)
            : const InferenceResult(
                textureClass: 'Argilosa', confidenceScore: 0.9),
        repository: repository,
      ));
      await tester.tap(find.text('open capture'));
      await tester.pumpAndSettle();
      await captureFirst(tester);
      await retake(tester);
      expect(repository.createCalls, isEmpty);

      await tester.tap(find.text('Salvar registro'));
      await tester.pumpAndSettle();

      final saved = repository.createCalls.single;
      expect(saved.imagePath, retakePath);
      expect(saved.textureClass, 'Argilosa');
      expect(saved.confidenceScore, 0.9);
      expect(find.text('DETAILS_STUB 1'), findsOneWidget);
    });

    // The labelled and tap-target guidelines on the whole screen, with the
    // third button in the column.
    testWidgets('retake_is_labelled', (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(buildScreen(
        pickFromCamera: () async => XFile(samplePath),
        locate: () async => null,
        classify: (_) async =>
            const InferenceResult(textureClass: 'Media', confidenceScore: 0.7),
      ));
      await captureFirst(tester);
      await tester.pumpAndSettle();

      expect(
        tester.getSemantics(find.bySemanticsLabel('Tirar outra foto')),
        isSemantics(isButton: true, isEnabled: true, hasTapAction: true),
      );
      await expectMeetsGuidelines(tester);
      semantics.dispose();
    });
  });

  // A photograph recovered after Android killed the app arrives with the
  // screen, which treats it as a fresh capture without opening the camera
  // (SPEC 0096).
  testWidgets('a_capture_screen_opened_with_a_photograph_locates_and_classifies_it',
      (tester) async {
    var cameraOpened = false;
    final classified = <String>[];
    await tester.pumpWidget(buildScreen(
      pickFromCamera: () async {
        cameraOpened = true;
        return null;
      },
      // Typed as the seam's nullable future: the screen's location timeout
      // answers null, which a non-nullable future cannot hold.
      locate: () => Future<LocationReading?>.value(
          (latitude: -23.5, longitude: -46.6, address: 'São Paulo')),
      classify: (path) async {
        classified.add(path);
        return null;
      },
      initialImagePath: samplePath,
    ));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }

    expect(cameraOpened, isFalse);
    expect(find.text('Salvar registro'), findsOneWidget);
    expect(classified, [samplePath]);
    expect(find.text('São Paulo'), findsOneWidget);
  });

  // A failed classification says which cause it was (SPEC 0105).
  testWidgets('the_capture_screen_names_the_cause', (tester) async {
    await tester.pumpWidget(buildScreen(
      pickFromCamera: () async => XFile(samplePath),
      locate: () async => null,
      classify: (_) async => null,
      failureCause: ClassificationFailureCause.sheetCropped,
    ));

    await capture(tester);

    expect(find.text('Folha cortada no quadro · tire outra foto'),
        findsOneWidget);
  });

  // Before a photograph, and with a result, capture passes Flutter's four
  // accessibility guidelines (SPEC 0133).
  for (final (name, theme) in appThemes) {
    testWidgets('screens_meet_guidelines in the $name theme', (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(buildScreen(
        pickFromCamera: () async => XFile(samplePath),
        locate: () async => null,
        classify: (_) async =>
            const InferenceResult(textureClass: 'Media', confidenceScore: 0.7),
        theme: theme,
      ));
      await tester.pumpAndSettle();
      await expectMeetsGuidelines(tester);

      await capture(tester);
      await tester.pumpAndSettle();
      expect(find.text('Salvar registro'), findsOneWidget);
      await expectMeetsGuidelines(tester);
      semantics.dispose();
    });
  }

  // The guide comes before the first camera launch only, its back button
  // never opens the camera, and a flag that cannot be read or written never
  // keeps the camera closed (SPEC 0142).
  group('capture guide', () {
    Widget buildGuided(FakeCaptureGuideStore store, List<String> picks) {
      final router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (context, _) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => context.push('/capture'),
                  child: const Text('open capture'),
                ),
              ),
            ),
          ),
          GoRoute(
            path: '/capture',
            builder: (_, _) => CaptureScreen(
              pickFromCamera: () async {
                picks.add('camera');
                return XFile(samplePath);
              },
              locate: () async => null,
              checkCameraPermission: () async => AppPermissionStatus.granted,
              requestCameraPermission: () async => AppPermissionStatus.granted,
              deletePickedFile: _keepPickedFile,
            ),
          ),
          GoRoute(
            path: '/capture-guide',
            builder: (_, state) =>
                CaptureGuideScreen(beforeCamera: state.extra == true),
          ),
        ],
      );
      return ProviderScope(
        overrides: [
          captureGuideStoreProvider.overrideWithValue(store),
          inferenceServiceProvider.overrideWithValue(_FakeInference(
            (_) async =>
                const InferenceResult(textureClass: 'Media', confidenceScore: 0.7),
          )),
        ],
        child: MaterialApp.router(routerConfig: router),
      );
    }

    Future<void> openCapture(WidgetTester tester) async {
      await tester.tap(find.text('open capture'));
      await tester.pumpAndSettle();
    }

    testWidgets('guide_shown_before_first_camera', (tester) async {
      final store = FakeCaptureGuideStore();
      final picks = <String>[];
      await tester.pumpWidget(buildGuided(store, picks));
      await openCapture(tester);

      await tester.tap(find.text('Câmera'));
      await tester.pumpAndSettle();
      expect(find.byType(CaptureGuideScreen), findsOneWidget);
      expect(picks, isEmpty);

      await tester.tap(find.text('Abrir câmera'));
      await tester.pumpAndSettle();
      expect(find.byType(CaptureGuideScreen), findsNothing);
      expect(picks, ['camera']);
      expect(find.text('Salvar registro'), findsOneWidget);

      // The second capture goes straight to the camera.
      await tester.tap(find.text('Descartar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Câmera'));
      await tester.pumpAndSettle();
      expect(find.byType(CaptureGuideScreen), findsNothing);
      expect(picks, ['camera', 'camera']);
    });

    testWidgets('back_does_not_open_camera', (tester) async {
      final store = FakeCaptureGuideStore();
      final picks = <String>[];
      await tester.pumpWidget(buildGuided(store, picks));
      await openCapture(tester);

      await tester.tap(find.text('Câmera'));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(find.byType(CaptureGuideScreen), findsNothing);
      expect(find.text('Câmera'), findsOneWidget);
      expect(picks, isEmpty);
      expect(store.seen, isFalse);

      // Backing out leaves the guide unseen, so the next tap shows it again.
      await tester.tap(find.text('Câmera'));
      await tester.pumpAndSettle();
      expect(find.byType(CaptureGuideScreen), findsOneWidget);
    });

    testWidgets('an_unreadable_flag_does_not_block_the_camera',
        (tester) async {
      final picks = <String>[];
      await tester.pumpWidget(buildGuided(
        FakeCaptureGuideStore(readError: Exception('prefs unavailable')),
        picks,
      ));
      await openCapture(tester);

      await tester.tap(find.text('Câmera'));
      await tester.pumpAndSettle();

      expect(find.byType(CaptureGuideScreen), findsNothing);
      expect(picks, ['camera']);
    });

    testWidgets('an_unwritable_flag_does_not_block_the_camera',
        (tester) async {
      final picks = <String>[];
      await tester.pumpWidget(buildGuided(
        FakeCaptureGuideStore(writeError: Exception('disk full')),
        picks,
      ));
      await openCapture(tester);

      await tester.tap(find.text('Câmera'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Abrir câmera'));
      await tester.pumpAndSettle();

      expect(picks, ['camera']);
      expect(find.text('Salvar registro'), findsOneWidget);
    });

    testWidgets('guide_reachable_on_demand from capture', (tester) async {
      final store = FakeCaptureGuideStore();
      final picks = <String>[];
      await tester.pumpWidget(buildGuided(store, picks));
      await openCapture(tester);

      await tester.tap(find.byTooltip('Como capturar'));
      await tester.pumpAndSettle();
      expect(find.byType(CaptureGuideScreen), findsOneWidget);
      expect(find.text('Abrir câmera'), findsNothing);

      await tester.tap(find.text('Entendi'));
      await tester.pumpAndSettle();
      expect(find.byType(CaptureGuideScreen), findsNothing);
      expect(find.text('Câmera'), findsOneWidget);
      expect(picks, isEmpty);
      expect(store.markCalls, 1);

      // Read on demand counts as seen: the first capture opens the camera.
      await tester.tap(find.text('Câmera'));
      await tester.pumpAndSettle();
      expect(picks, ['camera']);
    });
  });
}
