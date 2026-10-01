// Capture asks for what it needs, when it needs it (SPEC 0099): the camera
// when "Câmera" is tapped, then location once the photograph arrives. A
// denied location still saves the record. These pin what the splash no longer
// does in its place.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:visiosoil_app/core/constants/app_strings.dart';
import 'package:visiosoil_app/core/features/capture/capture_screen.dart';
import 'package:visiosoil_app/core/services/classification_report.dart';
import 'package:visiosoil_app/core/services/inference_service.dart';
import 'package:visiosoil_app/core/services/permission_service.dart';
import 'package:visiosoil_app/providers/inference_provider.dart';
import 'package:visiosoil_app/providers/soil_record_repository_provider.dart';

import '../../support/fake_soil_record_repository.dart';

class _FailingInference extends InferenceService {
  @override
  Future<ClassificationReport> classify(
    String imagePath, {
    Duration? timeout,
    InferenceIsolateEntry? entryPoint,
  }) async =>
      const ClassificationReport.failed(ClassificationFailureCause.timeout);
}

void main() {
  late String samplePath;

  setUp(() {
    final dir = Directory.systemTemp.createTempSync('capture_permissions');
    final file = File('${dir.path}/sample.png')
      ..writeAsBytesSync(img.encodePng(img.Image(width: 8, height: 8)));
    samplePath = file.path;
  });

  Widget routed({
    required CameraPermissionProbe checkCamera,
    required CameraPermissionProbe requestCamera,
    required LocationResolver locate,
    FakeSoilRecordRepository? repository,
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
            pickFromCamera: () async => XFile(samplePath),
            locate: locate,
            checkCameraPermission: checkCamera,
            requestCameraPermission: requestCamera,
          ),
        ),
      ],
    );
    return ProviderScope(
      overrides: [
        inferenceServiceProvider.overrideWithValue(_FailingInference()),
        if (repository != null)
          soilRecordRepositoryProvider.overrideWithValue(repository),
      ],
      child: MaterialApp.router(routerConfig: router),
    );
  }

  Future<void> openAndCapture(WidgetTester tester) async {
    await tester.tap(find.text('open capture'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Câmera'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
  }

  testWidgets('first_capture_requests_the_camera_then_location_once_each',
      (tester) async {
    final asked = <String>[];
    await tester.pumpWidget(routed(
      checkCamera: () async => AppPermissionStatus.denied,
      requestCamera: () async {
        asked.add('camera');
        return AppPermissionStatus.granted;
      },
      locate: () {
        asked.add('location');
        return Future<LocationReading?>.value(null);
      },
    ));

    await openAndCapture(tester);

    expect(asked, ['camera', 'location']);
  });

  testWidgets('a_capture_without_location_still_saves_the_record',
      (tester) async {
    final repository = FakeSoilRecordRepository();
    await tester.pumpWidget(routed(
      checkCamera: () async => AppPermissionStatus.granted,
      requestCamera: () async => AppPermissionStatus.granted,
      // What `LocationService` amounts to when location is denied.
      locate: () => Future<LocationReading?>.error('denied'),
      repository: repository,
    ));

    await openAndCapture(tester);
    await tester.tap(find.text('Salvar registro'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    await tester.pumpAndSettle();

    final saved = repository.createCalls.single;
    expect(saved.latitude, isNull);
    expect(saved.longitude, isNull);
    expect(saved.address, AppStrings.addressUnavailable);
    expect(find.text('open capture'), findsOneWidget);
  });
}
