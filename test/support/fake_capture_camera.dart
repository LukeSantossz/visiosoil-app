import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/widgets.dart';
import 'package:visiosoil_app/core/features/capture/guided_camera/capture_camera.dart';
import 'package:visiosoil_app/core/features/capture/guided_camera/tilt_source.dart';

/// Makes [FakeCaptureCamera]s and remembers them, in creation order, with one
/// shared [log] of what each was asked to do (SPEC 0165).
class FakeCaptureCameras {
  /// Thrown by every camera's initialize, when set.
  Object? initializeError;

  /// Thrown by takePicture, when set.
  Object? takePictureError;

  /// When set, initialize waits on it, so a test can hold it pending.
  Completer<void>? initializeGate;

  final cameras = <FakeCaptureCamera>[];
  final log = <String>[];

  FakeCaptureCamera create() {
    final camera = FakeCaptureCamera(this, cameras.length);
    cameras.add(camera);
    return camera;
  }
}

class FakeCaptureCamera implements CaptureCamera {
  FakeCaptureCamera(this._owner, this.index);

  final FakeCaptureCameras _owner;
  final int index;
  int takePictureCalls = 0;
  bool disposed = false;

  /// When set, takePicture waits on it.
  Completer<void>? pictureGate;

  @override
  Future<void> initialize() async {
    _owner.log.add('initialize:$index');
    final gate = _owner.initializeGate;
    if (gate != null) await gate.future;
    final error = _owner.initializeError;
    if (error != null) throw error;
  }

  @override
  Size get previewSize => const Size(720, 1280);

  @override
  Widget buildPreview() => const ColoredBox(
        key: ValueKey('fake-preview'),
        color: Color(0xFF223322),
      );

  @override
  Future<XFile> takePicture() async {
    takePictureCalls++;
    _owner.log.add('takePicture:$index');
    final gate = pictureGate;
    if (gate != null) await gate.future;
    final error = _owner.takePictureError;
    if (error != null) throw error;
    return XFile('/tmp/guided_$index.jpg');
  }

  @override
  Future<void> dispose() async {
    if (disposed) return;
    disposed = true;
    _owner.log.add('dispose:$index');
  }
}

/// A [TiltSource] a test drives sample by sample.
class FakeTiltSource implements TiltSource {
  final controller = StreamController<AccelerationSample>.broadcast();

  @override
  Stream<AccelerationSample> get samples => controller.stream;
}
