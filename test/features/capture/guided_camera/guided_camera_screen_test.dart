import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visiosoil_app/core/features/capture/guided_camera/capture_camera.dart';
import 'package:visiosoil_app/core/features/capture/guided_camera/live_reading.dart';
import 'package:visiosoil_app/core/theme/app_haptics.dart';
import 'package:visiosoil_app/core/theme/app_palette.dart';

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

  // The shutter works when there's no live reading (can't determine readiness).
  // But when we HAVE a live reading showing not-ready, it's blocked (redesign v11 §7).
  testWidgets('the_shutter_works_without_live_reading', (tester) async {
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

  // Final review fixes (R2, Codex Luna).
  testWidgets('a_late_failure_after_close_is_recorded', (tester) async {
    final h = await openGuidedCamera(tester);
    final gate = Completer<void>();
    h.cameras.cameras.single.pictureGate = gate;
    await tester.tap(shutter);
    await tester.pump();
    await backOut(tester);

    h.cameras.takePictureError = CameraException('captureFailed', 'late');
    gate.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(h.errors.sources, ['guided_camera']);
  });

  testWidgets('a_late_photograph_after_close_is_deleted', (tester) async {
    final dir = Directory.systemTemp.createTempSync('guided_late');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/late.jpg')..writeAsBytesSync([1, 2, 3]);
    final h = await openGuidedCamera(tester);
    h.cameras.picturePath = file.path;
    final gate = Completer<void>();
    h.cameras.cameras.single.pictureGate = gate;
    await tester.tap(shutter);
    await tester.pump();
    await backOut(tester);

    gate.complete();
    await settleIo(tester);
    await tester.pumpAndSettle();
    expect(file.existsSync(), isFalse);
    expect(h.popped, [isNull]);
  });

  testWidgets('the_banner_uses_each_roles_container', (tester) async {
    final h = await openGuidedCamera(tester);
    final palette = AppPalette.light;
    Color background() => tester
        .widget<Container>(find.byKey(const ValueKey('guided-camera-banner')))
        .color!;
    Color ink() => tester
        .widget<Text>(find.descendant(
          of: find.byKey(const ValueKey('guided-camera-banner')),
          matching: find.byType(Text),
        ))
        .style!
        .color!;

    expect((background(), ink()),
        (palette.surfaceVariant, palette.onSurfaceVariant));
    for (final (degrees, container, onContainer) in [
      (0.0, palette.primaryContainer, palette.onPrimaryContainer),
      (8.0, palette.warningContainer, palette.onWarningContainer),
      (20.0, palette.errorContainer, palette.onErrorContainer),
    ]) {
      await tiltTo(tester, h, degrees);
      expect((background(), ink()), (container, onContainer), reason: '$degrees');
    }
  });

  // Blocked haptic fires when shutter is tapped but we have a live reading
  // showing not-ready conditions (redesign v11 §7, bad-photo path).
  testWidgets('shutter_when_live_reading_not_ready_fires_blocked_haptic',
      (tester) async {
    AppHaptics.enabled = true;
    final h = await openGuidedCamera(tester);
    await tiltTo(tester, h, 0); // Level, but live reading will show not ready

    // Two readings needed to pass debouncer; "sheet not found" means not ready
    await emitFrame(tester, h);
    await replyWith(tester, h, const LiveSheetNotFound());
    await emitFrame(tester, h);
    await replyWith(tester, h, const LiveSheetNotFound());
    expect(bannerText(tester), contains('Enquadre a folha'));
    h.cameras.log.clear();

    // runAsync to handle blocked()'s 60ms timer
    await tester.runAsync(() async {
      await tester.tap(shutter);
      await Future.delayed(const Duration(milliseconds: 80));
    });
    await tester.pump();

    expect(h.cameras.log, contains('haptic:HapticFeedbackType.heavyImpact'));
    expect(h.cameras.cameras.single.takePictureCalls, 0,
        reason: 'should not take photo when live reading shows not ready');
  });

  testWidgets('shutter_when_live_reading_ready_does_not_fire_blocked',
      (tester) async {
    AppHaptics.enabled = true;
    final h = await openGuidedCamera(tester);
    await tiltTo(tester, h, 0); // Level

    // Two readings needed; "sheet found with good disc" means ready
    const goodReading = LiveSheetFound(
      sheetLongSidePx: 1000,
      discDiameterMm: 90, // Good size (8-10 cm)
      holdsMinPatches: true,
    );
    await emitFrame(tester, h);
    await replyWith(tester, h, goodReading);
    await emitFrame(tester, h);
    await replyWith(tester, h, goodReading);
    // With a ready reading, the auto-capture window opens (SPEC 0167)
    expect(bannerText(tester), contains('Segure firme'));
    h.cameras.log.clear();

    await tester.tap(shutter);
    await tester.pumpAndSettle();

    expect(h.cameras.log, isNot(contains('haptic:HapticFeedbackType.heavyImpact')));
    expect(h.cameras.cameras.single.takePictureCalls, 1);
  });
}
