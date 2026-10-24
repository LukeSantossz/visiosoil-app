import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visiosoil_app/core/features/capture/guided_camera/capture_alert.dart';
import 'package:visiosoil_app/core/features/capture/guided_camera/live_reading.dart';
import 'package:visiosoil_app/core/features/capture/guided_camera/quality_chip.dart';
import 'package:visiosoil_app/core/theme/app_motion.dart';
import 'package:visiosoil_app/core/features/capture/widgets/camera_permission_denied_view.dart';
import 'package:visiosoil_app/core/services/permission_service.dart';
import 'package:visiosoil_app/core/theme/app_theme.dart';
import '../../../support/guided_camera_harness.dart';

Future<void> readQuality(
  WidgetTester tester,
  GuidedCameraHarness h, {
  required bool good,
  bool cropped = false,
}) async {
  for (var i = 0; i < 2; i++) {
    h.cameras.cameras.single.emitFrame((
      format: tinyFrame.format,
      width: 32,
      height: 32,
      bytes: Uint8List.fromList(
        List.generate(
          1024,
          (index) => good ? ((index + index ~/ 32).isEven ? 80 : 180) : 10,
        ),
      ),
      bytesPerRow: 32,
    ));
    await tester.pump();
    h.readers.last.reply(
      cropped
          ? const LiveSheetCropped()
          : const LiveSheetFound(
              sheetLongSidePx: 900,
              discDiameterMm: 90,
              holdsMinPatches: true,
            ),
    );
    await tester.pump();
    await tester.pump();
  }
}

