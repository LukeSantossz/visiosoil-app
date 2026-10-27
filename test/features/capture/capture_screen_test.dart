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
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:visiosoil_app/core/constants/app_strings.dart';
import 'package:visiosoil_app/core/features/capture/capture_guide_screen.dart';
import 'package:visiosoil_app/core/features/capture/capture_screen.dart';
import 'package:visiosoil_app/core/features/details/widgets/result_lattice.dart';
import 'package:visiosoil_app/core/features/capture/capture_ui_state.dart';
import 'package:visiosoil_app/core/features/capture/guided_camera/capture_camera.dart';
import 'package:visiosoil_app/core/routes/app_router.dart';
import 'package:visiosoil_app/core/features/details/details_screen.dart';
import 'package:visiosoil_app/core/services/classification_report.dart';
import 'package:visiosoil_app/core/services/gallery_saver.dart';
import 'package:visiosoil_app/core/services/inference_service.dart';
import 'package:visiosoil_app/core/services/permission_service.dart';
import 'package:visiosoil_app/core/theme/app_motion.dart';
import 'package:visiosoil_app/core/theme/app_palette.dart';
import 'package:visiosoil_app/models/class_score.dart';
import 'package:visiosoil_app/models/soil_record.dart';
import 'package:visiosoil_app/providers/capture_guide_store_provider.dart';
import 'package:visiosoil_app/providers/capture_preferences_provider.dart';
import 'package:visiosoil_app/providers/image_provider.dart';
import 'package:visiosoil_app/providers/inference_provider.dart';
import 'package:visiosoil_app/providers/soil_record_repository_provider.dart';

import '../../support/fake_capture_guide_store.dart';
import '../../support/fake_soil_record_repository.dart';
import '../../support/guided_camera_harness.dart';
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

/// Holds every `create` until [gate] completes, so a test can act while a
/// save is in flight.
class _GatedSoilRecordRepository extends FakeSoilRecordRepository {
  _GatedSoilRecordRepository(this.gate);

  Future<void> gate;

  @override
  Future<SoilRecord> create(SoilRecord record) async {
    await gate;
    return super.create(record);
  }
}

/// Records each photograph handed to the gallery, or refuses them all.
class _RecordingGallerySaver implements GallerySaver {
  _RecordingGallerySaver({this.fails = false});

  final bool fails;
  final saved = <String>[];

