import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:visiosoil_app/core/data/repositories/soil_record_repository.dart';
import 'package:visiosoil_app/core/features/capture/capture_screen.dart';
import 'package:visiosoil_app/core/features/capture/capture_ui_state.dart';
import 'package:visiosoil_app/core/services/classification_report.dart';
import 'package:visiosoil_app/core/services/inference_service.dart';
import 'package:visiosoil_app/core/services/permission_service.dart';
import 'package:visiosoil_app/models/class_score.dart';
import 'package:visiosoil_app/models/soil_record.dart';
import 'package:visiosoil_app/providers/inference_provider.dart';
import 'package:visiosoil_app/providers/soil_record_repository_provider.dart';

import '../../support/fake_soil_record_repository.dart';

/// Answers with a report built from the handler's result: a result is `ok`,
/// and `null` stands for a run that failed. The cause is fixed because none of
/// these tests is about which one it was; the one that is sets its own.
class _FakeInference extends InferenceService {
  _FakeInference(this._handler, {this.cause = ClassificationFailureCause.timeout});

  final Future<InferenceResult?> Function(String imagePath) _handler;
  final ClassificationFailureCause cause;

  @override
  Future<ClassificationReport> classify(
    String imagePath, {
    Duration? timeout,
    InferenceIsolateEntry? entryPoint,
  }) async {
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
  }) {
    return ProviderScope(
      overrides: [
        inferenceServiceProvider.overrideWithValue(_FakeInference(classify)),
        if (repository != null)
          soilRecordRepositoryProvider.overrideWithValue(repository),
      ],
      child: MaterialApp(
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

  // Same as buildScreen but inside a GoRouter, so context.pop() on a successful
  // save has a route to pop back to.
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
      ],
    );
    return ProviderScope(
      overrides: [
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

    // The failed state the screen renders today, and no result.
    expect(find.byKey(const Key('retryClassification')), findsOneWidget);
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

    // Settle the retry as another failure, which brings the chip back.
    gate.complete(null);
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
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

  testWidgets('a successful save creates the record, shows success, and pops',
      (tester) async {
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
    expect(find.text('open capture'), findsOneWidget); // popped back to '/'
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

    expect(find.text('São Paulo'), findsOneWidget);
    expect(find.text('Localizando...'), findsNothing);
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
      // Routed, because the save it lets finish pops the screen.
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
      expect(find.text('open capture'), findsOneWidget); // popped back to '/'
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
}
