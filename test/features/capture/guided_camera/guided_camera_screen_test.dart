import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visiosoil_app/core/features/capture/guided_camera/capture_camera.dart';

import '../../../support/guided_camera_harness.dart';

void main() {
  testWidgets('the_guide_is_drawn', (tester) async {
    final h = await openGuidedCamera(tester);
    expect(fakePreview, findsOneWidget);
    expect(find.text('8–10 cm de solo'), findsOneWidget);
    expect(closeButton, findsOneWidget);
    expect(shutter, findsOneWidget);
    expect(levelIndicator, findsNothing, reason: 'no tilt yet');

    await tiltTo(tester, h, 0);
    expect(levelIndicator, findsOneWidget);
  });

  testWidgets('the_banner_follows_the_tilt', (tester) async {
    final h = await openGuidedCamera(tester);
    expect(bannerText(tester), 'Encaixe a folha no contorno.');
    await tiltTo(tester, h, 0);
    expect(bannerText(tester), 'Nivelado. Encaixe a folha no contorno.');
    await tiltTo(tester, h, 8);
    expect(bannerText(tester), 'Quase. Deixe o celular paralelo ao chão.');
    await tiltTo(tester, h, 20);
    expect(bannerText(tester), 'Segure o celular paralelo ao chão, de cima.');
  });

  testWidgets('the_shutter_returns_the_photograph', (tester) async {
    final h = await openGuidedCamera(tester);
    await tester.tap(shutter);
    await tester.pumpAndSettle();
    expect(h.cameras.cameras.single.takePictureCalls, 1);
    final result = h.popped.single;
    expect(result, isA<GuidedCaptureCaptured>());
    expect((result! as GuidedCaptureCaptured).file.path, '/tmp/guided_0.jpg');
  });

  testWidgets('a_double_tap_takes_one_photograph', (tester) async {
    final h = await openGuidedCamera(tester);
    final gate = Completer<void>();
    h.cameras.cameras.single.pictureGate = gate;
    await tester.tap(shutter);
    await tester.tap(shutter);
    gate.complete();
    await tester.pumpAndSettle();
    expect(h.cameras.cameras.single.takePictureCalls, 1);
    expect(h.popped, hasLength(1));
  });

  testWidgets('the_shutter_is_never_disabled', (tester) async {
    final h = await openGuidedCamera(tester);
    await tiltTo(tester, h, 20);
    await tester.tap(shutter);
    await tester.pumpAndSettle();
    expect(h.popped.single, isA<GuidedCaptureCaptured>());
  });

  testWidgets('a_tap_before_ready_does_nothing', (tester) async {
    final h = GuidedCameraHarness()..cameras.initializeGate = Completer<void>();
    await openGuidedCamera(tester, harness: h);
    await tester.tap(shutter);
    await tester.pump();
    expect(h.cameras.cameras.single.takePictureCalls, 0);
    expect(tester.takeException(), isNull);

    h.cameras.initializeGate!.complete();
    await tester.pumpAndSettle();
    expect(fakePreview, findsOneWidget);
  });

  testWidgets('close_returns_nothing', (tester) async {
    final h = await openGuidedCamera(tester);
    await tester.tap(closeButton);
    await tester.pumpAndSettle();
    expect(h.popped.single, isA<GuidedCaptureCancelled>());

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await backOut(tester);
    expect(h.popped, hasLength(2));
    expect(h.popped.last, isNull, reason: 'back pops null, read as cancelled');
  });

  testWidgets('no_camera_pops_unavailable', (tester) async {
    final h = GuidedCameraHarness()
      ..cameras.initializeError = const CameraUnavailableException('none');
    await openGuidedCamera(tester, harness: h);
    expect(h.popped.single, isA<GuidedCaptureUnavailable>());
    expect(h.cameras.cameras.single.disposed, isTrue);
  });

  testWidgets('a_revoked_permission_on_first_open_is_unavailable',
      (tester) async {
    final h = GuidedCameraHarness()
      ..cameras.initializeError =
          const CameraPermissionRevokedException('CameraAccessDenied');
    await openGuidedCamera(tester, harness: h);
    expect(h.popped.single, isA<GuidedCaptureUnavailable>());
  });

  testWidgets('a_failed_shot_keeps_the_screen', (tester) async {
    final h = await openGuidedCamera(tester);
    h.cameras.takePictureError = CameraException('captureFailed', 'boom');
    await tester.tap(shutter);
    await tester.pump();
    await tester.pump();
    expect(
      find.text('Não foi possível tirar a foto. Tente de novo.'),
      findsOneWidget,
    );
    expect(h.popped, isEmpty);
    expect(h.errors.sources, ['guided_camera']);

    h.cameras.takePictureError = null;
    await tester.tap(shutter);
    await tester.pumpAndSettle();
    expect(h.popped.single, isA<GuidedCaptureCaptured>());
  });

  testWidgets('no_sensor_blocks_nothing', (tester) async {
    final h = await openGuidedCamera(tester);
    await tiltTo(tester, h, 20);
    h.tilt.controller.addError(StateError('no accelerometer'));
    await tester.pumpAndSettle();
    expect(levelIndicator, findsNothing);
    expect(bannerText(tester), 'Encaixe a folha no contorno.');

    await tester.tap(shutter);
    await tester.pumpAndSettle();
    expect(h.popped.single, isA<GuidedCaptureCaptured>());
  });

  testWidgets('a_shot_finishing_after_close_does_not_pop', (tester) async {
    final h = await openGuidedCamera(tester);
    final gate = Completer<void>();
    h.cameras.cameras.single.pictureGate = gate;
    await tester.tap(shutter);
    await tester.pump();
    await backOut(tester);
    gate.complete();
    await tester.pumpAndSettle();
    expect(h.popped, [isNull]);
    expect(tester.takeException(), isNull);
  });
}
