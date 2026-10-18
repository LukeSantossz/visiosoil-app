import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart' show CameraException;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:visiosoil_app/core/features/capture/guided_camera/capture_camera.dart';
import 'package:visiosoil_app/core/features/capture/guided_camera/live_reading.dart';

import '../../../support/guided_camera_harness.dart';

const _cropped = LiveSheetCropped();
const _sound = LiveSheetFound(
  sheetLongSidePx: 900,
  discDiameterMm: 70,
  holdsMinPatches: true,
);

Future<void> _read(
  WidgetTester tester,
  GuidedCameraHarness h,
  LiveReading reading,
) async {
  await emitFrame(tester, h);
  await replyWith(tester, h, reading);
}

void main() {
  testWidgets('the_banner_shows_the_live_rows', (tester) async {
    final h = await openGuidedCamera(tester);
    await tiltTo(tester, h, 0);
    expect(h.readers, hasLength(1));
    expect(h.cameras.log, contains('startFrames:0'));

    await _read(tester, h, _cropped);
    expect(bannerText(tester), 'Nivelado. Encaixe a folha no contorno.',
        reason: 'one reading does not change the banner');
    await _read(tester, h, _cropped);
    expect(bannerText(tester), 'A folha está cortada. Afaste o celular.');
  });

  testWidgets('one_frame_in_flight', (tester) async {
    final h = await openGuidedCamera(tester);
    await emitFrame(tester, h);
    await emitFrame(tester, h);
    await emitFrame(tester, h);
    expect(h.readers.single.requests, hasLength(1));
    await replyWith(tester, h, _cropped);
    await emitFrame(tester, h);
    expect(h.readers.single.requests, hasLength(2));
  });

  testWidgets('a_stale_reading_is_discarded', (tester) async {
    final h = await openGuidedCamera(tester);
    await tiltTo(tester, h, 0);
    await emitFrame(tester, h);
    final stale = h.readers.single.requests.single - 1;
    h.readers.single.reply(_cropped, generation: stale);
    h.readers.single.reply(_cropped, generation: stale);
    await tester.pumpAndSettle();
    expect(bannerText(tester), 'Nivelado. Encaixe a folha no contorno.');
  });

  testWidgets('entering_green_ticks_once', (tester) async {
    final h = await openGuidedCamera(tester);
    await tiltTo(tester, h, 0);
    int ticks() => h.cameras.log
        .where((e) => e == 'haptic:HapticFeedbackType.selectionClick')
        .length;

    await _read(tester, h, _sound);
    await _read(tester, h, _sound);
    // Green with a level phone opens SPEC 0167's one-second window, whose
    // banner replaces row 8's sentence while it lasts.
    expect(bannerText(tester), 'Segure firme…');
    expect(ticks(), 1);
    await _read(tester, h, _sound);
    expect(ticks(), 1, reason: 'staying green ticks once');

    await _read(tester, h, _cropped);
    await _read(tester, h, _cropped);
    await _read(tester, h, _sound);
    await _read(tester, h, _sound);
    expect(ticks(), 2);
  });

  testWidgets('a_failed_reader_falls_back', (tester) async {
    final h = await openGuidedCamera(tester);
    await tiltTo(tester, h, 0);
    await _read(tester, h, _cropped);
    await _read(tester, h, _cropped);
    h.readers.single.fail();
    await tester.pumpAndSettle();

    expect(bannerText(tester), 'Nivelado. Encaixe a folha no contorno.');
    expect(h.errors.sources, ['live_sheet_reader']);
    expect(h.cameras.log, contains('stopFrames:0'));
    expect(h.readers.single.killed, isTrue);
    await emitFrame(tester, h);
    expect(h.readers, hasLength(1), reason: 'not restarted this visit');

    await tester.tap(shutter);
    await tester.pumpAndSettle();
    expect(h.popped.single, isA<GuidedCaptureCaptured>());
  });

  testWidgets('a_reader_that_does_not_answer_falls_back', (tester) async {
    final h = await openGuidedCamera(tester);
    await emitFrame(tester, h);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(h.errors.sources, ['live_sheet_reader']);
    expect(h.readers.single.killed, isTrue);
    expect(h.cameras.log, contains('stopFrames:0'));
  });

  testWidgets('the_shot_stops_the_reader_first', (tester) async {
    final h = await openGuidedCamera(tester);
    await emitFrame(tester, h);
    await tester.tap(shutter);
    await tester.pumpAndSettle();
    final log = h.cameras.log;
    expect(log.indexOf('stopFrames:0'), greaterThanOrEqualTo(0));
    expect(log.indexOf('stopFrames:0'), lessThan(log.indexOf('takePicture:0')));
    expect(h.readers.single.killed, isTrue);
    expect(h.popped.single, isA<GuidedCaptureCaptured>());
  });

  testWidgets('the_lifecycle_stops_the_reader', (tester) async {
    final h = await openGuidedCamera(tester);
    final binding = tester.binding;
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pumpAndSettle();
    final log = h.cameras.log;
    expect(h.readers.first.killed, isTrue);
    expect(log, contains('stopFrames:0'));
    expect(log.indexOf('stopFrames:0'), lessThan(log.indexOf('dispose:0')));

    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(h.readers, hasLength(2));
    expect(log, contains('startFrames:1'));

    await backOut(tester);
    expect(h.readers.last.killed, isTrue);
  });

  testWidgets('no_contract_no_reader', (tester) async {
    final h = GuidedCameraHarness()..liveContract = null;
    await openGuidedCamera(tester, harness: h);
    await tiltTo(tester, h, 0);
    expect(h.readers, isEmpty);
    expect(h.cameras.log, isNot(contains('startFrames:0')));
    expect(bannerText(tester), 'Nivelado. Encaixe a folha no contorno.');
    await tester.tap(shutter);
    await tester.pumpAndSettle();
    expect(h.popped.single, isA<GuidedCaptureCaptured>());
  });

  testWidgets('a_shot_teaches_the_still_size', (tester) async {
    final dir = Directory.systemTemp.createTempSync('guided_still');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/still.jpg')
      ..writeAsBytesSync(img.encodeJpg(img.Image(width: 30, height: 40)));
    final h = await openGuidedCamera(tester);
    h.cameras.picturePath = file.path;
    await tester.tap(shutter);
    await settleIo(tester);
    await tester.pumpAndSettle();
    expect(h.stillSizes.size, const Size(30, 40));
    // Learned before the photograph is handed over, so nothing that owns the
    // file afterwards can race the read.
    expect(h.stillSizeAtPop.single, const Size(30, 40));
  });

  testWidgets('a_known_still_size_asks_to_come_closer', (tester) async {
    final h = GuidedCameraHarness()..stillSizes.size = const Size(3000, 4000);
    await openGuidedCamera(tester, harness: h);
    await tiltTo(tester, h, 0);
    // The tiny frame is 4 × 2: a sheet 1 px long is far too coarse.
    const far = LiveSheetFound(
      sheetLongSidePx: 1,
      discDiameterMm: 70,
      holdsMinPatches: true,
    );
    await _read(tester, h, far);
    await _read(tester, h, far);
    expect(bannerText(tester), 'Aproxime o celular da folha.');
  });

  // R2 review fixes (Codex Luna).
  testWidgets('a_shot_during_startup_keeps_the_reader_off', (tester) async {
    final h = GuidedCameraHarness()..contractGate = Completer<void>();
    await openGuidedCamera(tester, harness: h);
    final gate = Completer<void>();
    h.cameras.cameras.single.pictureGate = gate;
    await tester.tap(shutter);
    await tester.pump();

    h.contractGate!.complete();
    await tester.pumpAndSettle();
    expect(h.readers, isEmpty, reason: 'the shot invalidated the startup');
    expect(h.cameras.log, isNot(contains('startFrames:0')));

    gate.complete();
    await tester.pumpAndSettle();
    expect(h.popped.single, isA<GuidedCaptureCaptured>());
  });

  testWidgets('a_reader_that_cannot_start_falls_back', (tester) async {
    final h = GuidedCameraHarness()..spawnError = StateError('no isolate');
    await openGuidedCamera(tester, harness: h);
    await tiltTo(tester, h, 0);
    expect(tester.takeException(), isNull);
    expect(h.errors.sources, ['live_sheet_reader']);
    expect(h.cameras.log, isNot(contains('startFrames:0')));
    expect(bannerText(tester), 'Nivelado. Encaixe a folha no contorno.');
    await tester.tap(shutter);
    await tester.pumpAndSettle();
    expect(h.popped.single, isA<GuidedCaptureCaptured>());
  });

  testWidgets('a_stream_that_will_not_stop_is_recorded', (tester) async {
    final h = await openGuidedCamera(tester);
    await emitFrame(tester, h);
    h.cameras.stopFramesError = CameraException('stopFailed', 'still streaming');
    await tester.tap(shutter);
    await tester.pumpAndSettle();
    expect(h.errors.sources, contains('guided_camera'));
    // The shot is still attempted; its own failure path handles a camera
    // that cannot capture while streaming.
    expect(h.cameras.log, contains('takePicture:0'));
    expect(h.popped.single, isA<GuidedCaptureCaptured>());
  });

  testWidgets('a_shot_waits_for_a_stream_still_starting', (tester) async {
    final h = GuidedCameraHarness()..cameras.startFramesGate = Completer<void>();
    await openGuidedCamera(tester, harness: h);
    expect(h.cameras.log, contains('startFrames:0'));
    await tester.tap(shutter);
    await tester.pump();
    expect(h.cameras.log, isNot(contains('takePicture:0')),
        reason: 'the stream is still starting');

    h.cameras.startFramesGate!.complete();
    await tester.pumpAndSettle();
    final log = h.cameras.log;
    expect(log.indexOf('stopFrames:0'), greaterThanOrEqualTo(0));
    expect(log.indexOf('stopFrames:0'), lessThan(log.indexOf('takePicture:0')));
    expect(h.cameras.cameras.single.streaming, isFalse);
    expect(h.popped.single, isA<GuidedCaptureCaptured>());
  });
}
