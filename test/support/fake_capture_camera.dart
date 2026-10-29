import 'dart:typed_data';
import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/widgets.dart';
import 'package:visiosoil_app/core/features/capture/guided_camera/ambient_light_source.dart';
import 'package:visiosoil_app/core/features/capture/guided_camera/camera_optics.dart';
import 'package:visiosoil_app/core/features/capture/guided_camera/live_reading.dart';
import 'package:visiosoil_app/core/features/capture/guided_camera/live_sheet_reader.dart';
import 'package:visiosoil_app/core/services/descriptors/patch_grid.dart';
import 'package:visiosoil_app/core/services/still_size_store.dart';
import 'package:visiosoil_app/core/features/capture/guided_camera/capture_camera.dart';
import 'package:visiosoil_app/core/features/capture/guided_camera/tilt_source.dart';

/// Makes [FakeCaptureCamera]s and remembers them, in creation order, with one
/// shared [log] of what each was asked to do (SPEC 0165).
class FakeCaptureCameras {
  /// Thrown by every camera's initialize, when set.
  Object? initializeError;
  bool canSwitchCamera = true;

  /// Thrown by takePicture, when set.
  Object? takePictureError;

  /// When set, initialize waits on it, so a test can hold it pending.
  Completer<void>? initializeGate;

  /// When set, dispose waits on it before it completes.
  Completer<void>? disposeGate;

  /// Thrown by dispose, when set.
  Object? disposeError;

  /// Thrown by stopFrames, when set.
  Object? stopFramesError;

  /// When set, startFrames waits on it before the stream runs.
  Completer<void>? startFramesGate;

  /// When set, takePicture returns a file at this path instead of a made-up
  /// one, so a test can check what happens to it.
  String? picturePath;

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
  @override
  bool get canSwitchCamera => _owner.canSwitchCamera;
  @override
  Future<void> switchCamera() async {
    _owner.log.add('switchCamera:$index');
    _lens++;
  }

  /// Which of the device's back cameras is open, bumped by every switch.
  int _lens = 0;

  @override
  String? get cameraId => '$_lens';

  int takePictureCalls = 0;
  bool disposed = false;

  /// When set, takePicture waits on it.
  Completer<void>? pictureGate;

  void Function(CameraFrame frame)? _onFrame;

  /// Whether frames are streaming.
  bool get streaming => _onFrame != null;

  /// Hands [frame] to the screen as the plugin's stream would; ignored when
  /// not streaming.
  void emitFrame(CameraFrame frame) => _onFrame?.call(frame);

  @override
  int get frameRotationDegrees => 0;

  @override
  Future<void> startFrames(void Function(CameraFrame frame) onFrame) async {
    _owner.log.add('startFrames:$index');
    final gate = _owner.startFramesGate;
    if (gate != null) await gate.future;
    _onFrame = onFrame;
  }

  @override
  Future<void> stopFrames() async {
    final error = _owner.stopFramesError;
    if (error != null) throw error;
    if (_onFrame == null) return;
    _onFrame = null;
    _owner.log.add('stopFrames:$index');
  }

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
  Widget buildPreview() =>
      const ColoredBox(key: ValueKey('fake-preview'), color: Color(0xFF223322));

  @override
  Future<XFile> takePicture() async {
    takePictureCalls++;
    _owner.log.add('takePicture:$index');
    final gate = pictureGate;
    if (gate != null) await gate.future;
    final error = _owner.takePictureError;
    if (error != null) throw error;
    final path = _owner.picturePath;
    // A made-up photograph lives in memory, so reading it needs no file I/O
    // inside the fake clock; a test that needs a real file sets picturePath.
    return path != null
        ? XFile(path)
        : XFile.fromData(Uint8List(0), path: '/tmp/guided_$index.jpg');
  }

  /// Logs `dispose:<index>` once the release has completed, so a test can
  /// check what waited on it.
  @override
  Future<void> dispose() async {
    if (disposed) return;
    disposed = true;
    final gate = _owner.disposeGate;
    if (gate != null) await gate.future;
    final error = _owner.disposeError;
    if (error != null) throw error;
    _owner.log.add('dispose:$index');
  }
}

/// A [TiltSource] a test drives sample by sample.
class FakeTiltSource implements TiltSource {
  final controller = StreamController<AccelerationSample>.broadcast();

  @override
  Stream<AccelerationSample> get samples => controller.stream;
}

/// A [CameraOpticsSource] that answers [optics] for every camera and
/// remembers which ones it was asked about (SPEC 0238).
class FakeCameraOpticsSource implements CameraOpticsSource {
  CameraOptics? optics;
  final asked = <String>[];

  @override
  Future<CameraOptics?> opticsOf(String cameraId) async {
    asked.add(cameraId);
    return optics;
  }
}

/// An [AmbientLightSource] a test drives reading by reading, counting how
/// often the screen started listening (SPEC 0238).
class FakeAmbientLightSource implements AmbientLightSource {
  int listens = 0;
  late final controller = StreamController<double>.broadcast(
    onListen: () => listens++,
  );

  bool get listening => controller.hasListener;

  @override
  Stream<double> get lux => controller.stream;
}

/// A [LiveSheetReader] a test answers by hand (SPEC 0166).
class FakeLiveSheetReader implements LiveSheetReader {
  final requests = <int>[];
  final _replies = StreamController<LiveReply>();
  bool killed = false;

  @override
  void read(RgbFrame frame, int generation) => requests.add(generation);

  @override
  Stream<LiveReply> get replies => _replies.stream;

  @override
  void kill() {
    if (killed) return;
    killed = true;
    unawaited(_replies.close());
  }

  /// Answers the last request, or [generation] when given.
  void reply(LiveReading reading, {int? generation}) {
    if (killed) return;
    _replies.add((generation: generation ?? requests.last, reading: reading));
  }

  /// The reader fails, as an isolate that threw or exited would.
  void fail() {
    if (!killed) _replies.addError(StateError('the reader failed'));
  }
}

/// A [StillSizeStore] held in memory.
class FakeStillSizeStore implements StillSizeStore {
  FakeStillSizeStore([this.size]);

  Size? size;

  @override
  Future<Size?> read() async => size;

  @override
  Future<void> write(Size size) async => this.size = size;
}
