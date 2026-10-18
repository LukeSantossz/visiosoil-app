import 'package:flutter_riverpod/flutter_riverpod.dart';
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

/// The clock the automatic capture stamps its events with (SPEC 0167).
/// Overridden in tests to drive the one-second window by hand.
final autoCaptureClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

/// Spawns the live sheet reader (SPEC 0166). Overridden with a fake in tests.
final liveSheetReaderFactoryProvider = Provider<LiveSheetReaderFactory>(
  (ref) => IsolateLiveSheetReader.spawn,
);
