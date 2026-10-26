import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:visiosoil_app/core/features/capture/guided_camera/capture_camera.dart';
import 'package:visiosoil_app/core/features/capture/guided_camera/guided_camera_screen.dart';
import 'package:visiosoil_app/core/features/capture/guided_camera/live_frame.dart';
import 'package:visiosoil_app/core/features/capture/guided_camera/live_reading.dart';
import 'package:visiosoil_app/core/services/error_report_store.dart';
import 'package:visiosoil_app/core/theme/app_theme.dart';
import 'package:visiosoil_app/providers/error_report_provider.dart';
import 'package:visiosoil_app/providers/guided_camera_provider.dart';

import 'fake_capture_camera.dart';

/// Records the source of every error the screen reports. Anything else falls
/// to noSuchMethod.
class RecordingErrorReportStore implements ErrorReportStore {
  final sources = <String>[];

  @override
  Future<void> record({
    required String source,
    required Object error,
    StackTrace? stack,
    String? library,
  }) async {
    sources.add(source);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The guided camera's fakes, and what the screen popped each time it closed.
class GuidedCameraHarness {
  final cameras = FakeCaptureCameras();
  final tilt = FakeTiltSource();
  final errors = RecordingErrorReportStore();
  final popped = <GuidedCaptureResult?>[];

  /// The live reader's contract, or null for one that failed to load.
  LiveContract? liveContract = (
    canonicalMmPerPx: 0.12920342774728033,
    patchPx: 160,
    strideFraction: 0.5,
    minPatches: 9,
  );

  /// Every live reader the screen spawned, in order (SPEC 0166).
  final readers = <FakeLiveSheetReader>[];
  final stillSizes = FakeStillSizeStore();

  /// When set, loading the contract waits on it.
  Completer<void>? contractGate;

  /// Thrown by the reader factory, when set.
  Object? spawnError;

  /// The stored still size at the moment each result was popped.
  final stillSizeAtPop = <Object?>[];

  /// The clock the automatic capture stamps its events with (SPEC 0167).
  DateTime now = DateTime.utc(2026, 10, 18, 12);

  /// Moves [now] forward.
  void advance(int milliseconds) =>
      now = now.add(Duration(milliseconds: milliseconds));
}

/// Pumps a home page whose "open" button pushes [GuidedCameraScreen], taps
/// it, and records what the screen pops into [GuidedCameraHarness.popped].
Future<GuidedCameraHarness> openGuidedCamera(
  WidgetTester tester, {
  GuidedCameraHarness? harness,
  ThemeData? theme,
  List<Override> overrides = const [],
}) async {
  final h = harness ?? GuidedCameraHarness();
  // A platform call with no handler never answers inside a widget test, and
  // the screen awaits its orientation lock before it opens the camera. Each
  // orientation call is logged with the camera's calls, so a test can check
  // their order.
  final messenger = tester.binding.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
    if (call.method == 'SystemChrome.setPreferredOrientations') {
      h.cameras.log.add('orientations:${call.arguments}');
    }
    if (call.method == 'HapticFeedback.vibrate') {
      h.cameras.log.add('haptic:${call.arguments}');
    }
    return null;
  });
  addTearDown(
    () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
  );
  await tester.pumpWidget(ProviderScope(
    overrides: [
      ...guidedCameraOverrides(h),
      ...overrides,
    ],
    child: MaterialApp(
      theme: theme ?? AppTheme.light,
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async {
              final result =
                  await Navigator.of(context).push<GuidedCaptureResult>(
                MaterialPageRoute(builder: (_) => const GuidedCameraScreen()),
              );
              h.popped.add(result);
              h.stillSizeAtPop.add(h.stillSizes.size);
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return h;
}

/// Feeds enough samples at [degrees] for the smoothed tilt to settle on it,
/// and pumps until the screen has drawn it: the stream delivers its events in
/// a microtask after the first frame.
Future<void> tiltTo(
  WidgetTester tester,
  GuidedCameraHarness h,
  double degrees,
) async {
  final radians = degrees * math.pi / 180;
  for (var i = 0; i < 60; i++) {
    h.tilt.controller.add(
      (x: 0, y: 9.81 * math.sin(radians), z: 9.81 * math.cos(radians)),
    );
  }
  await tester.pumpAndSettle();
}

/// The banner's sentence.
String bannerText(WidgetTester tester) => tester
    .widgetList<Text>(find.descendant(
      of: find.byKey(const ValueKey('guided-camera-banner')),
      matching: find.byType(Text),
    ))
    .map((text) => text.data)
    .join();

final shutter = find.byKey(const ValueKey('guided-camera-shutter'));
final closeButton = find.byKey(const ValueKey('guided-camera-close'));
final levelIndicator = find.byKey(const ValueKey('guided-camera-level'));
final fakePreview = find.byKey(const ValueKey('fake-preview'));

/// Pops the guided camera as a back gesture would.
Future<void> backOut(WidgetTester tester) async {
  tester.state<NavigatorState>(find.byType(Navigator)).maybePop();
  await tester.pumpAndSettle();
}

/// The provider overrides that put the guided camera on [h]'s fakes.
List<Override> guidedCameraOverrides(GuidedCameraHarness h) => [
      captureCameraFactoryProvider.overrideWithValue(h.cameras.create),
      tiltSourceProvider.overrideWithValue(h.tilt),
      errorReportStoreProvider.overrideWithValue(h.errors),
      liveContractLoaderProvider.overrideWithValue(() async {
        await h.contractGate?.future;
        return h.liveContract;
      }),
      liveSheetReaderFactoryProvider.overrideWithValue((contract) async {
        final error = h.spawnError;
        if (error != null) throw error;
        final reader = FakeLiveSheetReader();
        h.readers.add(reader);
        return reader;
      }),
      stillSizeStoreProvider.overrideWithValue(h.stillSizes),
      autoCaptureClockProvider.overrideWithValue(() => h.now),
    ];

/// A tiny luma frame, as the camera's stream would hand one over.
CameraFrame get tinyFrame => (
      format: LivePixelFormat.yuv420,
      width: 4,
      height: 2,
      bytes: Uint8List(8),
      bytesPerRow: 4,
    );

/// Emits a frame from the live camera and lets the screen hand it over.
Future<void> emitFrame(WidgetTester tester, GuidedCameraHarness h) async {
  h.cameras.cameras.last.emitFrame(tinyFrame);
  await tester.pump();
}

/// The live reader answers the last frame with [reading].
Future<void> replyWith(
  WidgetTester tester,
  GuidedCameraHarness h,
  LiveReading reading,
) async {
  h.readers.last.reply(reading);
  await tester.pumpAndSettle();
}

/// Lets real file I/O started inside the fake clock finish: a real wait for
/// the I/O, then a pump for its callbacks, a few times over.
Future<void> settleIo(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
}
