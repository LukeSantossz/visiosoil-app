import 'dart:async';

import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visiosoil_app/core/features/capture/guided_camera/capture_camera.dart';

/// A camera platform that records what the plugin asked of it, so the
/// production [PluginCaptureCamera] is checked without a device.
class _RecordingCameraPlatform extends CameraPlatform {
  _RecordingCameraPlatform(this.cameras, {this.initializeError});

  final List<CameraDescription> cameras;
  final Object? initializeError;
  final calls = <String>[];
  CameraDescription? created;
  MediaSettings? settings;
  ImageFormatGroup? formatGroup;

  @override
  Future<List<CameraDescription>> availableCameras() async => cameras;

  @override
  Future<int> createCameraWithSettings(
    CameraDescription cameraDescription,
    MediaSettings mediaSettings,
  ) async {
    created = cameraDescription;
    settings = mediaSettings;
    calls.add('create');
    return 7;
  }

  @override
  Future<void> initializeCamera(
    int cameraId, {
    ImageFormatGroup imageFormatGroup = ImageFormatGroup.unknown,
  }) async {
    calls.add('initialize');
    formatGroup = imageFormatGroup;
    final error = initializeError;
    if (error != null) throw error;
  }

  @override
  Stream<CameraInitializedEvent> onCameraInitialized(int cameraId) =>
      Stream.value(const CameraInitializedEvent(
        7,
        1280,
        720,
        ExposureMode.auto,
        true,
        FocusMode.auto,
        true,
      ));

  /// Never emits: the plugin awaits its first event in the background, and
  /// an empty stream would fail that wait.
  @override
  Stream<CameraErrorEvent> onCameraError(int cameraId) =>
      StreamController<CameraErrorEvent>().stream;

  @override
  Stream<DeviceOrientationChangedEvent> onDeviceOrientationChanged() =>
      const Stream.empty();

  @override
  Future<void> setFlashMode(int cameraId, FlashMode mode) async =>
      calls.add('flash:${mode.name}');

  @override
  Future<void> lockCaptureOrientation(
    int cameraId,
    DeviceOrientation orientation,
  ) async =>
      calls.add('lock:${orientation.name}');

  @override
  Future<void> dispose(int cameraId) async => calls.add('dispose');
}

const _front = CameraDescription(
  name: 'front',
  lensDirection: CameraLensDirection.front,
  sensorOrientation: 270,
);
const _back = CameraDescription(
  name: 'back',
  lensDirection: CameraLensDirection.back,
  sensorOrientation: 90,
);
const _secondBack = CameraDescription(
  name: 'back2',
  lensDirection: CameraLensDirection.back,
  sensorOrientation: 90,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late CameraPlatform original;
  setUp(() => original = CameraPlatform.instance);
  tearDown(() => CameraPlatform.instance = original);

  test('the_camera_is_configured', () async {
    final platform = _RecordingCameraPlatform([_front, _back, _secondBack]);
    CameraPlatform.instance = platform;
    final camera = PluginCaptureCamera();
    await camera.initialize();

    expect(platform.created?.name, 'back');
    expect(platform.settings?.resolutionPreset, ResolutionPreset.max);
    expect(platform.settings?.enableAudio, isFalse);
    expect(
      platform.calls,
      ['create', 'initialize', 'flash:off', 'lock:portraitUp'],
    );
    expect(camera.previewSize, const Size(720, 1280));
    // Android's luma plane, turned by the sensor's orientation (SPEC 0166).
    expect(platform.formatGroup, ImageFormatGroup.yuv420);
    expect(camera.frameRotationDegrees, 90);

    await camera.dispose();
    expect(platform.calls.last, 'dispose');
    await camera.dispose();
    expect(platform.calls.where((call) => call == 'dispose'), hasLength(1));
  });

  test('no_back_camera_is_unavailable', () async {
    CameraPlatform.instance = _RecordingCameraPlatform([_front]);
    await expectLater(
      PluginCaptureCamera().initialize(),
      throwsA(isA<CameraUnavailableException>()),
    );
  });

  test('an_access_denied_code_is_a_revoked_permission', () async {
    for (final code in [
      'CameraAccessDenied',
      'CameraAccessDeniedWithoutPrompt',
      'CameraAccessRestricted',
    ]) {
      CameraPlatform.instance = _RecordingCameraPlatform(
        [_back],
        initializeError: PlatformException(code: code),
      );
      await expectLater(
        PluginCaptureCamera().initialize(),
        throwsA(isA<CameraPermissionRevokedException>()),
        reason: code,
      );
    }
  });

  test('another_camera_error_is_unavailable', () async {
    CameraPlatform.instance = _RecordingCameraPlatform(
      [_back],
      initializeError: PlatformException(code: 'cameraNotReadable'),
    );
    await expectLater(
      PluginCaptureCamera().initialize(),
      throwsA(isA<CameraUnavailableException>()),
    );
  });

  test('ios_frames_arrive_portrait', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final platform = _RecordingCameraPlatform([_back]);
    CameraPlatform.instance = platform;
    final camera = PluginCaptureCamera();
    await camera.initialize();
    // BGRA, already turned by the locked portrait-up capture orientation
    // (camera_avfoundation applies it to the stream's connection).
    expect(platform.formatGroup, ImageFormatGroup.bgra8888);
    expect(camera.frameRotationDegrees, 0);
  });
}
