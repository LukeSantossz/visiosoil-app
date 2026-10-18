import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:visiosoil_app/core/features/capture/guided_camera/camera_release_queue.dart';
import 'package:visiosoil_app/core/features/capture/guided_camera/capture_camera.dart';
import 'package:visiosoil_app/core/features/capture/guided_camera/tilt_source.dart';
import 'package:visiosoil_app/core/services/still_size_store.dart';

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
