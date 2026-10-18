import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visiosoil_app/core/features/capture/guided_camera/capture_camera.dart';
import 'package:visiosoil_app/core/features/capture/guided_camera/capture_guide_overlay.dart';
import 'package:visiosoil_app/core/features/capture/guided_camera/live_reading.dart';

import '../../../support/guided_camera_harness.dart';
import '../../../support/guidelines.dart';

const _sound = LiveSheetFound(
  sheetLongSidePx: 900,
  discDiameterMm: 70,
  holdsMinPatches: true,
);
const _cropped = LiveSheetCropped();

final _ring = find.byKey(const ValueKey('guided-camera-ring'));
final _flash = find.byKey(const ValueKey('guided-camera-flash'));

/// One reading answered with [reading], stamped at the harness clock.
Future<void> _read(
  WidgetTester tester,
  GuidedCameraHarness h,
  LiveReading reading,
) async {
  await emitFrame(tester, h);
  h.readers.last.reply(reading);
  // The reply lands in a microtask after the first frame.
  await tester.pump();
  await tester.pump();
}

/// Flat phone, then two sound readings at the current clock: the banner
/// shows green and the window opens.
Future<void> _openWindow(WidgetTester tester, GuidedCameraHarness h) async {
  await tiltTo(tester, h, 0);
  await _read(tester, h, _sound);
  await _read(tester, h, _sound);
}

int _shots(GuidedCameraHarness h) =>
    h.cameras.log.where((e) => e.startsWith('takePicture:')).length;

