import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:camera/camera.dart' show XFile;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:visiosoil_app/core/features/capture/guided_camera/camera_release_queue.dart';
import 'package:visiosoil_app/core/features/capture/guided_camera/capture_camera.dart';
import 'package:visiosoil_app/core/features/capture/guided_camera/capture_guidance.dart';
import 'package:visiosoil_app/core/features/capture/guided_camera/capture_guide_overlay.dart';
import 'package:visiosoil_app/core/features/capture/guided_camera/live_frame.dart';
import 'package:visiosoil_app/core/features/capture/guided_camera/live_reading.dart';
import 'package:visiosoil_app/core/features/capture/guided_camera/live_sheet_reader.dart';
import 'package:visiosoil_app/core/features/capture/guided_camera/still_scale.dart';
import 'package:visiosoil_app/core/features/capture/guided_camera/tilt.dart';
import 'package:visiosoil_app/core/features/capture/guided_camera/tilt_source.dart';
import 'package:visiosoil_app/core/services/descriptors/patch_grid.dart';
import 'package:visiosoil_app/core/services/error_report_store.dart';
import 'package:visiosoil_app/core/services/still_size_store.dart';
import 'package:visiosoil_app/core/theme/app_haptics.dart';
import 'package:visiosoil_app/core/theme/app_palette.dart';
import 'package:visiosoil_app/core/widgets/visio_icon_button.dart';
import 'package:visiosoil_app/providers/error_report_provider.dart';
import 'package:visiosoil_app/providers/guided_camera_provider.dart';

/// The in-app camera: the preview, the sheet outline, the soil target and the
/// level, a banner and an always-enabled shutter (SPEC 0165, ADR 0028). Pops
/// a [GuidedCaptureResult]; a back gesture pops null, read as cancelled.
class GuidedCameraScreen extends ConsumerStatefulWidget {
  const GuidedCameraScreen({super.key});

  static const double bannerHeight = 72;
  static const double footerHeight = 140;

  @override
  ConsumerState<GuidedCameraScreen> createState() =>
      _GuidedCameraScreenState();
}

