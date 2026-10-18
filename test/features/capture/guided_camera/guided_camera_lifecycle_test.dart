import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visiosoil_app/core/features/capture/guided_camera/capture_camera.dart';

import '../../../support/guided_camera_harness.dart';
import '../../../support/guidelines.dart';

void main() {
  testWidgets('the_camera_follows_the_lifecycle', (tester) async {
    final h = await openGuidedCamera(tester);
    final binding = tester.binding;

    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(h.cameras.log.where((entry) => entry == 'dispose:0'), hasLength(1));
    expect(fakePreview, findsNothing);

    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(h.cameras.cameras, hasLength(2));
    expect(fakePreview, findsOneWidget);

    // A second resume while an initialisation is pending starts none.
    h.cameras.initializeGate = Completer<void>();
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(h.cameras.cameras, hasLength(3));
    h.cameras.initializeGate!.complete();
    h.cameras.initializeGate = null;
    await tester.pumpAndSettle();
    expect(fakePreview, findsOneWidget);

    binding.handleAppLifecycleStateChanged(AppLifecycleState.detached);
    await tester.pump();
    expect(h.cameras.cameras.last.disposed, isTrue);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
  });

  testWidgets('a_stale_initialisation_restarts_when_wanted', (tester) async {
    final h = GuidedCameraHarness()..cameras.initializeGate = Completer<void>();
    await openGuidedCamera(tester, harness: h);
    final binding = tester.binding;
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    final gate = h.cameras.initializeGate!;
    h.cameras.initializeGate = null;
    gate.complete();
    await tester.pumpAndSettle();

    expect(h.cameras.cameras.first.disposed, isTrue);
    expect(h.cameras.cameras.where((camera) => !camera.disposed), hasLength(1));
    expect(fakePreview, findsOneWidget);
  });

  testWidgets('an_initialisation_after_dispose_disposes_its_camera',
      (tester) async {
    final h = GuidedCameraHarness()..cameras.initializeGate = Completer<void>();
    await openGuidedCamera(tester, harness: h);
    await backOut(tester);

    h.cameras.initializeGate!.complete();
    await tester.pumpAndSettle();
    expect(h.cameras.cameras.single.disposed, isTrue);
    expect(h.cameras.cameras, hasLength(1));
  });

  testWidgets('a_revoked_permission_cancels', (tester) async {
    final h = await openGuidedCamera(tester);
    final binding = tester.binding;
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    h.cameras.initializeError =
        const CameraPermissionRevokedException('CameraAccessDenied');
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(h.popped.single, isA<GuidedCaptureCancelled>());
  });

  testWidgets('another_error_on_resume_is_unavailable', (tester) async {
    final h = await openGuidedCamera(tester);
    final binding = tester.binding;
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    h.cameras.initializeError = const CameraUnavailableException('gone');
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(h.popped.single, isA<GuidedCaptureUnavailable>());
  });

  testWidgets('the_orientation_is_restored', (tester) async {
    final h = await openGuidedCamera(tester);
    final log = h.cameras.log;
    const portrait = 'orientations:[DeviceOrientation.portraitUp]';
    expect(log, contains(portrait));
    expect(log.indexOf(portrait), lessThan(log.indexOf('initialize:0')));

    await backOut(tester);
    expect(log.last, 'orientations:[]');
    expect(log.indexOf('dispose:0'), lessThan(log.lastIndexOf('orientations:[]')));
  });

  for (final (name, theme) in appThemes) {
    testWidgets('guided_camera_meets_guidelines_$name', (tester) async {
      final semantics = tester.ensureSemantics();
      final h = await openGuidedCamera(tester, theme: theme);
      for (final degrees in [0.0, 8.0, 20.0]) {
        await tiltTo(tester, h, degrees);
        await expectMeetsGuidelines(tester);
      }
      semantics.dispose();
    });
  }

  // Final review fixes (R2, Codex Luna).
  testWidgets('a_resume_waits_for_the_release', (tester) async {
    final h = await openGuidedCamera(tester);
    final binding = tester.binding;
    h.cameras.disposeGate = Completer<void>();
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(h.cameras.log, isNot(contains('initialize:1')),
        reason: 'a second camera must not open while the first is released');

    h.cameras.disposeGate!.complete();
    h.cameras.disposeGate = null;
    await tester.pumpAndSettle();
    final log = h.cameras.log;
    expect(log.indexOf('dispose:0'), lessThan(log.indexOf('initialize:1')));
    expect(fakePreview, findsOneWidget);
  });

  testWidgets('closing_during_initialisation_restores_after_release',
      (tester) async {
    final h = GuidedCameraHarness()..cameras.initializeGate = Completer<void>();
    await openGuidedCamera(tester, harness: h);
    await backOut(tester);
    h.cameras.initializeGate!.complete();
    await tester.pumpAndSettle();

    final log = h.cameras.log;
    expect(log, contains('dispose:0'));
    expect(log.indexOf('dispose:0'), lessThan(log.lastIndexOf('orientations:[]')));
  });

  testWidgets('a_failing_release_still_restores_the_orientation',
      (tester) async {
    final h = await openGuidedCamera(tester);
    h.cameras.disposeError = CameraUnavailableException('release failed');
    await backOut(tester);
    expect(h.cameras.log.last, 'orientations:[]');
    expect(tester.takeException(), isNull);
  });

  testWidgets('a_stale_camera_is_released_before_the_next_opens',
      (tester) async {
    final h = GuidedCameraHarness()..cameras.initializeGate = Completer<void>();
    await openGuidedCamera(tester, harness: h);
    final binding = tester.binding;
    // Released while camera 0 initialises: it completes stale.
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();

    h.cameras.disposeGate = Completer<void>();
    final initGate = h.cameras.initializeGate!;
    h.cameras.initializeGate = null;
    initGate.complete();
    await tester.pump();
    // Camera 0 is being released; a resume now must wait for it.
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(h.cameras.log, isNot(contains('initialize:1')));

    h.cameras.disposeGate!.complete();
    h.cameras.disposeGate = null;
    await tester.pumpAndSettle();
    final log = h.cameras.log;
    expect(log.indexOf('dispose:0'), lessThan(log.indexOf('initialize:1')));
    expect(fakePreview, findsOneWidget);
  });

  testWidgets('a_failed_camera_is_released_before_the_next_opens',
      (tester) async {
    final h = await openGuidedCamera(tester);
    final binding = tester.binding;
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pumpAndSettle();
    // Camera 1 fails to open while the screen is wanted; its release is held.
    h.cameras.initializeGate = Completer<void>();
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    h.cameras.disposeGate = Completer<void>();
    h.cameras.initializeError = const CameraUnavailableException('busy');
    final initGate = h.cameras.initializeGate!;
    h.cameras.initializeGate = null;
    initGate.complete();
    await tester.pump();
    h.cameras.initializeError = null;
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(h.cameras.log, isNot(contains('initialize:2')));

    h.cameras.disposeGate!.complete();
    h.cameras.disposeGate = null;
    await tester.pumpAndSettle();
    final log = h.cameras.log;
    expect(log.indexOf('dispose:1'), lessThan(log.indexOf('initialize:2')));
  });

  // R2 round 2: the queue spans screens, not one screen's lifetime.
  testWidgets('a_new_screen_waits_for_the_previous_release', (tester) async {
    final h = await openGuidedCamera(tester);
    h.cameras.disposeGate = Completer<void>();
    await backOut(tester);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(h.cameras.log, isNot(contains('initialize:1')),
        reason: 'the first camera is still closing');

    h.cameras.disposeGate!.complete();
    h.cameras.disposeGate = null;
    await tester.pumpAndSettle();
    final log = h.cameras.log;
    const portrait = 'orientations:[DeviceOrientation.portraitUp]';
    final reset = log.indexOf('orientations:[]');
    expect(log.indexOf('dispose:0'), lessThan(reset));
    expect(reset, lessThan(log.lastIndexOf(portrait)));
    expect(log.lastIndexOf(portrait), lessThan(log.indexOf('initialize:1')));
    expect(fakePreview, findsOneWidget);
  });

  // #391: a release never disposes the controller under a shot.
  testWidgets('a_release_waits_for_the_shot_in_flight', (tester) async {
    final h = await openGuidedCamera(tester);
    final camera = h.cameras.cameras.single;
    final gate = Completer<void>();
    camera.pictureGate = gate;
    await tester.tap(shutter);
    await tester.pump();
    expect(camera.takePictureCalls, 1);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(camera.disposed, isFalse,
        reason: 'takePicture is still running on this camera');

    gate.complete();
    await tester.pumpAndSettle();
    expect(camera.disposed, isTrue);
    expect(h.popped.single, isA<GuidedCaptureCaptured>());
    expect(tester.takeException(), isNull);
  });

  testWidgets('a_close_waits_for_the_shot_in_flight', (tester) async {
    final h = await openGuidedCamera(tester);
    final camera = h.cameras.cameras.single;
    final gate = Completer<void>();
    camera.pictureGate = gate;
    await tester.tap(shutter);
    await tester.pump();
    await backOut(tester);
    expect(camera.disposed, isFalse,
        reason: 'takePicture is still running on this camera');

    gate.complete();
    await tester.pumpAndSettle();
    expect(camera.disposed, isTrue);
    expect(h.popped, [isNull]);
    expect(tester.takeException(), isNull);
  });
}