void main() {
  testWidgets('the_screen_fires_after_a_steady_second', (tester) async {
    final h = await openGuidedCamera(tester);
    await _openWindow(tester, h);
    expect(_shots(h), 0);
    h.advance(500);
    await _read(tester, h, _sound);
    expect(_shots(h), 0, reason: 'half a second');
    h.advance(600);
    await _read(tester, h, _sound);
    await tester.pumpAndSettle();
    expect(_shots(h), 1);
    final log = h.cameras.log;
    expect(log.indexOf('stopFrames:0'), lessThan(log.indexOf('takePicture:0')));
    expect(h.popped.single, isA<GuidedCaptureCaptured>());
  });

  testWidgets('the_banner_says_hold_still_and_the_ring_fills', (tester) async {
    final h = await openGuidedCamera(tester);
    await _openWindow(tester, h);
    expect(bannerText(tester), 'Segure firme…');
    expect(_ring, findsOneWidget);
    await tester.pump(const Duration(milliseconds: 500));
    final ring = tester.widget<CustomPaint>(_ring).painter! as CountdownRingPainter;
    expect(ring.progress, closeTo(0.5, 0.05));

    // Leaving green closes the window and empties the ring at once.
    await _read(tester, h, _cropped);
    await _read(tester, h, _cropped);
    expect(_ring, findsNothing);
    expect(bannerText(tester), 'A folha está cortada. Afaste o celular.');
  });

  testWidgets('the_shutter_wins', (tester) async {
    final h = await openGuidedCamera(tester);
    await _openWindow(tester, h);
    final gate = Completer<void>();
    h.cameras.cameras.single.pictureGate = gate;
    await tester.tap(shutter);
    await tester.pump();
    // The automatic trigger would fire now; the manual shot holds the flag.
    h.advance(1100);
    gate.complete();
    await tester.pumpAndSettle();
    expect(_shots(h), 1);
    expect(h.popped.single, isA<GuidedCaptureCaptured>());
  });

  testWidgets('a_failed_shot_rearms_after_a_new_second', (tester) async {
    final h = await openGuidedCamera(tester);
    h.cameras.takePictureError = const _CaptureFailed();
    await _openWindow(tester, h);
    h.advance(500);
    await _read(tester, h, _sound);
    h.advance(600);
    await _read(tester, h, _sound);
    await tester.pumpAndSettle();
    expect(_shots(h), 1, reason: 'the automatic shot failed');

    h.cameras.takePictureError = null;
    // A new reader starts; its first readings open a new window after the
    // failure, which must last its full second.
    expect(h.readers, hasLength(2));
    h.advance(100);
    await _read(tester, h, _sound);
    await _read(tester, h, _sound);
    h.advance(900);
    await _read(tester, h, _sound);
    await tester.pumpAndSettle();
    expect(_shots(h), 1, reason: 'not yet a full second');
    h.advance(200);
    await _read(tester, h, _sound);
    await tester.pumpAndSettle();
    expect(_shots(h), 2);
    expect(h.popped.single, isA<GuidedCaptureCaptured>());
  });

  testWidgets('a_tap_and_a_firing_in_the_same_frame_take_one_photograph',
      (tester) async {
    final h = await openGuidedCamera(tester);
    await _openWindow(tester, h);
    h.advance(500);
    await _read(tester, h, _sound);
    h.advance(600);
    // The reading that fires and the tap land before the next frame.
    await emitFrame(tester, h);
    h.readers.last.reply(_sound);
    await tester.tap(shutter);
    await tester.pumpAndSettle();
    expect(_shots(h), 1);
    expect(h.popped.single, isA<GuidedCaptureCaptured>());
  });

  testWidgets('a_failed_manual_shot_unlocks', (tester) async {
    final h = await openGuidedCamera(tester);
    h.cameras.takePictureError = const _CaptureFailed();
    await _openWindow(tester, h);
    await tester.tap(shutter);
    await tester.pump();
    await tester.pump();
    expect(_shots(h), 1, reason: 'the manual shot failed');
    expect(h.popped, isEmpty);

    h.cameras.takePictureError = null;
    expect(h.readers, hasLength(2));
    h.advance(100);
    await _read(tester, h, _sound);
    await _read(tester, h, _sound);
    h.advance(900);
    await _read(tester, h, _sound);
    await tester.pumpAndSettle();
    expect(_shots(h), 1, reason: 'not yet a full second');
    h.advance(200);
    await _read(tester, h, _sound);
    await tester.pumpAndSettle();
    expect(_shots(h), 2);
    expect(h.popped.single, isA<GuidedCaptureCaptured>());
  });

  testWidgets('the_reader_fallback_disarms_the_trigger', (tester) async {
    final h = await openGuidedCamera(tester);
    await _openWindow(tester, h);
    expect(_ring, findsOneWidget);
    h.readers.last.fail();
    await tester.pumpAndSettle();
    expect(_ring, findsNothing);
    // Level tilts that still move, so each one is an event the trigger sees.
    for (var i = 0; i < 4; i++) {
      h.advance(500);
      await tiltTo(tester, h, i.isEven ? 0.2 : 0.4);
    }
    await tester.pumpAndSettle();
    expect(_shots(h), 0);
    expect(_ring, findsNothing);
  });

  testWidgets('no_tilt_no_trigger', (tester) async {
    final h = await openGuidedCamera(tester);
    h.tilt.controller.addError(StateError('no accelerometer'));
    await tester.pumpAndSettle();
    await _read(tester, h, _sound);
    await _read(tester, h, _sound);
    expect(bannerText(tester), 'Folha e solo certos.');
    expect(_ring, findsNothing);
    for (var i = 0; i < 4; i++) {
      h.advance(500);
      await _read(tester, h, _sound);
    }
    await tester.pumpAndSettle();
    expect(_shots(h), 0);
  });

  testWidgets('the_flash_shows_and_respects_reduce_motion', (tester) async {
    for (final reduce in [false, true]) {
      final h = GuidedCameraHarness();
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          FakeAccessibilityFeatures(disableAnimations: reduce);
      addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      await openGuidedCamera(tester, harness: h);
      final gate = Completer<void>();
      h.cameras.cameras.single.pictureGate = gate;
      await _openWindow(tester, h);
      h.advance(500);
      await _read(tester, h, _sound);
      h.advance(600);
      await _read(tester, h, _sound);
      expect(_flash, reduce ? findsNothing : findsOneWidget, reason: 'reduce $reduce');
      gate.complete();
      await tester.pumpAndSettle();
      expect(_shots(h), 1, reason: 'reduce $reduce');
    }
  });

  testWidgets('the_trigger_adds_no_haptic', (tester) async {
    final h = await openGuidedCamera(tester);
    await _openWindow(tester, h);
    h.advance(500);
    await _read(tester, h, _sound);
    h.advance(600);
    await _read(tester, h, _sound);
    await tester.pumpAndSettle();
    final haptics = h.cameras.log.where((e) => e.startsWith('haptic:'));
    expect(haptics, ['haptic:HapticFeedbackType.selectionClick'],
        reason: 'only the green tick of SPEC 0166');
  });

  testWidgets('a_release_closes_the_window', (tester) async {
    final h = await openGuidedCamera(tester);
    await _openWindow(tester, h);
    final binding = tester.binding;
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pumpAndSettle();
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    h.advance(1100);
    await tiltTo(tester, h, 0);
    expect(_shots(h), 0, reason: 'the window before the release is gone');
    expect(_ring, findsNothing);
  });
  for (final (name, theme) in appThemes) {
    testWidgets('the_ring_meets_guidelines_$name', (tester) async {
      final semantics = tester.ensureSemantics();
      final h = await openGuidedCamera(tester, theme: theme);
      await _openWindow(tester, h);
      expect(_ring, findsOneWidget);
      await expectMeetsGuidelines(tester);
      semantics.dispose();
    });
  }
}

class _CaptureFailed implements Exception {
  const _CaptureFailed();

}
