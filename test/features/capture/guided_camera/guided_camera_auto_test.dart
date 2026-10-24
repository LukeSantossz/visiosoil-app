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
    final ring =
        tester.widget<CustomPaint>(_ring).painter! as CountdownRingPainter;
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

  testWidgets('a_suppressed_reading_does_not_count', (tester) async {
    final h = await openGuidedCamera(tester);
    await _openWindow(tester, h);
    h.advance(500);
    // One cropped reading: the debounce keeps the banner green and the window
    // open, but the reading is not one of the window's two.
    await _read(tester, h, _cropped);
    expect(bannerText(tester), 'Segure firme…');
    h.advance(600);
    await tiltTo(tester, h, 0);
    expect(_shots(h), 0, reason: 'one counted reading');
    await _read(tester, h, _sound);
    await tester.pumpAndSettle();
    expect(_shots(h), 1);
  });

  testWidgets('a_shot_clears_the_ring_while_it_runs', (tester) async {
    final h = await openGuidedCamera(tester);
    await _openWindow(tester, h);
    expect(_ring, findsOneWidget);
    final gate = Completer<void>();
    h.cameras.cameras.single.pictureGate = gate;
    await tester.tap(shutter);
    await tester.pump();
    expect(_ring, findsNothing);
    expect(bannerText(tester), isNot('Segure firme…'));
    gate.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('a_tap_and_a_firing_in_the_same_frame_take_one_photograph', (
    tester,
  ) async {
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

  testWidgets('an_unchanged_tilt_still_reaches_the_trigger', (tester) async {
    final h = await openGuidedCamera(tester);
    await _openWindow(tester, h);
    h.advance(500);
    await _read(tester, h, _sound);
    h.advance(600);
    // A perfectly still phone repeats the same smoothed tilt; that sample is
    // still the first event past the second.
    await tiltTo(tester, h, 0);
    await tester.pumpAndSettle();
    expect(_shots(h), 1);
    expect(h.popped.single, isA<GuidedCaptureCaptured>());
  });

  testWidgets('losing_the_tilt_closes_the_window_at_once', (tester) async {
    final h = await openGuidedCamera(tester);
    await _openWindow(tester, h);
    expect(_ring, findsOneWidget);
    h.tilt.controller.addError(StateError('no accelerometer'));
    await tester.pump();
    expect(_ring, findsNothing);
    expect(bannerText(tester), isNot('Segure firme…'));
  });

  testWidgets('closing_the_screen_disarms_the_trigger', (tester) async {
    final h = await openGuidedCamera(tester);
    await _openWindow(tester, h);
    h.advance(500);
    await _read(tester, h, _sound);
    h.advance(600);
    await emitFrame(tester, h);
    // The reading that would fire lands during the pop's transition.
    await tester.tap(closeButton);
    h.readers.last.reply(_sound);
    await tester.pump();
    await tester.pumpAndSettle();
    expect(_shots(h), 0);
    expect(h.popped.single, isNot(isA<GuidedCaptureCaptured>()));
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
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await openGuidedCamera(tester, harness: h);
      final gate = Completer<void>();
      h.cameras.cameras.single.pictureGate = gate;
      await _openWindow(tester, h);
      h.advance(500);
      await _read(tester, h, _sound);
      h.advance(600);
      await _read(tester, h, _sound);
      expect(
        _flash,
        reduce ? findsNothing : findsOneWidget,
        reason: 'reduce $reduce',
      );
      gate.complete();
      await tester.pumpAndSettle();
      expect(_shots(h), 1, reason: 'reduce $reduce');
    }
  });

  // Amended 2026-10-18: the ring stays still under reduced motion.
  testWidgets('the_ring_stays_still_under_reduce_motion', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final h = await openGuidedCamera(tester);
    await _openWindow(tester, h);
    double progress() =>
        (tester.widget<CustomPaint>(_ring).painter! as CountdownRingPainter)
            .progress;
    expect(progress(), 1);
    await tester.pump(const Duration(milliseconds: 500));
    expect(progress(), 1);

    await _read(tester, h, _cropped);
    await _read(tester, h, _cropped);
    expect(_ring, findsNothing);
  });

  testWidgets('reduce_motion_turned_on_mid_window_stills_the_ring', (
    tester,
  ) async {
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final h = await openGuidedCamera(tester);
    await _openWindow(tester, h);
    await tester.pump(const Duration(milliseconds: 200));
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    await tester.pump();
    final ring =
        tester.widget<CustomPaint>(_ring).painter! as CountdownRingPainter;
    expect(ring.progress, 1);
  });

  // R2 round 1: turning reduced motion off resumes the ring where the window
  // is, not from empty.
  testWidgets('reduce_motion_turned_off_mid_window_resumes_the_ring', (
    tester,
  ) async {
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    final h = await openGuidedCamera(tester);
    await _openWindow(tester, h);
    h.advance(400);
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures();
    await tester.pump();
    final ring =
        tester.widget<CustomPaint>(_ring).painter! as CountdownRingPainter;
    expect(ring.progress, closeTo(0.4, 0.05));
  });

  testWidgets('the_trigger_plays_the_capture_haptic', (tester) async {
    final h = await openGuidedCamera(tester);
    await _openWindow(tester, h);
    h.advance(500);
    await _read(tester, h, _sound);
    h.advance(600);
    await _read(tester, h, _sound);
    await tester.pumpAndSettle();
    final haptics = h.cameras.log.where((e) => e.startsWith('haptic:'));
    expect(haptics, [
      'haptic:HapticFeedbackType.selectionClick',
      'haptic:HapticFeedbackType.mediumImpact',
    ], reason: 'readiness followed by v11 capture feedback');
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