  @override
  Future<void> save(String imagePath) async {
    if (fails) throw StateError('refused');
    saved.add(imagePath);
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

// Details as capture hands over to it (SPEC 0219): the record's id, and what
// the repository holds for it, so a test reads what capture wrote.
GoRoute _detailsStub() => GoRoute(
      path: '/details',
      builder: (_, state) {
        final extra = state.extra;
        final id = extra is CapturedRecord ? extra.id : extra as int;
        return Scaffold(
          appBar: AppBar(),
          body: Consumer(
            builder: (context, ref, _) {
              final record = ref.watch(soilRecordByIdProvider(id)).value;
              return Column(
                children: [
                  Text('DETAILS_STUB $id'),
                  Text('CLASS ${record?.textureClass}'),
                  Text('CAUSE ${record?.classificationFailure?.name}'),
                  Text('ADDRESS ${record?.address}'),
                ],
              );
            },
          ),
        );
      },
    );

void main() {
  late String samplePath;

  // Existing flow tests exercise business transitions without decorative time.
  setUp(() => AppMotion.reduceMotion = true);
  tearDown(() => AppMotion.reduceMotion = false);

  setUpAll(() {
    final dir = Directory.systemTemp.createTempSync('capture_screen_test');
    final file = File('${dir.path}/sample.png');
    file.writeAsBytesSync(img.encodePng(img.Image(width: 8, height: 8)));
    samplePath = file.path;
  });

  // Capture inside a GoRouter, since a saved capture replaces itself with
  // details (SPEC 0132, SPEC 0219). It opens on capture; [buildRouted] opens
  // on a launcher underneath it, for the tests that go back.
  Widget buildScreen({
    CameraImagePicker? pickFromCamera,
    GuidedCameraOpener? openGuidedCamera,
    CameraImagePicker? pickFromSystemCamera,
    required LocationResolver locate,
    required Future<InferenceResult?> Function(String) classify,
    FakeSoilRecordRepository? repository,
    PickedFileDeleter deletePickedFile = _keepPickedFile,
    String? initialImagePath,
    ClassificationFailureCause failureCause = ClassificationFailureCause.timeout,
    _FakeInference? inference,
    ThemeData? theme,
    CameraPermissionProbe? checkCameraPermission,
    CameraPermissionProbe? requestCameraPermission,
    List<Override> overrides = const [],
    String initialLocation = '/capture',
  }) {
    final router = GoRouter(
      initialLocation: initialLocation,
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
            openGuidedCamera: openGuidedCamera,
            pickFromSystemCamera: pickFromSystemCamera,
            locate: locate,
            checkCameraPermission: checkCameraPermission ??
                () async => AppPermissionStatus.granted,
            requestCameraPermission: requestCameraPermission ??
                () async => AppPermissionStatus.granted,
            deletePickedFile: deletePickedFile,
            initialImagePath: initialImagePath,
          ),
        ),
        _detailsStub(),
      ],
    );
    return ProviderScope(
      overrides: [
        _guideAlreadySeen(),
        inferenceServiceProvider.overrideWithValue(
            inference ?? _FakeInference(classify, cause: failureCause)),
        soilRecordRepositoryProvider
            .overrideWithValue(repository ?? FakeSoilRecordRepository()),
        ...overrides,
      ],
      child: MaterialApp.router(theme: theme, routerConfig: router),
    );
  }

  Widget buildRouted({
    required CameraImagePicker pickFromCamera,
    required LocationResolver locate,
    required Future<InferenceResult?> Function(String) classify,
    FakeSoilRecordRepository? repository,
    PickedFileDeleter deletePickedFile = _keepPickedFile,
    ClassificationFailureCause failureCause = ClassificationFailureCause.timeout,
    List<Override> overrides = const [],
  }) =>
      buildScreen(
        pickFromCamera: pickFromCamera,
        locate: locate,
        classify: classify,
        repository: repository,
        deletePickedFile: deletePickedFile,
        failureCause: failureCause,
        overrides: overrides,
        initialLocation: '/',
      );

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
  }

  // Flushes the permission -> pick -> setImage -> create -> start-futures
  // async chain.
  Future<void> capture(WidgetTester tester) async {
    await tester.tap(find.text('Câmera'));
    await settle(tester);
  }

  // Lets the classification be written and details replace capture.
  Future<void> handOver(WidgetTester tester) async {
    await settle(tester);
    await tester.pumpAndSettle();
  }

  Future<void> openCapture(WidgetTester tester) async {
    await tester.tap(find.text('open capture'));
    await tester.pumpAndSettle();
  }

  // The photograph capture holds, read from the provider because the
  // processing view shows none of it.
  String? shownPath(WidgetTester tester) => ProviderScope.containerOf(
        tester.element(find.byType(CaptureScreen)),
      ).read(imageProvider).file?.path;

  // The acceptance criteria of SPEC 0219: the record is created when the
  // photograph arrives, and what arrives later is written into it.
  group('save on arrival', () {
    testWidgets('capture_saves_when_the_photograph_arrives', (tester) async {
      final repository = FakeSoilRecordRepository();
      final gate = Completer<InferenceResult?>();
      await tester.pumpWidget(buildScreen(
        pickFromCamera: () async => XFile(samplePath),
        locate: () async => null,
        classify: (_) => gate.future,
        repository: repository,
      ));

      await capture(tester);

      expect(repository.createCalls, hasLength(1));
      final created = repository.stored[1]!;
      expect(created.imagePath, samplePath);
      expect(created.textureClass, isNull);
      expect(created.classificationFailure, isNull);
      expect(created.address, AppStrings.addressUnavailable);
      expect(repository.updateClassificationCalls, isEmpty);
      expect(find.byType(CaptureScreen), findsOneWidget);

      gate.complete(null);
      await handOver(tester);
    });

    testWidgets('capture_writes_the_classification_and_opens_details',
        (tester) async {
      final repository = FakeSoilRecordRepository();
      await tester.pumpWidget(buildScreen(
        pickFromCamera: () async => XFile(samplePath),
        locate: () async => null,
        classify: (_) async =>
            const InferenceResult(textureClass: 'Argilosa', confidenceScore: 0.82),
        repository: repository,
      ));

      await capture(tester);
      await handOver(tester);

      expect(repository.createCalls, hasLength(1));
      expect(repository.updateClassificationCalls, [1]);
      final written = repository.stored[1]!;
      expect(written.textureClass, 'Argilosa');
      expect(written.confidenceScore, 0.82);
      expect(written.classificationFailure, isNull);
      expect(find.byType(CaptureScreen), findsNothing);
      expect(find.text('DETAILS_STUB 1'), findsOneWidget);
      expect(find.text('CLASS Argilosa'), findsOneWidget);
      expect(find.text(AppStrings.resultSavedSnackbar), findsOneWidget);
    });

    testWidgets('capture_writes_a_failed_classification', (tester) async {
      final repository = FakeSoilRecordRepository();
      await tester.pumpWidget(buildScreen(
        pickFromCamera: () async => XFile(samplePath),
        locate: () async => null,
        classify: (_) async => null,
        failureCause: ClassificationFailureCause.sheetNotFound,
        repository: repository,
      ));

      await capture(tester);
      await handOver(tester);

      expect(repository.updateClassificationCalls, [1]);
      final written = repository.stored[1]!;
      expect(written.textureClass, isNull);
      expect(written.classificationFailure,
          ClassificationFailureCause.sheetNotFound);
      expect(find.text('DETAILS_STUB 1'), findsOneWidget);
      expect(find.text('CAUSE sheetNotFound'), findsOneWidget);
    });

    testWidgets('failed_result_write_offers_a_retry', (tester) async {
      final repository = FakeSoilRecordRepository()
        ..throwOnUpdateClassification = true;
      await tester.pumpWidget(buildScreen(
        pickFromCamera: () async => XFile(samplePath),
        locate: () async => null,
        classify: (_) async =>
            const InferenceResult(textureClass: 'Argilosa', confidenceScore: 0.82),
        repository: repository,
      ));

      await capture(tester);
      await handOver(tester);

      // Nothing claims the result was saved, and capture stays.
      expect(find.text('Não foi possível salvar o resultado'), findsOneWidget);
      expect(find.text(AppStrings.resultSavedSnackbar), findsNothing);
      expect(find.text('DETAILS_STUB 1'), findsNothing);
      expect(repository.stored[1]!.textureClass, isNull);

      repository.throwOnUpdateClassification = false;
      await tester.tap(find.text('Tentar de novo'));
      await handOver(tester);

      expect(repository.updateClassificationCalls, [1, 1]);
      expect(repository.stored[1]!.textureClass, 'Argilosa');
      expect(find.text('DETAILS_STUB 1'), findsOneWidget);
      expect(find.text('CLASS Argilosa'), findsOneWidget);
      expect(find.text(AppStrings.resultSavedSnackbar), findsOneWidget);
    });

    testWidgets('declined_result_write_opens_the_record', (tester) async {
      final repository = FakeSoilRecordRepository()
        ..throwOnUpdateClassification = true;
      await tester.pumpWidget(buildScreen(
        pickFromCamera: () async => XFile(samplePath),
        locate: () async => null,
        classify: (_) async =>
            const InferenceResult(textureClass: 'Argilosa', confidenceScore: 0.82),
        repository: repository,
      ));

      await capture(tester);
      await handOver(tester);
      await tester.tap(find.text('Continuar sem resultado'));
      await handOver(tester);

      // The record keeps the photograph, without the result.
      expect(repository.updateClassificationCalls, [1]);
      expect(repository.stored[1]!.textureClass, isNull);
      expect(find.text('DETAILS_STUB 1'), findsOneWidget);
      expect(find.text('CLASS null'), findsOneWidget);
    });

    testWidgets('leaving_while_classifying_keeps_the_record', (tester) async {
      final repository = FakeSoilRecordRepository();
      final gate = Completer<InferenceResult?>();
      await tester.pumpWidget(buildRouted(
        pickFromCamera: () async => XFile(samplePath),
        locate: () async => null,
        classify: (_) => gate.future,
        repository: repository,
      ));
      await openCapture(tester);
      await capture(tester);

      await tester.tap(find.byTooltip('Voltar'));
      await tester.pumpAndSettle();
      expect(find.byType(CaptureScreen), findsNothing);
      expect(find.text('open capture'), findsOneWidget);

      gate.complete(
        const InferenceResult(textureClass: 'Argilosa', confidenceScore: 0.8),
      );
      await handOver(tester);

      expect(repository.stored.keys, [1]);
      expect(repository.deleteByIdCalls, isEmpty);
      expect(repository.updateClassificationCalls, [1]);
      expect(repository.stored[1]!.textureClass, 'Argilosa');
      // Nobody is left to open details for.
      expect(find.textContaining('DETAILS_STUB'), findsNothing);
      expect(find.text('open capture'), findsOneWidget);
    });

    testWidgets('capture_writes_the_location', (tester) async {
      final repository = FakeSoilRecordRepository();
      final locateGate = Completer<LocationReading?>();
      await tester.pumpWidget(buildScreen(
        pickFromCamera: () async => XFile(samplePath),
        locate: () => locateGate.future,
        classify: (_) async =>
            const InferenceResult(textureClass: 'Media', confidenceScore: 0.7),
        repository: repository,
      ));

      await capture(tester);
      await handOver(tester);
      // Details does not wait for the fix.
      expect(find.text('DETAILS_STUB 1'), findsOneWidget);
      expect(find.text('ADDRESS ${AppStrings.addressUnavailable}'),
          findsOneWidget);
      expect(repository.updateLocationCalls, isEmpty);

      locateGate.complete(
        (latitude: -23.5, longitude: -46.6, accuracy: 6.0, address: 'São Paulo'),
      );
      await handOver(tester);

      expect(repository.updateLocationCalls, [1]);
      final written = repository.stored[1]!;
      expect(written.latitude, -23.5);
      expect(written.longitude, -46.6);
      expect(written.horizontalAccuracy, 6.0);
      expect(written.address, 'São Paulo');
      expect(written.textureClass, 'Media');
      // Details re-reads the record once the location is written.
      expect(find.text('ADDRESS São Paulo'), findsOneWidget);
    });

    testWidgets('failed_create_keeps_the_photograph', (tester) async {
      final repository = FakeSoilRecordRepository()..throwOnCreate = true;
      final classified = <String>[];
      await tester.pumpWidget(buildScreen(
        pickFromCamera: () async => XFile(samplePath),
        locate: () async => null,
        classify: (path) async {
          classified.add(path);
          return null;
        },
        repository: repository,
      ));

      await capture(tester);

      expect(
        find.text('Não foi possível salvar o registro. Tente novamente.'),
        findsOneWidget,
      );
      expect(find.text('Salvar registro'), findsOneWidget);
      expect(shownPath(tester), samplePath);
      expect(classified, isEmpty, reason: 'nothing to write a result into');

      repository.throwOnCreate = false;
      await tester.tap(find.text('Salvar registro'));
      await handOver(tester);

      expect(repository.createCalls, hasLength(2));
      expect(repository.stored[2]!.imagePath, samplePath);
      expect(classified, [samplePath]);
      expect(find.text('DETAILS_STUB 2'), findsOneWidget);
    });
  });

  testWidgets('a_result_settles_before_details_opens', (tester) async {
    AppMotion.reduceMotion = false;
    final repository = FakeSoilRecordRepository();
    final pending = Completer<InferenceResult?>();
    await tester.pumpWidget(buildScreen(
      pickFromCamera: () async => XFile(samplePath),
      locate: () async => null,
      classify: (_) => pending.future,
      repository: repository,
    ));
    await capture(tester);
    expect(find.text('Resultado'), findsOneWidget);
    expect(find.text(AppStrings.processingTitle), findsOneWidget);
    pending.complete(const InferenceResult(textureClass: 'Argilosa', confidenceScore: .9));
    await tester.pump();
    await tester.pump();
    // Written before the triangle settles, so leaving now would lose nothing.
    expect(repository.updateClassificationCalls, [1]);
    await tester.pump(const Duration(milliseconds: 1800));
    expect(find.textContaining('DETAILS_STUB'), findsNothing);
    expect(find.byType(CaptureScreen), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 650));
    await settle(tester);
    // The triangle holds the class for AppMotion.slow before details opens.
    await tester.pump(AppMotion.slow);
    await settle(tester);
    expect(find.text('DETAILS_STUB 1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a camera picker failure shows a snackbar and keeps the screen',
      (tester) async {
    final repository = FakeSoilRecordRepository();
    await tester.pumpWidget(buildScreen(
      pickFromCamera: () async => throw PlatformException(code: 'camera_error'),
      locate: () async => null,
      classify: (_) async => null,
      repository: repository,
    ));

    await capture(tester);

    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.text('Câmera'), findsOneWidget);
    expect(repository.createCalls, isEmpty);
  });

  testWidgets('the screen applies no classification deadline of its own',
      (tester) async {
    final repository = FakeSoilRecordRepository();
    final pending = Completer<InferenceResult?>();
    await tester.pumpWidget(buildScreen(
      pickFromCamera: () async => XFile(samplePath),
      locate: () async => null,
      classify: (_) => pending.future,
      repository: repository,
    ));

    await capture(tester);

    // Well past the 20s deadline the screen used to impose. The single deadline
    // now lives in InferenceService, which is the only layer holding the isolate
    // handle and so the only one that can stop the work rather than abandon it.
    await tester.pump(const Duration(seconds: 25));
    expect(find.byType(CaptureScreen), findsOneWidget,
        reason: 'the screen must wait for the service instead of timing out');
    expect(repository.updateClassificationCalls, isEmpty);

    // The service resolving to null — its own timeout, or a failed run — is
    // what writes the failure and opens details.
    pending.complete(null);
    await handOver(tester);

    expect(repository.updateClassificationCalls, [1]);
    expect(find.text('DETAILS_STUB 1'), findsOneWidget);
  });

  // The chip names the step the isolate reports, not a timer (SPEC 0116).
  group('classification phases', () {
    // PNG 13 draws the result's lattice behind the bar while it classifies
    // (SPEC 0211).
    testWidgets('processing_draws_the_result_lattice', (tester) async {
      final gate = Completer<InferenceResult?>();
      await tester.pumpWidget(buildScreen(
        pickFromCamera: () async => XFile(samplePath),
        locate: () async => null,
        classify: (_) => gate.future,
      ));

      await capture(tester);
      expect(find.byType(ResultLattice), findsOneWidget);

      gate.complete(null);
      await handOver(tester);
    });

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
      expect(_phase('Classificando...'), findsOneWidget);

      // Each phase crossfades into the next over AppMotion.base (SPEC 0134).
      inference.phaseCallbacks.single!(ClassificationPhase.findingSheet);
      await settle(tester);
      await tester.pump(AppMotion.base);
      expect(_phase('Procurando a folha A4...'), findsOneWidget);
      expect(_phase('Classificando...'), findsNothing);

      inference.phaseCallbacks.single!(ClassificationPhase.describingTexture);
      await settle(tester);
      await tester.pump(AppMotion.base);
      expect(_phase('Descrevendo a textura...'), findsOneWidget);
      expect(_phase('Procurando a folha A4...'), findsNothing);

      gate.complete(null);
      await handOver(tester);
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
        find.byWidgetPredicate(
          (widget) =>
              widget is Semantics &&
              widget.properties.liveRegion == true &&
              widget.properties.label == 'Calculando a classe...',
        ),
        findsOneWidget,
      );

      gate.complete(null);
      await handOver(tester);
    });
  });

  // Details replaces capture, given the id `create` returned (SPEC 0132). The
  // fake numbers records from 1.
  testWidgets('save_opens_details', (tester) async {
    final repository = FakeSoilRecordRepository();
    await tester.pumpWidget(buildRouted(
      pickFromCamera: () async => XFile(samplePath),
      locate: () async => null,
      classify: (_) async => null,
      repository: repository,
    ));

    await openCapture(tester);
    await capture(tester);
    await handOver(tester);

    expect(repository.createCalls.length, 1);
    expect(find.text(AppStrings.resultSavedSnackbar), findsOneWidget);
    expect(find.text('DETAILS_STUB 1'), findsOneWidget);
    expect(find.byType(CaptureScreen), findsNothing);

    // Capture was replaced, not covered: back returns to what opened it.
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('open capture'), findsOneWidget);
    expect(find.byType(CaptureScreen), findsNothing);
  });

  // Configurações' capture switches (SPEC 0208).
  group('capture settings', () {
    Future<void> captureAndSave(WidgetTester tester) async {
      await openCapture(tester);
      await capture(tester);
      await handOver(tester);
    }

    testWidgets('location_off_skips_the_fix', (tester) async {
      final repository = FakeSoilRecordRepository();
      var locateCalls = 0;
      await tester.pumpWidget(buildRouted(
        pickFromCamera: () async => XFile(samplePath),
        locate: () async {
          locateCalls++;
          return (
            latitude: -22.9,
            longitude: -47.06,
            accuracy: 5.0,
            address: 'X',
          );
        },
        classify: (_) async => null,
        repository: repository,
        overrides: [initialRecordLocationProvider.overrideWithValue(false)],
      ));

      await captureAndSave(tester);

      expect(locateCalls, 0);
      expect(repository.updateLocationCalls, isEmpty);
      expect(repository.stored[1]!.latitude, isNull);
      expect(repository.stored[1]!.longitude, isNull);
    });

    testWidgets('gallery_on_copies_the_stored_photo', (tester) async {
      final gallery = _RecordingGallerySaver();
      await tester.pumpWidget(buildRouted(
        pickFromCamera: () async => XFile(samplePath),
        locate: () async => null,
        classify: (_) async => null,
        repository: _StoringRepository(),
        overrides: [
          initialSaveToGalleryProvider.overrideWithValue(true),
          gallerySaverProvider.overrideWithValue(gallery),
        ],
      ));

      await captureAndSave(tester);

      // The stored copy, not the picker's file (review of #438).
      expect(gallery.saved, [_StoringRepository.storedPath]);
    });

    testWidgets('gallery_off_copies_nothing', (tester) async {
      final gallery = _RecordingGallerySaver();
      await tester.pumpWidget(buildRouted(
        pickFromCamera: () async => XFile(samplePath),
        locate: () async => null,
        classify: (_) async => null,
        overrides: [gallerySaverProvider.overrideWithValue(gallery)],
      ));

      await captureAndSave(tester);

      expect(gallery.saved, isEmpty);
    });

    testWidgets('gallery_failure_keeps_the_record', (tester) async {
      final repository = FakeSoilRecordRepository();
      await tester.pumpWidget(buildRouted(
        pickFromCamera: () async => XFile(samplePath),
        locate: () async => null,
        classify: (_) async => null,
        repository: repository,
        overrides: [
          initialSaveToGalleryProvider.overrideWithValue(true),
          gallerySaverProvider.overrideWithValue(
            _RecordingGallerySaver(fails: true),
          ),
        ],
      ));

      await captureAndSave(tester);

      expect(repository.createCalls, hasLength(1));
      expect(repository.updateClassificationCalls, [1]);
      expect(find.text('DETAILS_STUB 1'), findsOneWidget);
      // The refusal arrives first; the saved notice queues behind it.
      expect(
        find.text('Não foi possível salvar a foto na galeria.'),
        findsOneWidget,
      );
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(find.text(AppStrings.resultSavedSnackbar), findsOneWidget);
    });
  });

  // The photograph's return makes one light haptic, and a result arriving one
  // by its confidence (SPEC 0126, redesign v11 §3.14).
  group('haptics', () {
    int count(List<String> haptics, String type) =>
        haptics.where((h) => h == 'HapticFeedbackType.$type').length;

    testWidgets('the_photograph_confirms', (tester) async {
      final haptics = recordHaptics(tester);
      final gate = Completer<InferenceResult?>();
      await tester.pumpWidget(buildScreen(
        pickFromCamera: () async => XFile(samplePath),
        locate: () async => null,
        classify: (_) => gate.future,
      ));

      await capture(tester);
      expect(count(haptics, 'lightImpact'), 1);

      gate.complete(null);
      await handOver(tester);
      // The automatic save makes none of its own.
      expect(count(haptics, 'lightImpact'), 1);
      expect(count(haptics, 'mediumImpact'), 0);
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
      await handOver(tester);

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
      await handOver(tester);

      expect(count(haptics, 'mediumImpact'), 0);
    });

    // The shutter and the triangle's settle each play a light impact first,
    // so the entry is counted rather than read off the end.
    for (final (score, medium, light) in [
      (0.82, 1, 2),
      (0.60, 1, 2),
      (0.40, 0, 3),
    ]) {
      testWidgets('entry_haptic_follows_the_level at $score', (tester) async {
        final haptics = recordHaptics(tester);
        await tester.pumpWidget(buildScreen(
          pickFromCamera: () async => XFile(samplePath),
          locate: () async => null,
          classify: (_) async =>
              InferenceResult(textureClass: 'Argilosa', confidenceScore: score),
        ));
        await capture(tester);
        await handOver(tester);

        expect(count(haptics, 'mediumImpact'), medium);
        expect(count(haptics, 'lightImpact'), light);
      });
    }
  });

  // PNG 33 leads the saved snackbar with a light green check (SPEC 0218).
  testWidgets('saved_snackbar_leads_with_a_check', (tester) async {
    await tester.pumpWidget(buildScreen(
      pickFromCamera: () async => XFile(samplePath),
      locate: () async => null,
      classify: (_) async =>
          const InferenceResult(textureClass: 'Argilosa', confidenceScore: 0.82),
    ));
    await capture(tester);
    await handOver(tester);

    final check = find.descendant(
      of: find.byType(SnackBar),
      matching: find.byIcon(LucideIcons.check),
    );
    expect(check, findsOneWidget);
    final icon = tester.widget<Icon>(check);
    expect(icon.size, 20);
    expect(icon.color, AppPalette.light.inversePrimary);
    expect(
      tester.getTopLeft(find.text(AppStrings.resultSavedSnackbar)).dx -
          tester.getTopRight(check).dx,
      12,
    );
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
    await tester.pumpWidget(buildScreen(
      pickFromCamera: () async => XFile(samplePath),
      locate: () async => null,
      classify: (_) async => result,
      repository: repository,
    ));

    await capture(tester);
    await handOver(tester);

    final saved = repository.stored[1]!;
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

  // SPEC 0173: a record whose classification failed keeps the cause its chip
  // named, and one that was classified keeps none.
  for (final failed in [true, false]) {
    testWidgets(
        failed
            ? 'a_failed_capture_keeps_its_cause'
            : 'a_classified_capture_keeps_no_cause', (tester) async {
      final repository = FakeSoilRecordRepository();
      await tester.pumpWidget(buildScreen(
        pickFromCamera: () async => XFile(samplePath),
        locate: () async => null,
        classify: (_) async => failed
            ? null
            : const InferenceResult(
                textureClass: 'Argilosa', confidenceScore: 0.9),
        repository: repository,
        failureCause: ClassificationFailureCause.photographTooCoarse,
      ));

      await capture(tester);
      await handOver(tester);

      expect(
        repository.stored[1]!.classificationFailure,
        failed ? ClassificationFailureCause.photographTooCoarse : null,
      );
    });
  }

  // SPEC 0148: the reading's horizontal accuracy reaches the record, and a
  // reading without one saves none.
  for (final accuracy in [4.2, null]) {
    testWidgets('saving_a_located_capture_persists_the_accuracy ($accuracy)',
        (tester) async {
      final repository = FakeSoilRecordRepository();
      await tester.pumpWidget(buildScreen(
        pickFromCamera: () async => XFile(samplePath),
        locate: () => Future<LocationReading?>.value((
          latitude: -23.5,
          longitude: -46.6,
          accuracy: accuracy,
          address: 'São Paulo',
        )),
        classify: (_) async => null,
        repository: repository,
      ));

      await capture(tester);
      await handOver(tester);

      expect(repository.updateLocationCalls, [1]);
      final saved = repository.stored[1]!;
      expect(saved.latitude, -23.5);
      expect(saved.horizontalAccuracy, accuracy);
    });
  }

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

    // pickFromCamera and pickFromSystemCamera are left as the real defaults on
    // purpose, so the capture drives ImagePicker().pickImage down to the
    // intercepted channel. The guided camera is unavailable, so the system
    // camera's own default runs (SPEC 0165).
    await tester.pumpWidget(buildScreen(
      openGuidedCamera: (_) async => const GuidedCaptureResult.unavailable(),
      locate: () async => null,
      classify: (_) async => null,
    ));

    await capture(tester);
    await handOver(tester);

    expect(requestedFullMetadata, isFalse);
  });

  testWidgets('a denied camera permission shows the permission-denied view',
      (tester) async {
    await tester.pumpWidget(buildScreen(
      pickFromCamera: () async => null,
      locate: () async => null,
      classify: (_) async => null,
      checkCameraPermission: () async => AppPermissionStatus.denied,
      requestCameraPermission: () async => AppPermissionStatus.denied,
    ));

    await capture(tester);

    expect(find.text('Acesso à câmera necessário'), findsOneWidget);
    expect(find.text('Câmera'), findsNothing);
  });

  // The picker's file carries the original EXIF, GPS included; the record
  // points at the durable copy, so the screen deletes the picker's file once
  // it is no longer needed (SPEC 0094).
  group('picked file', () {
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

      await openCapture(tester);
      await capture(tester);
      await handOver(tester);

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

      expect(repository.createCalls, hasLength(1));
      expect(deleted, isEmpty);
    });

    // After a failed save, "Descartar" deletes the picker's file (SPEC 0147).
    testWidgets('a_discarded_capture_deletes_the_picker_file', (tester) async {
      final deleted = <String>[];
      await tester.pumpWidget(buildScreen(
        pickFromCamera: () async => XFile(samplePath),
        locate: () async => null,
        classify: (_) async => null,
        repository: FakeSoilRecordRepository()..throwOnCreate = true,
        deletePickedFile: (path) async => deleted.add(path),
      ));

      await capture(tester);
      await tester.tap(find.text('Descartar'));
      await tester.pump();

      expect(deleted, [samplePath]);
      expect(find.text('Câmera'), findsOneWidget);
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

      await openCapture(tester);
      await capture(tester);
      await handOver(tester);

      expect(repository.createCalls, hasLength(1));
      expect(find.text(AppStrings.resultSavedSnackbar), findsOneWidget);
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

  // Leaving capture discards a photograph that could not be saved, as
  // "Descartar" does, once the page has left, so the next capture starts
  // without it (SPEC 0146).
  group('leaving capture', () {
    testWidgets('leaving_capture_discards_its_photograph', (tester) async {
      final deleted = <String>[];
      await tester.pumpWidget(buildRouted(
        pickFromCamera: () async => XFile(samplePath),
        locate: () async => null,
        classify: (_) async => null,
        repository: FakeSoilRecordRepository()..throwOnCreate = true,
        deletePickedFile: (path) async => deleted.add(path),
      ));
      await openCapture(tester);
      await capture(tester);
      expect(find.text('Salvar registro'), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pump();
      // The photograph leaves with the page instead of blanking under it.
      expect(find.text('Salvar registro'), findsOneWidget);
      expect(deleted, isEmpty);

      await tester.pumpAndSettle();
      expect(find.byType(CaptureScreen), findsNothing);
      expect(deleted, [samplePath]);

      await openCapture(tester);
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
        classify: (_) async =>
            const InferenceResult(textureClass: 'Media', confidenceScore: 0.7),
        repository: repository,
        deletePickedFile: (path) async => deleted.add(path),
      ));
      await openCapture(tester);
      await capture(tester);

      await tester.tap(find.byTooltip('Voltar'));
      await tester.pumpAndSettle();
      expect(find.byType(CaptureScreen), findsNothing);
      expect(deleted, isEmpty);

      gate.complete();
      await handOver(tester);

      expect(repository.createCalls, hasLength(1));
      expect(repository.stored[1]!.textureClass, 'Media');
      expect(deleted, [samplePath]);
    });

    testWidgets('a_saved_capture_starts_the_next_one_clean', (tester) async {
      await tester.pumpWidget(buildRouted(
        pickFromCamera: () async => XFile(samplePath),
        locate: () async => null,
        classify: (_) async =>
            const InferenceResult(textureClass: 'Media', confidenceScore: 0.7),
      ));
      await openCapture(tester);
      await capture(tester);
      await handOver(tester);
      expect(find.text('DETAILS_STUB 1'), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();
      await openCapture(tester);

      expect(find.text('Câmera'), findsOneWidget);
      expect(find.text('Salvar registro'), findsNothing);
      final uiState =
          (tester.state(find.byType(CaptureScreen)) as dynamic).uiState
              as CaptureUiState;
      expect(uiState.classificationResult, isNull);
    });
  });

  // A photograph whose save failed can be replaced without discarding it
  // first, and nothing changes until the camera returns a new one
  // (SPEC 0147).
  group('retake', () {
    late String retakePath;

    setUpAll(() {
      final dir = Directory.systemTemp.createTempSync('capture_retake_test');
      final file = File('${dir.path}/retake.png');
      file.writeAsBytesSync(img.encodePng(img.Image(width: 8, height: 8)));
      retakePath = file.path;
    });

    Future<void> retake(WidgetTester tester) async {
      // The failed save's notice would queue the retake's own behind it.
      ScaffoldMessenger.of(tester.element(find.byType(CaptureScreen)))
          .removeCurrentSnackBar();
      await tester.tap(find.text('Tirar outra foto'));
      await settle(tester);
      await settle(tester);
    }

    testWidgets('retake_replaces_the_photograph', (tester) async {
      final repository = FakeSoilRecordRepository()..throwOnCreate = true;
      final picks = [samplePath, retakePath];
      final classified = <String>[];
      final deleted = <String>[];
      await tester.pumpWidget(buildScreen(
        pickFromCamera: () async => XFile(picks.removeAt(0)),
        locate: () async => null,
        classify: (path) async {
          classified.add(path);
          return const InferenceResult(
            textureClass: 'Argilosa',
            confidenceScore: 0.8,
          );
        },
        repository: repository,
        deletePickedFile: (path) async => deleted.add(path),
      ));

      await capture(tester);
      expect(shownPath(tester), samplePath);

      repository.throwOnCreate = false;
      await retake(tester);
      await handOver(tester);

      expect(repository.createCalls.map((r) => r.imagePath),
          [samplePath, retakePath]);
      expect(repository.stored.keys, [2]);
      expect(repository.stored[2]!.textureClass, 'Argilosa');
      expect(classified, [retakePath]);
      expect(deleted, unorderedEquals([samplePath, retakePath]));
      expect(find.text('DETAILS_STUB 2'), findsOneWidget);
    });

    testWidgets('cancelling_a_retake_keeps_the_photograph', (tester) async {
      final repository = FakeSoilRecordRepository()..throwOnCreate = true;
      final picks = <String?>[samplePath, null];
      final deleted = <String>[];
      await tester.pumpWidget(buildScreen(
        pickFromCamera: () async {
          final path = picks.removeAt(0);
          return path == null ? null : XFile(path);
        },
        locate: () async => null,
        classify: (_) async => null,
        repository: repository,
        deletePickedFile: (path) async => deleted.add(path),
      ));

      await capture(tester);
      await retake(tester);

      expect(picks, isEmpty, reason: 'the camera opened for the retake');
      expect(shownPath(tester), samplePath);
      expect(repository.createCalls, hasLength(1));
      expect(deleted, isEmpty);
      expect(find.text('Salvar registro'), findsOneWidget);
    });

    testWidgets('a_failed_retake_keeps_the_photograph', (tester) async {
      var picks = 0;
      final deleted = <String>[];
      await tester.pumpWidget(buildScreen(
        pickFromCamera: () async {
          if (++picks == 1) return XFile(samplePath);
          throw PlatformException(code: 'camera_error');
        },
        locate: () async => null,
        classify: (_) async => null,
        repository: FakeSoilRecordRepository()..throwOnCreate = true,
        deletePickedFile: (path) async => deleted.add(path),
      ));

      await capture(tester);
      await retake(tester);

      expect(picks, 2);
      expect(find.text('Não foi possível abrir a câmera.'), findsOneWidget);
      expect(shownPath(tester), samplePath);
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
        await tester.pumpWidget(buildScreen(
          pickFromCamera: () async {
            picks++;
            return XFile(samplePath);
          },
          locate: () async => null,
          classify: (_) async => null,
          repository: FakeSoilRecordRepository()..throwOnCreate = true,
          checkCameraPermission: () async => camera,
          requestCameraPermission: () async => camera,
          deletePickedFile: (path) async => deleted.add(path),
        ));

        await capture(tester);
        camera = refusal;
        await retake(tester);

        expect(picks, 1);
        expect(find.text('Sem acesso à câmera. A foto atual foi mantida.'),
            findsOneWidget);
        expect(find.text('Acesso à câmera necessário'), findsNothing);
        expect(find.text('Salvar registro'), findsOneWidget);
        expect(shownPath(tester), samplePath);
        expect(deleted, isEmpty);
      });
    }

    // A save and a retake never run together: whichever is tapped first runs,
    // and the other does nothing (SPEC 0147).
    testWidgets('a_save_waits_for_an_open_retake', (tester) async {
      final repository = FakeSoilRecordRepository()..throwOnCreate = true;
      final pickGate = Completer<XFile?>();
      var picks = 0;
      final deleted = <String>[];
      await tester.pumpWidget(buildScreen(
        pickFromCamera: () =>
            ++picks == 1 ? Future.value(XFile(samplePath)) : pickGate.future,
        locate: () async => null,
        classify: (_) async => null,
        repository: repository,
        deletePickedFile: (path) async => deleted.add(path),
      ));
      await capture(tester);
      repository.throwOnCreate = false;

      await tester.tap(find.text('Tirar outra foto'));
      await tester.tap(find.text('Salvar registro'));
      await settle(tester);
      expect(repository.createCalls, hasLength(1),
          reason: 'no save while the camera is open for a retake');

      pickGate.complete(XFile(retakePath));
      await handOver(tester);
      expect(repository.createCalls, hasLength(2));
      expect(repository.createCalls.last.imagePath, retakePath);
      expect(deleted, unorderedEquals([samplePath, retakePath]));
    });

    testWidgets('a_retake_waits_for_a_save', (tester) async {
      var picks = 0;
      final saveGate = Completer<void>();
      final repository = _GatedSoilRecordRepository(Future.value())
        ..throwOnCreate = true;
      final deleted = <String>[];
      await tester.pumpWidget(buildScreen(
        pickFromCamera: () async {
          picks++;
          return XFile(picks == 1 ? samplePath : retakePath);
        },
        locate: () async => null,
        classify: (_) async => null,
        repository: repository,
        deletePickedFile: (path) async => deleted.add(path),
      ));
      await capture(tester);
      repository
        ..throwOnCreate = false
        ..gate = saveGate.future;

      await tester.tap(find.text('Salvar registro'));
      await tester.tap(find.text('Tirar outra foto'));
      await settle(tester);
      expect(picks, 1, reason: 'no camera while a save is in flight');

      saveGate.complete();
      await handOver(tester);
      expect(picks, 1);
      expect(deleted, [samplePath]);
      expect(find.text('DETAILS_STUB 2'), findsOneWidget);
    });

    // The labelled and tap-target guidelines on the whole screen, with the
    // third button in the column.
    testWidgets('retake_is_labelled', (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(buildScreen(
        pickFromCamera: () async => XFile(samplePath),
        locate: () async => null,
        classify: (_) async => null,
        repository: FakeSoilRecordRepository()..throwOnCreate = true,
      ));
      await capture(tester);
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
  // screen, which saves it as a fresh capture without opening the camera
  // (SPEC 0096, SPEC 0219).
  testWidgets('a_capture_screen_opened_with_a_photograph_saves_and_classifies_it',
      (tester) async {
    final repository = FakeSoilRecordRepository();
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
          (latitude: -23.5, longitude: -46.6,
              accuracy: null, address: 'São Paulo')),
      classify: (path) async {
        classified.add(path);
        return const InferenceResult(textureClass: 'Media', confidenceScore: 0.7);
      },
      repository: repository,
      initialImagePath: samplePath,
    ));
    await handOver(tester);

    expect(cameraOpened, isFalse);
    expect(repository.createCalls.single.imagePath, samplePath);
    expect(classified, [samplePath]);
    expect(repository.stored[1]!.textureClass, 'Media');
    expect(repository.stored[1]!.address, 'São Paulo');
    expect(find.text('DETAILS_STUB 1'), findsOneWidget);
  });

  // Before a photograph, and with one whose save failed, capture passes
  // Flutter's four accessibility guidelines (SPEC 0133).
  for (final (name, theme) in appThemes) {
    testWidgets('screens_meet_guidelines in the $name theme', (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(buildScreen(
        pickFromCamera: () async => XFile(samplePath),
        locate: () async => null,
        classify: (_) async => null,
        repository: FakeSoilRecordRepository()..throwOnCreate = true,
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
          _detailsStub(),
        ],
      );
      return ProviderScope(
        overrides: [
          captureGuideStoreProvider.overrideWithValue(store),
          inferenceServiceProvider.overrideWithValue(_FakeInference(
            (_) async =>
                const InferenceResult(textureClass: 'Media', confidenceScore: 0.7),
          )),
          soilRecordRepositoryProvider
              .overrideWithValue(FakeSoilRecordRepository()),
        ],
        child: MaterialApp.router(routerConfig: router),
      );
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
      await handOver(tester);
      expect(find.byType(CaptureGuideScreen), findsNothing);
      expect(picks, ['camera']);
      expect(find.text('DETAILS_STUB 1'), findsOneWidget);

      // The second capture goes straight to the camera.
      await tester.pageBack();
      await tester.pumpAndSettle();
      // The saved notice would cover the capture button.
      ScaffoldMessenger.of(tester.element(find.text('open capture')))
          .removeCurrentSnackBar();
      await tester.pumpAndSettle();
      await openCapture(tester);
      await tester.tap(find.text('Câmera'));
      await handOver(tester);
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
      await handOver(tester);

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
      await handOver(tester);

      expect(picks, ['camera']);
      expect(find.text('DETAILS_STUB 1'), findsOneWidget);
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
      await handOver(tester);
      expect(picks, ['camera']);
    });
  });

  // The default picker composes the guided camera and the system camera it
  // falls back to (SPEC 0165).
  group('guided camera composition', () {
    testWidgets('no_camera_falls_back_to_the_system_camera', (tester) async {
      final repository = FakeSoilRecordRepository();
      var systemCalls = 0;
      await tester.pumpWidget(buildScreen(
        openGuidedCamera: (_) async => const GuidedCaptureResult.unavailable(),
        pickFromSystemCamera: () async {
          systemCalls++;
          return XFile(samplePath);
        },
        locate: () async => null,
        classify: (_) async => null,
        repository: repository,
      ));

      await capture(tester);
      await handOver(tester);

      expect(systemCalls, 1);
      expect(repository.createCalls.single.imagePath, samplePath);
    });

    testWidgets('a_guided_photograph_skips_the_system_camera', (tester) async {
      final repository = FakeSoilRecordRepository();
      var systemCalls = 0;
      await tester.pumpWidget(buildScreen(
        openGuidedCamera: (_) async =>
            GuidedCaptureResult.captured(XFile(samplePath)),
        pickFromSystemCamera: () async {
          systemCalls++;
          return null;
        },
        locate: () async => null,
        classify: (_) async => null,
        repository: repository,
      ));

      await capture(tester);
      await handOver(tester);

      expect(systemCalls, 0);
      expect(repository.createCalls.single.imagePath, samplePath);
    });

    for (final (name, result) in <(String, GuidedCaptureResult?)>[
      ('cancelled', const GuidedCaptureResult.cancelled()),
      ('back', null),
    ]) {
      testWidgets('close_returns_nothing_$name', (tester) async {
        final repository = FakeSoilRecordRepository();
        var systemCalls = 0;
        await tester.pumpWidget(buildScreen(
          openGuidedCamera: (_) async => result,
          pickFromSystemCamera: () async {
            systemCalls++;
            return XFile(samplePath);
          },
          locate: () async => null,
          classify: (_) async => null,
          repository: repository,
        ));

        await capture(tester);

        expect(systemCalls, 0);
        expect(shownPath(tester), isNull);
        expect(repository.createCalls, isEmpty);
        expect(find.text('Câmera'), findsOneWidget);
      });
    }
  });

  // The guided camera reached the way the app reaches it: a GoRouter push of
  // /camera, popped by the screen itself (SPEC 0165; R2 review).
  group('guided camera through the router', () {
    final productionCameraRoute = appRouter.configuration.routes
        .whereType<GoRoute>()
        .singleWhere((route) => route.path == '/camera');

    Future<(GuidedCameraHarness, List<String>)> pumpRouted(
      WidgetTester tester,
      FakeSoilRecordRepository repository,
    ) async {
      final h = GuidedCameraHarness();
      final deleted = <String>[];
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
          SystemChannels.platform, (call) async => null);
      addTearDown(() =>
          messenger.setMockMethodCallHandler(SystemChannels.platform, null));
      final router = GoRouter(
        initialLocation: '/capture',
        routes: [
          GoRoute(
            path: '/capture',
            builder: (_, _) => CaptureScreen(
              locate: () async => null,
              checkCameraPermission: () async => AppPermissionStatus.granted,
              requestCameraPermission: () async => AppPermissionStatus.granted,
              deletePickedFile: (path) async => deleted.add(path),
            ),
          ),
          // The production route's own builder, so a broken /camera fails here.
          GoRoute(path: '/camera', builder: productionCameraRoute.builder),
          _detailsStub(),
        ],
      );
      await tester.pumpWidget(ProviderScope(
        overrides: [
          _guideAlreadySeen(),
          inferenceServiceProvider
              .overrideWithValue(_FakeInference((_) async => null)),
          soilRecordRepositoryProvider.overrideWithValue(repository),
          ...guidedCameraOverrides(h),
        ],
        child: MaterialApp.router(routerConfig: router),
      ));
      await tester.pumpAndSettle();
      return (h, deleted);
    }

    testWidgets('a_guided_photograph_returns_through_the_router',
        (tester) async {
      final repository = FakeSoilRecordRepository();
      final (h, deleted) = await pumpRouted(tester, repository);
      h.cameras.picturePath = samplePath;
      await tester.tap(find.text('Câmera'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('guided-camera-shutter')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('guided-camera-shutter')));
      await settleIo(tester);
      await tester.pumpAndSettle();
      expect(repository.createCalls.single.imagePath, samplePath);
      expect(deleted, [samplePath]);
      expect(find.text('DETAILS_STUB 1'), findsOneWidget);
      // The guided camera reads the shot to learn the still size (SPEC 0166);
      // let that read finish before the test ends.
      await settleIo(tester);
    });

    testWidgets('back_from_the_router_returns_nothing', (tester) async {
      final repository = FakeSoilRecordRepository();
      await pumpRouted(tester, repository);
      await tester.tap(find.text('Câmera'));
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('guided-camera-shutter')), findsNothing);
      expect(shownPath(tester), isNull);
      expect(repository.createCalls, isEmpty);
    });

    testWidgets('a_retake_through_the_router_deletes_the_previous_file',
        (tester) async {
      final dir = Directory.systemTemp.createTempSync('guided_retake');
      addTearDown(() => dir.deleteSync(recursive: true));
      final second = File('${dir.path}/second.png')
        ..writeAsBytesSync(File(samplePath).readAsBytesSync());
      // Unsaved, so the photograph stays for a retake (SPEC 0219).
      final (h, deleted) = await pumpRouted(
          tester, FakeSoilRecordRepository()..throwOnCreate = true);

      h.cameras.picturePath = samplePath;
      await tester.tap(find.text('Câmera'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('guided-camera-shutter')));
      await settleIo(tester);
      await tester.pumpAndSettle();

      h.cameras.picturePath = second.path;
      await tester.tap(find.text('Tirar outra foto'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('guided-camera-shutter')));
      await settleIo(tester);
      await tester.pumpAndSettle();

      expect(shownPath(tester), second.path);
      expect(deleted, [samplePath]);
      // The guided camera reads the shot to learn the still size (SPEC 0166);
      // let that read finish before the file is deleted.
      await settleIo(tester);
    });
  });
}

/// The processing screen's phase, read aloud and not drawn (SPEC 0211).
Finder _phase(String label) => find.byWidgetPredicate(
  (widget) => widget is Semantics && widget.properties.label == label,
);

/// Saves each record under another path, as the image store does, so a test
/// can tell the stored photograph from the picker's file.
class _StoringRepository extends FakeSoilRecordRepository {
  static const storedPath = '/stored/sample.jpg';

  @override
  Future<SoilRecord> create(SoilRecord record) =>
      super.create(record.copyWith(imagePath: storedPath));
}