class _GuidedCameraScreenState extends ConsumerState<GuidedCameraScreen>
    with WidgetsBindingObserver {
  CaptureCamera? _camera;

  /// Bumped by every release, so an initialisation that completes after one
  /// knows it is stale and disposes its own camera.
  int _generation = 0;
  bool _initializing = false;

  /// The app-wide queue of releases; the next camera opens only after it.
  late final CameraReleaseQueue _releases =
      ref.read(cameraReleaseQueueProvider);

  /// The initialisation in flight, if any; dispose waits for it.
  Future<void>? _opening;

  /// Whether the screen wants a live camera: false between a release and the
  /// next resume, and after dispose.
  bool _wantCamera = true;
  bool _everInitialized = false;
  bool _shooting = false;
  bool _closed = false;

  final TiltSmoother _smoother = TiltSmoother();
  double? _tilt;
  StreamSubscription<AccelerationSample>? _tiltSubscription;

  /// Read once, so a shot or a reader failing after close still reports.
  late final ErrorReportStore _errors;

  // The live reading (SPEC 0166).
  static const _readTimeout = Duration(seconds: 2);
  LiveSheetReader? _reader;
  StreamSubscription<LiveReply>? _replies;
  Timer? _readTimer;
  bool _frameInFlight = false;

  /// Bumped by every request and every stop: a reply carrying another
  /// generation answers a frame nobody waits for any more.
  int _readGeneration = 0;

  /// Set when the reader failed: no live reading for the rest of the visit.
  bool _liveFailed = false;

  /// Bumped by every stop: a startup that resumes after one was cancelled.
  int _liveToken = 0;

  /// The preview stream's start in flight, if any: every stop waits for it,
  /// so no stream is left running behind a stop that came while it started.
  Future<void>? _startingFrames;
  LiveContract? _liveContract;
  Size? _readSize;
  Size? _stillSize;
  ReadingDebouncer _debouncer = ReadingDebouncer();
  LiveReading? _shownReading;
  bool _shownTooCoarse = false;
  bool _wasReady = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _errors = ref.read(errorReportStoreProvider);
    _tiltSubscription = ref.read(tiltSourceProvider).samples.listen(
      (sample) {
        final tilt = _smoother.add(sample.x, sample.y, sample.z);
        if (mounted && tilt != _tilt) {
          setState(() => _tilt = tilt);
          _tickIfGreen();
        }
      },
      onError: (Object error, StackTrace stack) {
        // No accelerometer: the level hides and nothing is blocked.
        developer.log(
          'Tilt unavailable: $error',
          name: 'GuidedCameraScreen',
          error: error,
          stackTrace: stack,
        );
        unawaited(_tiltSubscription?.cancel());
        if (mounted) setState(() => _tilt = null);
      },
    );
    unawaited(_start());
  }

  Future<void> _start() async {
    // A camera screen closed just before this one may still be releasing its
    // camera and resetting the orientation; both must land first.
    await _releases.idle;
    if (!mounted) return;
    // Set before the camera opens, so its first frames are already portrait.
    await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    if (!mounted) return;
    await _openCamera();
  }

  Future<void> _openCamera() {
    if (_initializing || _camera != null || !_wantCamera || _closed) {
      return Future.value();
    }
    _initializing = true;
    final opening = _initializeCamera();
    _opening = opening;
    return opening;
  }

  Future<void> _initializeCamera() async {
    final generation = _generation;
    final cameras = ref.read(captureCameraFactoryProvider);
    // A camera being released must be gone before the next one opens: two
    // native sessions on one sensor conflict.
    await _releases.idle;
    if (generation != _generation || !mounted) {
      _initializing = false;
      _reopenIfWanted();
      return;
    }
    final camera = cameras();
    try {
      await camera.initialize();
    } on Exception catch (e, stack) {
      _initializing = false;
      await _releaseStale(camera);
      if (generation != _generation || !mounted) {
        _reopenIfWanted();
        return;
      }
      developer.log(
        'Guided camera could not open: $e',
        name: 'GuidedCameraScreen',
        error: e,
        stackTrace: stack,
      );
      // A permission revoked while the app was away closes the screen; the
      // capture screen's own permission check explains it on the next tap.
      _pop(e is CameraPermissionRevokedException && _everInitialized
          ? const GuidedCaptureResult.cancelled()
          : const GuidedCaptureResult.unavailable());
      return;
    }
    _initializing = false;
    if (generation != _generation || !mounted) {
      await _releaseStale(camera);
      _reopenIfWanted();
      return;
    }
    setState(() {
      _camera = camera;
      _everInitialized = true;
    });
    unawaited(_startLive(camera));
  }

  /// A stale initialisation finished while the screen wants a camera again:
  /// the resume that arrived meanwhile started none, so start one now.
  void _reopenIfWanted() {
    if (mounted && _wantCamera) unawaited(_openCamera());
  }

  /// Releases [camera], logging a failure: a camera that fails to close must
  /// not stop the screen from reopening one or restoring the orientation.
  Future<void> _release(CaptureCamera? camera) async {
    if (camera == null) return;
    try {
      await camera.dispose();
    } on Exception catch (e, stack) {
      developer.log(
        'Releasing the guided camera failed: $e',
        name: 'GuidedCameraScreen',
        error: e,
        stackTrace: stack,
      );
    }
  }

  /// Puts [camera]'s release on the app-wide queue, so the next camera,
  /// which waits on it, never opens while any earlier one is still closing.
  /// Its frames stop first.
  Future<void> _queueRelease(CaptureCamera? camera) => _releases.add(() async {
        if (camera == null) return;
        await _stopFrames(camera);
        await _release(camera);
      });

  /// Stops [camera]'s preview frames. A failure is recorded: a stream left
  /// running wastes the camera's work and can make the next shot fail, which
  /// that shot's own error path then reports to the user.
  Future<void> _stopFrames(CaptureCamera camera) async {
    final starting = _startingFrames;
    try {
      // A stream still starting is stopped once it runs, not before.
      if (starting != null) await starting;
      await camera.stopFrames();
    } on Exception catch (e, stack) {
      unawaited(_errors.record(source: 'guided_camera', error: e, stack: stack));
    }
  }

  /// Starts reading [camera]'s preview live, unless the reader failed this
  /// visit or the contract cannot be loaded (SPEC 0166).
  Future<void> _startLive(CaptureCamera camera) async {
    if (_liveFailed || _reader != null || _shooting) return;
    final token = _liveToken;
    final loadContract = ref.read(liveContractLoaderProvider);
    final spawn = ref.read(liveSheetReaderFactoryProvider);
    final stillSizes = ref.read(stillSizeStoreProvider);
    try {
      final contract = _liveContract ??= await loadContract();
      if (contract == null || !_canGoLive(camera, token)) return;
      _stillSize ??= await _readStillSize(stillSizes);
      if (!_canGoLive(camera, token)) return;
      final reader = await spawn(contract);
      if (!_canGoLive(camera, token) || _reader != null) {
        reader.kill();
        return;
      }
      _reader = reader;
      _replies = reader.replies.listen(_onReply, onError: _onReaderFailed);
      final starting = camera.startFrames(_onFrame);
      _startingFrames = starting;
      try {
        await starting;
      } finally {
        if (identical(_startingFrames, starting)) _startingFrames = null;
      }
    } on Object catch (e, stack) {
      // A reader that cannot start is a reader that failed: recorded, and the
      // banner stays the tilt's for the visit.
      if (token == _liveToken) _onReaderFailed(e, stack);
    }
  }

  /// Whether a startup begun under [token] may still go live on [camera]: no
  /// stop, shot, failure or close came meanwhile.
  bool _canGoLive(CaptureCamera camera, int token) =>
      token == _liveToken &&
      mounted &&
      !_closed &&
      !_liveFailed &&
      !_shooting &&
      identical(_camera, camera);

  Future<Size?> _readStillSize(StillSizeStore store) async {
    try {
      return await store.read();
    } on Exception catch (e, stack) {
      developer.log(
        'Reading the still size failed: $e',
        name: 'GuidedCameraScreen',
        error: e,
        stackTrace: stack,
      );
      return null;
    }
  }

  /// Hands one frame to the reader, unless one is already being read: frames
  /// that arrive meanwhile are dropped, never queued.
  void _onFrame(CameraFrame frame) {
    final reader = _reader;
    final camera = _camera;
    if (reader == null || camera == null || _frameInFlight) return;
    _frameInFlight = true;
    final RgbFrame read;
    try {
      read = reduceForReading(rotateClockwise(
        greyFrameFromPlane(
          bytes: frame.bytes,
          width: frame.width,
          height: frame.height,
          bytesPerRow: frame.bytesPerRow,
          format: frame.format,
        ),
        camera.frameRotationDegrees,
      ));
    } on ArgumentError catch (e, stack) {
      _onReaderFailed(e, stack);
      return;
    }
    _readSize = Size(read.width.toDouble(), read.height.toDouble());
    final generation = ++_readGeneration;
    _readTimer = Timer(_readTimeout, () {
      _onReaderFailed(
        TimeoutException('the live sheet reader did not answer', _readTimeout),
        StackTrace.current,
      );
    });
    reader.read(read, generation);
  }

  void _onReply(LiveReply reply) {
    if (reply.generation != _readGeneration) return;
    _readTimer?.cancel();
    _frameInFlight = false;
    final reading = reply.reading;
    final tooCoarse = _isTooCoarse(reading);
    // The reader's own row: the tilt rows follow the sensor, not the reader.
    final row = guidanceFor(tilt: 0, reading: reading, tooCoarse: tooCoarse).row;
    if (_debouncer.accept(row) != row || !mounted) return;
    setState(() {
      _shownReading = reading;
      _shownTooCoarse = tooCoarse;
    });
    _tickIfGreen();
  }

  bool _isTooCoarse(LiveReading reading) {
    final still = _stillSize;
    final read = _readSize;
    final contract = _liveContract;
    if (reading is! LiveSheetFound ||
        still == null ||
        read == null ||
        contract == null) {
      return false;
    }
    return stillTooCoarse(
      sheetLongSidePx: reading.sheetLongSidePx,
      frame: read,
      still: still,
      canonicalMmPerPx: contract.canonicalMmPerPx,
    );
  }

  /// A selection tick on entering green, once per entry.
  void _tickIfGreen() {
    final ready = _shownReading != null &&
        guidanceFor(
              tilt: _tilt,
              reading: _shownReading,
              tooCoarse: _shownTooCoarse,
            ).row ==
            GuidanceRow.ready;
    if (ready && !_wasReady) unawaited(AppHaptics.selection());
    _wasReady = ready;
  }

  /// The reader failed: it threw, exited, or held a reading too long. No live
  /// reading for the rest of the visit; the banner is the tilt's again.
  void _onReaderFailed(Object error, StackTrace stack) {
    if (_liveFailed) return;
    _liveFailed = true;
    unawaited(_errors.record(
      source: 'live_sheet_reader',
      error: error,
      stack: stack,
    ));
    final camera = _camera;
    _stopLive();
    if (camera != null) unawaited(_stopFrames(camera));
    if (mounted) setState(() {});
  }

  /// Stops the live reading at once: no frame is accepted, the reader is
  /// killed, and any reply still on its way is stale. The frames stop where
  /// the caller awaits them.
  void _stopLive() {
    _liveToken++;
    _readGeneration++;
    _readTimer?.cancel();
    _readTimer = null;
    _frameInFlight = false;
    unawaited(_replies?.cancel());
    _replies = null;
    _reader?.kill();
    _reader = null;
    _debouncer = ReadingDebouncer();
    _shownReading = null;
    _shownTooCoarse = false;
    _wasReady = false;
  }

  /// Learns this device's still size from a photograph just taken.
  Future<void> _learnStillSize(StillSizeStore store, XFile file) async {
    try {
      final size = portraitSizeOfJpeg(await file.readAsBytes());
      if (size != null) await store.write(size);
    } on Exception catch (e, stack) {
      developer.log(
        'Learning the still size failed: $e',
        name: 'GuidedCameraScreen',
        error: e,
        stackTrace: stack,
      );
    }
  }

  /// Releases a camera whose initialisation completed failed or stale. Once
  /// the screen is disposed, its dispose step already holds the queue waiting
  /// for this initialisation, so the release runs directly: queueing it behind
  /// that step would wait on itself.
  Future<void> _releaseStale(CaptureCamera camera) =>
      mounted ? _queueRelease(camera) : _release(camera);

  Future<void> _resetOrientation() async {
    try {
      // Back to the app's default of every orientation.
      await SystemChrome.setPreferredOrientations(const []);
    } on PlatformException catch (e, stack) {
      developer.log(
        'Restoring the orientation failed: $e',
        name: 'GuidedCameraScreen',
        error: e,
        stackTrace: stack,
      );
    }
  }

  /// Releases the live camera. [rebuild] is false from dispose, where the
  /// screen cannot rebuild.
  void _releaseCamera({bool rebuild = true}) {
    _stopLive();
    _generation++;
    final camera = _camera;
    _camera = null;
    if (rebuild && mounted) setState(() {});
    unawaited(_queueRelease(camera));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The plugin no longer manages its lifecycle; the app does (SPEC 0165).
    switch (state) {
      case AppLifecycleState.resumed:
        _wantCamera = true;
        unawaited(_openCamera());
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        _wantCamera = false;
        _releaseCamera();
    }
  }

  Future<void> _shoot() async {
    final camera = _camera;
    if (_shooting || camera == null) return;
    _shooting = true;
    // Read now: the screen may be closed by the time the shot returns.
    final stillSizes = ref.read(stillSizeStoreProvider);
    // The reader stops before the shot, and nothing waits on its last frame.
    _stopLive();
    await _stopFrames(camera);
    try {
      final file = await camera.takePicture();
      // Learned before the photograph is handed over: whoever owns the file
      // next may move or delete it.
      await _learnStillSize(stillSizes, file);
      if (_closed || !mounted) {
        // Nobody will receive it: the screen closed while it was taken.
        await _discard(file);
        return;
      }
      _pop(GuidedCaptureResult.captured(file));
    } on Exception catch (e, stack) {
      _shooting = false;
      unawaited(_errors.record(source: 'guided_camera', error: e, stack: stack));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Não foi possível tirar a foto. Tente de novo.'),
      ));
      if (identical(_camera, camera)) unawaited(_startLive(camera));
    }
  }

  Future<void> _discard(XFile file) async {
    try {
      await File(file.path).delete();
    } on FileSystemException catch (e, stack) {
      developer.log(
        'Could not delete a photograph taken after the camera closed: $e',
        name: 'GuidedCameraScreen',
        error: e,
        stackTrace: stack,
      );
    }
  }

  void _pop(GuidedCaptureResult result) {
    if (_closed || !mounted) return;
    _closed = true;
    Navigator.of(context).pop(result);
  }

  @override
  void dispose() {
    _closed = true;
    _wantCamera = false;
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_tiltSubscription?.cancel());
    _releaseCamera(rebuild: false);
    final opening = _opening;
    // Queued after the live camera's release. An initialisation still in
    // flight releases its own camera when it completes stale; the reset waits
    // for that too, and a camera screen opened meanwhile waits for the reset.
    unawaited(_releases.add(() async {
      await opening;
      await _resetOrientation();
    }));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final guidance = guidanceFor(
      tilt: _tilt,
      reading: _shownReading,
      tooCoarse: _shownTooCoarse,
    ).guidance;
    final camera = _camera;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (camera != null)
            ClipRect(
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox.fromSize(
                  size: camera.previewSize,
                  child: camera.buildPreview(),
                ),
              ),
            ),
          SafeArea(
            child: CaptureGuideOverlay(
              topInset: GuidedCameraScreen.bannerHeight,
              bottomInset: GuidedCameraScreen.footerHeight,
              tilt: _tilt,
              direction: _smoother.direction,
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                _GuidanceBanner(guidance: guidance),
                const Spacer(),
                SizedBox(
                  height: GuidedCameraScreen.footerHeight,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      VisioIconButton(
                        key: const ValueKey('guided-camera-close'),
                        label: 'Fechar câmera',
                        icon: Icons.close,
                        iconSize: 32,
                        overPhoto: true,
                        onPressed: () =>
                            _pop(const GuidedCaptureResult.cancelled()),
                      ),
                      _Shutter(onTap: _shoot),
                      // Balances the close button, so the shutter is centred.
                      const SizedBox(width: 48),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GuidanceBanner extends StatelessWidget {
  const _GuidanceBanner({required this.guidance});

  final Guidance guidance;

  @override
  Widget build(BuildContext context) {
    final colours = guidanceColors(guidance.tone, context.palette);
    return Container(
      key: const ValueKey('guided-camera-banner'),
      height: GuidedCameraScreen.bannerHeight,
      color: colours.background,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Icon(guidance.icon, color: colours.foreground),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              guidance.message,
              style: TextStyle(
                color: colours.foreground,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Shutter extends StatelessWidget {
  const _Shutter({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Tirar foto',
      child: GestureDetector(
        key: const ValueKey('guided-camera-shutter'),
        onTap: onTap,
        child: Container(
          width: 76,
          height: 76,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
            border: Border.all(color: Colors.white70, width: 4),
          ),
        ),
      ),
    );
  }
}
