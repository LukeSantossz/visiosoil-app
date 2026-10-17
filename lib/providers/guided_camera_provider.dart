import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:visiosoil_app/core/features/capture/guided_camera/capture_camera.dart';
import 'package:visiosoil_app/core/features/capture/guided_camera/tilt_source.dart';

/// Makes a fresh camera each time the guided screen opens one, since a
/// released camera is not reused (SPEC 0165). Overridden with a fake in tests.
final captureCameraFactoryProvider = Provider<CaptureCameraFactory>(
  (ref) => PluginCaptureCamera.new,
);

/// The accelerometer behind the guided camera's level. Overridden in tests.
final tiltSourceProvider = Provider<TiltSource>(
  (ref) => SensorsPlusTiltSource(),
);
