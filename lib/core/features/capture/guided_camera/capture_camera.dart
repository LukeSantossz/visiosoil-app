import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

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

  /// Takes a still at the camera's largest resolution.
  Future<XFile> takePicture();

  /// Releases the camera. Safe to call more than once, or after a failed
  /// [initialize].
  Future<void> dispose();
}

typedef CaptureCameraFactory = CaptureCamera Function();

/// [CaptureCamera] over the `camera` plugin.
class PluginCaptureCamera implements CaptureCamera {
  /// The plugin's codes for a camera permission refused.
  static const accessDeniedCodes = {
    'CameraAccessDenied',
    'CameraAccessDeniedWithoutPrompt',
    'CameraAccessRestricted',
  };

  CameraController? _controller;

  @override
  Future<void> initialize() async {
    try {
      final cameras = await availableCameras();
      final back = cameras
          .where((camera) => camera.lensDirection == CameraLensDirection.back);
      if (back.isEmpty) {
        throw const CameraUnavailableException('no back-facing camera');
      }
      final controller = CameraController(
        back.first,
        ResolutionPreset.max,
        enableAudio: false,
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
}
