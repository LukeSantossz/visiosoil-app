import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:visiosoil_app/core/features/capture/guided_camera/ambient_light_source.dart';
import 'package:visiosoil_app/core/features/capture/guided_camera/camera_optics.dart';
import 'package:visiosoil_app/core/features/capture/guided_camera/camera_release_queue.dart';
import 'package:visiosoil_app/core/features/capture/guided_camera/capture_camera.dart';
import 'package:visiosoil_app/core/features/capture/guided_camera/live_reading.dart';
import 'package:visiosoil_app/core/features/capture/guided_camera/live_sheet_reader.dart';
import 'package:visiosoil_app/core/features/capture/guided_camera/tilt_source.dart';
import 'package:visiosoil_app/core/services/still_size_store.dart';
import 'package:visiosoil_app/providers/inference_provider.dart';

/// Makes a fresh camera each time the guided screen opens one, since a
/// released camera is not reused (SPEC 0165). Overridden with a fake in tests.
final captureCameraFactoryProvider = Provider<CaptureCameraFactory>(
  (ref) => PluginCaptureCamera.new,
);

/// The accelerometer behind the guided camera's level. Overridden in tests.
final tiltSourceProvider = Provider<TiltSource>(
  (ref) => SensorsPlusTiltSource(),
);

/// The lens and sensor behind the distance chip's estimate (SPEC 0238).
/// Overridden in tests.
final cameraOpticsSourceProvider = Provider<CameraOpticsSource>(
  (ref) => const PlatformCameraOpticsSource(),
);

/// The ambient light sensor behind the light chip's lux (SPEC 0238).
/// Overridden in tests.
final ambientLightSourceProvider = Provider<AmbientLightSource>(
  (ref) => const PlatformAmbientLightSource(),
);

/// The app-wide queue of guided camera releases and orientation resets, so
/// a reopened camera waits for the previous one to close (SPEC 0165).
final cameraReleaseQueueProvider = Provider<CameraReleaseQueue>(
  (ref) => CameraReleaseQueue(),
);

/// The size of this device's stills, learned from the first guided shot
/// (SPEC 0166). Overridden with a fake in tests.
final stillSizeStoreProvider = Provider<StillSizeStore>(
  (ref) => SharedPreferencesStillSizeStore(),
);

/// Loads the contract's numbers the live reader needs, or null when the
/// contract cannot be loaded: the screen then reads nothing live (SPEC 0166).
final liveContractLoaderProvider = Provider<Future<LiveContract?> Function()>(
  (ref) => () async {
    final inference = ref.read(inferenceServiceProvider);
    final cause = await inference.initialize();
    final contract = inference.contract;
    if (cause != null || contract == null) return null;
    return liveContractOf(contract);
  },
);

/// A clock that starts at [now]'s first reading and then moves only by
/// [watch]'s elapsed time, so a change to the wall clock cannot reach it.
DateTime Function() steadyClock({
  DateTime Function() now = DateTime.now,
  Stopwatch? watch,
}) {
  final start = now();
  final elapsed = (watch ?? Stopwatch())..start();
  return () => start.add(elapsed.elapsed);
}

/// The clock the automatic capture stamps its events with (SPEC 0167): one
/// that only moves forward, so the device's clock changing mid-window can
/// neither fire it early nor hold it back. Overridden in tests to drive the
/// one-second window by hand.
final autoCaptureClockProvider = Provider<DateTime Function()>(
  (ref) => steadyClock(),
);

/// Spawns the live sheet reader (SPEC 0166). Overridden with a fake in tests.
final liveSheetReaderFactoryProvider = Provider<LiveSheetReaderFactory>(
  (ref) => IsolateLiveSheetReader.spawn,
);