void main() {
  for (final entry in {
    'light': AppTheme.light,
    'dark': AppTheme.dark,
    'sun': AppTheme.sun,
  }.entries) {
    testWidgets('${entry.key}_permission_states_explain_and_allow_retry', (
      tester,
    ) async {
      for (final status in [
        AppPermissionStatus.denied,
        AppPermissionStatus.permanentlyDenied,
        AppPermissionStatus.restricted,
      ]) {
        var retries = 0;
        await tester.pumpWidget(
          MaterialApp(
            theme: entry.value,
            home: CameraPermissionDeniedView(
              status: status,
              onRetry: () => retries++,
            ),
          ),
        );
        expect(find.text('Nova análise'), findsOneWidget);
        if (status == AppPermissionStatus.restricted) {
          expect(find.text('Câmera restrita'), findsOneWidget);
          expect(find.text('Tentar novamente'), findsNothing);
        } else if (status == AppPermissionStatus.permanentlyDenied) {
          expect(find.text('Abrir configurações'), findsOneWidget);
        } else {
          final button = find.text('Tentar novamente');
          expect(button, findsOneWidget);
          await tester.tap(button);
          expect(retries, 1);
        }
      }
    });

    testWidgets('${entry.key}_chips_cover_every_state_and_passive_semantics', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final h = await openGuidedCamera(tester, theme: entry.value);
      expect(find.text('Nova análise'), findsOneWidget);
      expect(find.textContaining('Simulação'), findsNothing);
      expect(
        tester
            .widgetList<QualityChip>(find.byType(QualityChip))
            .every((chip) => chip.status == QualityStatus.adjusting),
        isTrue,
      );
      await readQuality(tester, h, good: false, cropped: true);
      expect(
        tester
            .widgetList<QualityChip>(find.byType(QualityChip))
            .every((chip) => chip.status == QualityStatus.failed),
        isTrue,
      );
      await tiltTo(tester, h, 0);
      await readQuality(tester, h, good: true);
      for (final chip in tester.widgetList<QualityChip>(
        find.byType(QualityChip),
      )) {
        expect(chip.status, QualityStatus.ready);
        final node = tester.getSemantics(find.byWidget(chip));
        expect(node.getSemanticsData().flagsCollection.isLiveRegion, isTrue);
        expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isFalse);
      }
      await backOut(tester);
      semantics.dispose();
    });

    testWidgets('${entry.key}_blocked_feedback_expires_and_restarts', (
      tester,
    ) async {
      final h = await openGuidedCamera(tester, theme: entry.value);
      await readQuality(tester, h, good: false, cropped: true);
      await tester.tap(shutter);
      await tester.pump();
      expect(find.byType(CaptureAlert), findsOneWidget);
      expect(
        find.textContaining('Pouca luz, fora de foco, perto demais'),
        findsOneWidget,
      );
      expect(
        tester
            .widgetList<QualityChip>(find.byType(QualityChip))
            .every((chip) => chip.highlight),
        isTrue,
      );
      await tester.pump(const Duration(milliseconds: 60));
      expect(
        tester
            .widget<Transform>(
              find.byKey(const ValueKey('guided-camera-shake')),
            )
            .transform
            .storage[12],
        isNot(0),
      );
      await tester.pump(const Duration(milliseconds: 240));
      expect(
        tester
            .widget<Transform>(
              find.byKey(const ValueKey('guided-camera-shake')),
            )
            .transform
            .storage[12],
        closeTo(0, .001),
      );
      expect(
        h.cameras.log.where(
          (s) => s == 'haptic:HapticFeedbackType.heavyImpact',
        ),
        hasLength(2),
      );
      expect(h.cameras.cameras.single.takePictureCalls, 0);
      await tester.pump(const Duration(milliseconds: 3000));
      await tester.tap(shutter);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 3799));
      expect(find.byType(CaptureAlert), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 1));
      expect(find.byType(CaptureAlert), findsNothing);
      expect(
        tester
            .widgetList<QualityChip>(find.byType(QualityChip))
            .any((chip) => chip.highlight),
        isFalse,
      );
      await backOut(tester);
    });

    testWidgets('${entry.key}_ready_capture_scales_flashes_and_vibrates', (
      tester,
    ) async {
      final h = await openGuidedCamera(tester, theme: entry.value);
      await tiltTo(tester, h, 0);
      await readQuality(tester, h, good: true);
      final gate = Completer<void>();
      h.cameras.cameras.single.pictureGate = gate;
      await tester.tap(shutter);
      await tester.pump();
      final scale = tester.widget<AnimatedScale>(
        find.descendant(of: shutter, matching: find.byType(AnimatedScale)),
      );
      expect(scale.scale, .86);
      final flash = find.byKey(const ValueKey('guided-camera-flash'));
      expect(flash, entry.key == 'sun' ? findsNothing : findsOneWidget);
      if (entry.key != 'sun') {
        expect(tester.widget<ColoredBox>(flash).color, const Color(0x8CFFFFFF));
      }
      expect(h.cameras.log, contains('haptic:HapticFeedbackType.mediumImpact'));
      gate.complete();
      await tester.pumpAndSettle();
      expect(h.popped, hasLength(1));
      expect(h.cameras.log.last, 'orientations:[]');
    });

    testWidgets('${entry.key}_small_screen_large_text_and_tablet_fit', (
      tester,
    ) async {
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        tester.platformDispatcher.clearTextScaleFactorTestValue();
      });
      for (final size in [const Size(320, 568), const Size(800, 1280)]) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        final h = await openGuidedCamera(tester, theme: entry.value);
        await readQuality(tester, h, good: false, cropped: true);
        await tester.ensureVisible(shutter);
        await tester.tap(shutter);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(
          h.cameras.log.first,
          'orientations:[DeviceOrientation.portraitUp]',
        );
        await backOut(tester);
        await tester.pumpWidget(const SizedBox());
      }
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });
  }

  testWidgets(
    'automatic_capture_waits_for_quality_and_rearms_when_it_improves',
    (tester) async {
      final h = await openGuidedCamera(tester);
      await tiltTo(tester, h, 0);
      await readQuality(tester, h, good: false);
      h.advance(1100);
      await readQuality(tester, h, good: false);
      expect(h.cameras.cameras.single.takePictureCalls, 0);
      await readQuality(tester, h, good: true);
      h.advance(1100);
      await readQuality(tester, h, good: true);
      await tester.pumpAndSettle();
      expect(h.cameras.cameras.single.takePictureCalls, 1);
    },
  );

  testWidgets('reduced_motion_omits_capture_scale_and_flash', (tester) async {
    AppMotion.reduceMotion = true;
    addTearDown(() => AppMotion.reduceMotion = false);
    final h = await openGuidedCamera(tester);
    final gate = Completer<void>();
    h.cameras.cameras.single.pictureGate = gate;
    await tester.tap(shutter);
    await tester.pump();
    expect(find.byKey(const ValueKey('guided-camera-flash')), findsNothing);
    expect(
      tester
          .widget<AnimatedScale>(
            find.descendant(of: shutter, matching: find.byType(AnimatedScale)),
          )
          .scale,
      1,
    );
    expect(h.cameras.log, contains('haptic:HapticFeedbackType.mediumImpact'));
    gate.complete();
    await tester.pumpAndSettle();
  });
}
