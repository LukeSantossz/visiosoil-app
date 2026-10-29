import 'dart:developer' as developer;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:visiosoil_app/core/features/capture/guided_camera/live_frame.dart';

/// What the guided camera hands back to the capture screen (SPEC 0165).
sealed class GuidedCaptureResult {
  const GuidedCaptureResult();

  /// A photograph was taken.
  const factory GuidedCaptureResult.captured(XFile file) =
      GuidedCaptureCaptured;

  /// The user closed the camera, or a revoked permission closed it.
  const factory GuidedCaptureResult.cancelled() = GuidedCaptureCancelled;

  /// The camera could not be opened; the system camera is the fallback.
  const factory GuidedCaptureResult.unavailable() = GuidedCaptureUnavailable;
}

final class GuidedCaptureCaptured extends GuidedCaptureResult {
  const GuidedCaptureCaptured(this.file);

  final XFile file;
}

final class GuidedCaptureCancelled extends GuidedCaptureResult {
  const GuidedCaptureCancelled();
}

final class GuidedCaptureUnavailable extends GuidedCaptureResult {
  const GuidedCaptureUnavailable();
}

/// No camera could be opened: none faces back, or the platform failed.
class CameraUnavailableException implements Exception {
  const CameraUnavailableException(this.message);

  final String message;

  @override
  String toString() => 'CameraUnavailableException: $message';
}

/// The camera permission was refused, by its plugin [code].
class CameraPermissionRevokedException implements Exception {
  const CameraPermissionRevokedException(this.code);

  final String code;

  @override
  String toString() => 'CameraPermissionRevokedException: $code';
}

/// The camera the guided screen drives. A fake stands in for it in tests, so
/// no widget test needs the plugin.
abstract interface class CaptureCamera {
  /// Opens the camera. Throws [CameraUnavailableException] or
  /// [CameraPermissionRevokedException].
  Future<void> initialize();

  /// The preview's size, portrait. Valid after [initialize].
  Size get previewSize;

  /// The live preview. Valid after [initialize].
  Widget buildPreview();

  bool get canSwitchCamera;
  Future<void> switchCamera();

  /// The open camera's Camera2 id on Android, which its optics are read by
  /// (SPEC 0238); null when none is open.
  String? get cameraId;

  /// Takes a still at the camera's largest resolution.
  Future<XFile> takePicture();

  /// Releases the camera. Safe to call more than once, or after a failed
  /// [initialize].
  Future<void> dispose();

  /// The clockwise turn, in degrees, that makes a preview frame portrait.
  /// Valid after [initialize].
  int get frameRotationDegrees;

  /// Streams preview frames to [onFrame] until [stopFrames].
  Future<void> startFrames(void Function(CameraFrame frame) onFrame);

  Future<void> stopFrames();
}

typedef CaptureCameraFactory = CaptureCamera Function();

/// One preview frame's first plane: the luma on Android, BGRA on iOS
/// (SPEC 0166).
typedef CameraFrame = ({
  LivePixelFormat format,
  int width,
  int height,
  Uint8List bytes,
  int bytesPerRow,
});

/// [CaptureCamera] over the `camera` plugin.
class PluginCaptureCamera implements CaptureCamera {
  /// The plugin's codes for a camera permission refused.
  static const accessDeniedCodes = {
    'CameraAccessDenied',
    'CameraAccessDeniedWithoutPrompt',
    'CameraAccessRestricted',
  };

  CameraController? _controller;
  List<CameraDescription> _cameras = [];

  @override
  Future<void> initialize() async {
    try {
      _cameras = (await availableCameras())
          .where((camera) => camera.lensDirection == CameraLensDirection.back)
          .toList();
      if (_cameras.isEmpty) {
        throw const CameraUnavailableException('no back-facing camera');
      }
      final controller = CameraController(
        _cameras.first,
        ResolutionPreset.max,
        enableAudio: false,
        // The plane the live reader reads: the luma on Android, BGRA on iOS.
        imageFormatGroup: defaultTargetPlatform == TargetPlatform.iOS
            ? ImageFormatGroup.bgra8888
            : ImageFormatGroup.yuv420,
      );
      _controller = controller;
      await controller.initialize();
      // The protocol forbids the flash.
      await controller.setFlashMode(FlashMode.off);
      // A phone held flat over a sheet has no reliable orientation of its own.
      await controller.lockCaptureOrientation(DeviceOrientation.portraitUp);
    } on CameraException catch (e) {
      if (accessDeniedCodes.contains(e.code)) {
        throw CameraPermissionRevokedException(e.code);
      }
      throw CameraUnavailableException(e.toString());
    }
  }

  @override
  bool get canSwitchCamera => _cameras.length > 1;

  @override
  Future<void> switchCamera() async {
    if (!canSwitchCamera) return;
    final controller = _controller!;
    final index = _cameras.indexOf(controller.description);
    if (index == -1) {
      throw const CameraUnavailableException(
        'current camera is missing from available cameras',
      );
    }
    await controller.setDescription(_cameras[(index + 1) % _cameras.length]);
    await controller.setFlashMode(FlashMode.off);
    await controller.lockCaptureOrientation(DeviceOrientation.portraitUp);
  }

  /// `camera_android_camerax` names each camera by its Camera2 id.
  @override
  String? get cameraId => _controller?.description.name;

  @override
  Size get previewSize {
    final size = _controller!.value.previewSize!;
    return Size(size.shortestSide, size.longestSide);
  }

  @override
  Widget buildPreview() => CameraPreview(_controller!);

  @override
  Future<XFile> takePicture() => _controller!.takePicture();

  @override
  Future<void> dispose() async {
    final controller = _controller;
    _controller = null;
    await controller?.dispose();
  }

  /// Android streams frames in the sensor's orientation, so they turn by
  /// it. iOS applies the locked portrait-up capture orientation to the
  /// stream's connection too, so its frames arrive portrait already.
  @override
  int get frameRotationDegrees => defaultTargetPlatform == TargetPlatform.iOS
      ? 0
      : _controller!.description.sensorOrientation;

  bool _loggedUnreadable = false;

  @override
  Future<void> startFrames(void Function(CameraFrame frame) onFrame) =>
      _controller!.startImageStream((image) {
        final format = switch (image.format.group) {
          ImageFormatGroup.yuv420 => LivePixelFormat.yuv420,
          ImageFormatGroup.bgra8888 => LivePixelFormat.bgra8888,
          _ => null,
        };
        if (format == null) {
          if (!_loggedUnreadable) {
            _loggedUnreadable = true;
            developer.log(
              'Preview frames in ${image.format.group} are not read',
              name: 'PluginCaptureCamera',
            );
          }
          return;
        }
        final plane = image.planes.first;
        onFrame((
          format: format,
          width: image.width,
          height: image.height,
          bytes: plane.bytes,
          bytesPerRow: plane.bytesPerRow,
        ));
      });

  @override
  Future<void> stopFrames() async {
    final controller = _controller;
    if (controller != null && controller.value.isStreamingImages) {
      await controller.stopImageStream();
    }
  }
}
