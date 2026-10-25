import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:math' as math;

import 'package:camera/camera.dart' show XFile;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:visiosoil_app/core/features/capture/capture_guide_screen.dart';
import 'package:visiosoil_app/core/features/capture/guided_camera/live_quality.dart';
import 'package:visiosoil_app/core/features/capture/guided_camera/quality_chip.dart';
import 'package:visiosoil_app/core/features/capture/guided_camera/capture_alert.dart';
import 'package:visiosoil_app/core/features/capture/guided_camera/auto_capture_trigger.dart';
import 'package:visiosoil_app/core/features/capture/guided_camera/camera_release_queue.dart';
import 'package:visiosoil_app/core/features/capture/guided_camera/capture_camera.dart';
import 'package:visiosoil_app/core/features/capture/guided_camera/capture_guidance.dart';
import 'package:visiosoil_app/core/features/capture/guided_camera/capture_guide_overlay.dart';
import 'package:visiosoil_app/core/features/capture/guided_camera/guide_alignment.dart';
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
import 'package:visiosoil_app/core/theme/app_density.dart';
import 'package:visiosoil_app/core/theme/app_spacing.dart';
import 'package:visiosoil_app/core/theme/app_motion.dart';
import 'package:visiosoil_app/core/theme/app_palette.dart';
import 'package:visiosoil_app/core/widgets/visio_icon_button.dart';
import 'package:visiosoil_app/providers/error_report_provider.dart';
import 'package:visiosoil_app/providers/guided_camera_provider.dart';

/// The in-app camera: the preview, the sheet outline, the soil target and the
/// level, live quality chips and guarded shutter feedback (SPEC 0189). Pops
/// a [GuidedCaptureResult]; a back gesture pops null, read as cancelled.
class GuidedCameraScreen extends ConsumerStatefulWidget {
  const GuidedCameraScreen({super.key});

  static const double bannerHeight = 72;
  static const double footerHeight = 140;

  @override
  ConsumerState<GuidedCameraScreen> createState() => _GuidedCameraScreenState();
}

class _GuidedCameraScreenState extends ConsumerState<GuidedCameraScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  LiveQuality? _quality;
  LiveQuality? _shownQuality;
  Map<String, String>? _failures;
  Set<String> _failedChips = {};
  Timer? _alertTimer;
  Timer? _flashTimer;
  late final AnimationController _shake = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
  );
  CaptureCamera? _camera;

  /// Bumped by every release, so an initialisation that completes after one
  /// knows it is stale and disposes its own camera.
  int _generation = 0;
  bool _initializing = false;

  /// The app-wide queue of releases; the next camera opens only after it.
  late final CameraReleaseQueue _releases = ref.read(
    cameraReleaseQueueProvider,
  );

  /// The initialisation in flight, if any; dispose waits for it.
  Future<void>? _opening;

  /// Whether the screen wants a live camera: false between a release and the
  /// next resume, and after dispose.
  bool _wantCamera = true;
  bool _everInitialized = false;
  bool _shooting = false;
  bool _controlsBusy = false;
  bool _showingGuide = false;
  bool _closed = false;

  /// Completes once the last shot or control operation is done: a release
  /// waits for it so the controller is never disposed while in use.
  Future<void> _shotInFlight = Future.value();

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

  /// Where the guides stand against the shown reading's corners, or null when
  /// they cannot be placed on the screen (SPEC 0169).
  SheetAlignment? _shownAlignment;
  bool _shownTooCoarse = false;
  bool _wasReady = false;

  // The automatic capture (SPEC 0167).
  final AutoCaptureTrigger _trigger = AutoCaptureTrigger();
  late final DateTime Function() _clock;
  bool _flashing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _errors = ref.read(errorReportStoreProvider);
    _clock = ref.read(autoCaptureClockProvider);
    _tiltSubscription = ref
        .read(tiltSourceProvider)
        .samples
        .listen(
          (sample) {
            final tilt = _smoother.add(sample.x, sample.y, sample.z);
            if (!mounted) return;
            if (tilt != _tilt) {
              setState(() => _tilt = tilt);
              _tickIfGreen();
            }
            // Every sample is an event: a still phone repeats the same tilt, and
            // that sample may be the first past the window's second.
            _feedTrigger(isReading: false);
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
            if (mounted) {
              setState(() {
                _tilt = null;
                _trigger.close();
              });
            }
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
      _pop(
        e is CameraPermissionRevokedException && _everInitialized
            ? const GuidedCaptureResult.cancelled()
            : const GuidedCaptureResult.unavailable(),
      );
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
  /// A shot still using it finishes first, then its frames stop.
  Future<void> _queueRelease(CaptureCamera? camera) => _releases.add(() async {
    if (camera == null) return;
    await _shotInFlight;
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
      unawaited(
        _errors.record(source: 'guided_camera', error: e, stack: stack),
      );
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
      read = reduceForReading(
        rotateClockwise(
          greyFrameFromPlane(
            bytes: frame.bytes,
            width: frame.width,
            height: frame.height,
            bytesPerRow: frame.bytesPerRow,
            format: frame.format,
          ),
          camera.frameRotationDegrees,
        ),
      );
    } on ArgumentError catch (e, stack) {
      _onReaderFailed(e, stack);
      return;
    }
    final quality = LiveQuality.measure(read);
    setState(() {
      // Match the reading debounce without delaying the raw capture gate.
      if (quality?.lightOk == _quality?.lightOk &&
          quality?.focusOk == _quality?.focusOk &&
          quality?.tooBright == _quality?.tooBright) {
        _shownQuality = quality;
      }
      _quality = quality;
    });
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
    if (!mounted) return;
    final alignment = _alignmentFor(reading);
    // The reader's own row: the tilt rows follow the sensor, not the reader.
    final row = guidanceFor(
      tilt: 0,
      reading: reading,
      tooCoarse: tooCoarse,
      alignment: alignment,
    ).row;
    if (_debouncer.accept(row) == row) {
      setState(() {
        _shownReading = reading;
        _shownTooCoarse = tooCoarse;
        _shownAlignment = alignment;
      });
      _tickIfGreen();
    }
    // Only a reading green in its own right counts toward the window's two;
    // one the debounce has not let through yet is an event that keeps the
    // window as the banner shows it (SPEC 0167, amended).
    _feedTrigger(isReading: row == GuidanceRow.ready, reading: reading);
  }

  /// Hands one event to the automatic capture: the banner's row as shown,
  /// this reading's disc, and the smoothed tilt, stamped now (SPEC 0167).
  /// [isReading] is false for a tilt sample and for a reading that is not
  /// green itself. With no live reading shown, the trigger is disarmed.
  void _feedTrigger({required bool isReading, LiveReading? reading}) {
    if (_controlsBusy || _shooting || _closed || _camera == null || !mounted) {
      return;
    }
    final shown = _shownReading;
    if (shown == null ||
        _reader == null ||
        (_quality != null && (!_quality!.lightOk || !_quality!.focusOk))) {
      if (_trigger.windowOpenedAt != null) setState(_trigger.close);
      return;
    }
    final row = guidanceFor(
      tilt: _tilt,
      reading: shown,
      tooCoarse: _shownTooCoarse,
      alignment: _shownAlignment,
    ).row;
    final openedBefore = _trigger.windowOpenedAt;
    final now = _clock();
    final fire = isReading
        ? _trigger.onReading(
            row: row,
            discDiameterMm: reading is LiveSheetFound
                ? reading.discDiameterMm
                : null,
            tilt: _tilt,
            at: now,
          )
        : _trigger.onTilt(row: row, tilt: _tilt, at: now);
    if (fire) {
      unawaited(_shoot(automatic: true));
      return;
    }
    if (_trigger.windowOpenedAt != openedBefore) setState(() {});
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

  /// Where the guides stand against [reading]'s corners on this screen, or
  /// null when they cannot be placed on it: no corners, no frame read yet,
  /// or a frame whose aspect is not the preview's (SPEC 0169).
  SheetAlignment? _alignmentFor(LiveReading reading) {
    final read = _readSize;
    final camera = _camera;
    if (reading is! LiveSheetFound || read == null || camera == null) {
      return null;
    }
    final screen = MediaQuery.sizeOf(context);
    final padding = MediaQuery.paddingOf(context);
    final mapped = mapCornersToOverlay(
      corners: reading.corners,
      readSize: read,
      previewSize: camera.previewSize,
      screenSize: screen,
      safePadding: padding,
    );
    if (mapped == null) return null;
    final preview = previewRectOnOverlay(
      previewSize: camera.previewSize,
      screenSize: screen,
      safePadding: padding,
    );
    return alignSheet(
      corners: assignCorners(mapped),
      // The overlay is laid out inside the safe area.
      layout: CaptureGuideLayout.compute(
        padding.deflateSize(screen),
        topInset: GuidedCameraScreen.bannerHeight,
        bottomInset: GuidedCameraScreen.footerHeight,
        preview: preview,
      ),
      // The preview is drawn whole, so leaving it is leaving the frame.
      screen: preview,
    );
  }

  /// A selection tick on entering green, once per entry.
  void _tickIfGreen() {
    final ready =
        _shownReading != null &&
        guidanceFor(
              tilt: _tilt,
              reading: _shownReading,
              tooCoarse: _shownTooCoarse,
              alignment: _shownAlignment,
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
    unawaited(
      _errors.record(source: 'live_sheet_reader', error: error, stack: stack),
    );
    final camera = _camera;
    _stopLive();
    if (camera != null) unawaited(_stopFrames(camera));
    if (mounted) setState(() {});
  }

  /// Stops the live reading at once: no frame is accepted, the reader is
  /// killed, and any reply still on its way is stale. The frames stop where
  /// the caller awaits them.
  void _stopLive() {
    _trigger.close();
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
    _quality = null;
    _shownQuality = null;
    _shownAlignment = null;
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
        _wantCamera = !_showingGuide;
        unawaited(_openCamera());
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        _wantCamera = false;
        _releaseCamera();
    }
  }

  Future<void> _shoot({bool automatic = false}) async {
    final camera = _camera;
    if (_controlsBusy || _shooting || _closed || camera == null) return;
    _shooting = true;
    unawaited(AppHaptics.result());
    _flash();
    // Read now: the screen may be closed by the time the shot returns.
    final stillSizes = ref.read(stillSizeStoreProvider);
    // The reader stops before the shot, and nothing waits on its last frame.
    // Stopping closes the window, so the ring and its banner go now.
    _stopLive();
    if (mounted) setState(() {});
    // Set before the first await, so a release queued meanwhile waits on it,
    // and completed in the finally whether the shot succeeds or throws.
    final inFlight = Completer<void>();
    _shotInFlight = inFlight.future;
    try {
      final XFile file;
      try {
        await _stopFrames(camera);
        file = await camera.takePicture();
      } finally {
        inFlight.complete();
      }
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
      // Only a window opened after this failure, lasting its full second,
      // fires again.
      _trigger.failedAt(_clock());
      unawaited(
        _errors.record(source: 'guided_camera', error: e, stack: stack),
      );
      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Não foi possível tirar a foto. Tente de novo.'),
        ),
      );
      if (identical(_camera, camera)) unawaited(_startLive(camera));
    }
  }

  /// A short white flash over the preview when the automatic shot fires, not
  /// shown when the system or user asks for reduced motion.
  void _flash() {
    if (!mounted ||
        context.palette.isSun ||
        AppMotion.reduceMotion ||
        MediaQuery.disableAnimationsOf(context)) {
      return;
    }
    setState(() => _flashing = true);
    _flashTimer?.cancel();
    _flashTimer = Timer(AppMotion.fast, () {
      if (mounted) setState(() => _flashing = false);
    });
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
    _alertTimer?.cancel();
    _flashTimer?.cancel();
    _shake.dispose();
    _closed = true;
    _wantCamera = false;
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_tiltSubscription?.cancel());
    _releaseCamera(rebuild: false);
    final opening = _opening;
    // Queued after the live camera's release. An initialisation still in
    // flight releases its own camera when it completes stale; the reset waits
    // for that too, and a camera screen opened meanwhile waits for the reset.
    unawaited(
      _releases.add(() async {
        await opening;
        await _resetOrientation();
      }),
    );
    super.dispose();
  }

  Widget _control({
    required String label,
    required IconData icon,
    required VoidCallback? onPressed,
  }) => VisioIconButton(
    label: label,
    icon: icon,
    overPhoto: true,
    onPressed: _shooting || _controlsBusy ? null : onPressed,
  );

  Future<void> _changeCamera() async {
    final camera = _camera;
    if (camera == null || _controlsBusy || _shooting || _closed) return;
    setState(() => _controlsBusy = true);
    _stopLive();
    final operation = Completer<void>();
    _shotInFlight = operation.future;
    try {
      await _stopFrames(camera);
      if (!identical(_camera, camera) || _closed) return;
      await camera.switchCamera();
    } on Exception catch (error, stack) {
      unawaited(
        _errors.record(source: 'guided_camera', error: error, stack: stack),
      );
      if (mounted && !_closed) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível ajustar a câmera.')),
        );
      }
    } finally {
      operation.complete();
      _controlsBusy = false;
      if (mounted && !_closed) {
        setState(() {});
        if (identical(_camera, camera)) unawaited(_startLive(camera));
      }
    }
  }

  Future<void> _openGuide() async {
    if (_shooting || _controlsBusy || _closed || _showingGuide) return;
    _showingGuide = true;
    _wantCamera = false;
    _releaseCamera();
    await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => const CaptureGuideScreen()));
    _showingGuide = false;
    if (!mounted || _closed) return;
    _wantCamera =
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    if (_wantCamera) unawaited(_openCamera());
  }

  bool _canCapture(GuidanceRow row) =>
      (_shownReading == null || row == GuidanceRow.ready) &&
      (_quality == null || (_quality!.lightOk && _quality!.focusOk));

  QualityStatus _status(bool? ok) => ok == null
      ? QualityStatus.adjusting
      : ok
      ? QualityStatus.ready
      : QualityStatus.failed;

  Widget _qualityChips(GuidanceRow row) {
    final distance = _shownReading == null ? null : row == GuidanceRow.ready;
    final chips = [
      QualityChip(
        label: 'Luz',
        value: _shownQuality == null
            ? 'Ajustando…'
            : _shownQuality!.lightOk
            ? 'Boa'
            : _shownQuality!.tooBright
            ? 'Excessiva'
            : 'Baixa',
        status: _status(_shownQuality?.lightOk),
        highlight: _failedChips.contains('Luz'),
      ),
      QualityChip(
        label: 'Foco',
        value: _shownQuality == null
            ? 'Ajustando…'
            : _shownQuality!.focusOk
            ? 'Nítido'
            : 'Desfocado',
        status: _status(_shownQuality?.focusOk),
        highlight: _failedChips.contains('Foco'),
      ),
      QualityChip(
        label: 'Distância',
        value: distance == null
            ? 'Ajustando…'
            : distance
            ? 'Enquadrada'
            : 'Ajuste a moldura',
        status: _status(distance),
        highlight: _failedChips.contains('Distância'),
      ),
    ];
    if (MediaQuery.textScalerOf(context).scale(1) >= 1.3) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final chip in chips)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: chip,
            ),
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < chips.length; i++) ...[
          if (i > 0) const SizedBox(width: AppSpacing.sm),
          Expanded(child: chips[i]),
        ],
      ],
    );
  }

  void _onShutter(GuidanceRow row) {
    if (_camera == null || _shooting || _controlsBusy) return;
    if (_canCapture(row)) {
      unawaited(_shoot());
      return;
    }
    final failures = <String, String>{};
    final chips = <String>{};
    if (_quality != null && !_quality!.lightOk) {
      failures[_quality!.tooBright ? 'Luz excessiva' : 'Pouca luz'] =
          'Procure sombra clara';
      chips.add('Luz');
    }
    if (_quality != null && !_quality!.focusOk) {
      failures['fora de foco'] = 'segure firme';
      chips.add('Foco');
    }
    if (_shownReading != null && row != GuidanceRow.ready) {
      final close =
          row == GuidanceRow.sheetCropped ||
          _shownAlignment?.fix == MisalignmentFix.farther;
      failures[close ? 'perto demais' : 'longe demais'] = close
          ? 'afaste até a folha caber na moldura'
          : 'aproxime até a amostra preencher a moldura';
      chips.add('Distância');
    }
    setState(() {
      _failures = failures;
      _failedChips = chips;
    });
    _alertTimer?.cancel();
    _alertTimer = Timer(CaptureAlert.visibleDuration, () {
      if (mounted) {
        setState(() {
          _failures = null;
          _failedChips = {};
        });
      }
    });
    if (!AppMotion.reduceMotion && !MediaQuery.disableAnimationsOf(context)) {
      _shake.forward(from: 0);
    }
    unawaited(AppHaptics.blocked());
  }

  @override
  Widget build(BuildContext context) {
    final windowOpen = _trigger.windowOpenedAt != null;
    final shown = guidanceFor(
      tilt: _tilt,
      reading: _shownReading,
      tooCoarse: _shownTooCoarse,
      alignment: _shownAlignment,
    );
    final guidance = windowOpen
        ? const Guidance(
            tone: GuidanceTone.ready,
            message: 'Segure firme…',
            icon: Icons.pan_tool_outlined,
          )
        : shown.guidance;
    final camera = _camera;
    // A sheet off the screen turns every bracket red under its warning; a
    // whole one shows each guide's own state (SPEC 0169).
    final reading = _shownReading;
    final alignment = _shownAlignment;
    final croppedSides = croppedSidesOf(reading, alignment);
    final cropped = reading is LiveSheetCropped || croppedSides.isNotEmpty;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Drawn whole, so the screen shows what the still holds and the
          // outline is a share of the still (SPEC 0171).
          if (camera != null)
            ClipRect(
              child: FittedBox(
                fit: BoxFit.contain,
                child: SizedBox.fromSize(
                  size: camera.previewSize,
                  child: camera.buildPreview(),
                ),
              ),
            ),
          if (_flashing)
            const IgnorePointer(
              child: ColoredBox(
                key: ValueKey('guided-camera-flash'),
                color: Color(0x8CFFFFFF),
              ),
            ),
          SafeArea(
            child: CaptureGuideOverlay(
              preview: camera == null
                  ? null
                  : previewRectOnOverlay(
                      previewSize: camera.previewSize,
                      screenSize: MediaQuery.sizeOf(context),
                      safePadding: MediaQuery.paddingOf(context),
                    ),
              topInset: GuidedCameraScreen.bannerHeight,
              bottomInset: GuidedCameraScreen.footerHeight,
              tilt: _tilt,
              direction: _smoother.direction,
              brackets: cropped
                  ? {
                      for (final position in BracketPosition.values)
                        position: GuideState.off,
                    }
                  : alignment?.brackets ?? allIdle,
              // An arrow only ever says what the banner says.
              arrow: shown.row == GuidanceRow.sheetMisaligned
                  ? alignment?.arrow
                  : null,
              target: cropped ? GuideState.idle : targetStateFor(reading),
              glow: croppedSides,
              warning: cropped ? croppedWarning(croppedSides) : null,
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                ColoredBox(
                  color: Colors.black54,
                  child: Row(
                    children: [
                      VisioIconButton(
                        key: const ValueKey('guided-camera-close'),
                        label: 'Fechar',
                        icon: Icons.close,
                        overPhoto: true,
                        onPressed: () =>
                            _pop(const GuidedCaptureResult.cancelled()),
                      ),
                      const Expanded(
                        child: Text(
                          'Nova análise',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      _control(
                        label: 'Como fotografar',
                        icon: Icons.info_outline,
                        onPressed: _openGuide,
                      ),
                    ],
                  ),
                ),
                _GuidanceBanner(guidance: guidance),
                Expanded(
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: SingleChildScrollView(
                      child: Container(
                        color: Colors.black,
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 560),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (_failures != null) ...[
                                  CaptureAlert(failures: _failures!),
                                  const SizedBox(height: AppSpacing.sm),
                                ],
                                _qualityChips(shown.row),
                                const SizedBox(height: AppSpacing.lg),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceEvenly,
                                  children: [
                                    AnimatedBuilder(
                                      animation: _shake,
                                      builder: (context, child) =>
                                          Transform.translate(
                                            key: const ValueKey(
                                              'guided-camera-shake',
                                            ),
                                            offset: Offset(
                                              math.sin(
                                                    _shake.value * math.pi * 6,
                                                  ) *
                                                  8 *
                                                  (1 - _shake.value),
                                              0,
                                            ),
                                            child: child,
                                          ),
                                      child: _Shutter(
                                        enabled:
                                            _camera != null &&
                                            !_shooting &&
                                            !_controlsBusy &&
                                            _canCapture(shown.row),
                                        shooting: _shooting,
                                        onTap: () => _onShutter(shown.row),
                                        windowOpenedAt: _trigger.windowOpenedAt,
                                        clock: _clock,
                                      ),
                                    ),
                                    _control(
                                      label: 'Trocar câmera',
                                      icon: Icons.flip_camera_ios_outlined,
                                      onPressed: camera?.canSwitchCamera == true
                                          ? () => _changeCamera()
                                          : null,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: AppSpacing.sm),
                                const Text(
                                  'Captura liberada quando os 3 itens estiverem ok',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: Colors.white),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
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
  const _Shutter({
    required this.onTap,
    required this.enabled,
    required this.shooting,
    required this.windowOpenedAt,
    required this.clock,
  });

  final VoidCallback onTap;
  final bool enabled;
  final bool shooting;

  /// When the automatic capture's window opened, or null when none is open:
  /// the ring around the shutter fills across the window's second.
  final DateTime? windowOpenedAt;

  /// The automatic capture's clock, read when the ring is built, so a ring
  /// started late fills from where the window already is. Read here and not
  /// by the parent: a change of the motion setting rebuilds this alone.
  final DateTime Function() clock;

  @override
  Widget build(BuildContext context) {
    final openedAt = windowOpenedAt;
    final reduceMotion =
        AppMotion.reduceMotion || MediaQuery.disableAnimationsOf(context);
    const window = AutoCaptureTrigger.window;
    final elapsed = openedAt == null
        ? 0.0
        : (clock().difference(openedAt).inMicroseconds / window.inMicroseconds)
              .clamp(0.0, 1.0);
    return SizedBox(
      width: 92,
      height: 92,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (openedAt != null)
            IgnorePointer(
              child: SizedBox(
                width: 92,
                height: 92,
                child: TweenAnimationBuilder<double>(
                  // Keyed by the motion setting too, so turning reduced
                  // motion on mid-window stills the ring at once.
                  key: ValueKey((openedAt, reduceMotion)),
                  // Under reduced motion the ring shows full and still;
                  // otherwise it fills from the window's elapsed share over
                  // the rest of its second.
                  tween: Tween(begin: reduceMotion ? 1 : elapsed, end: 1),
                  duration: window * (1 - (reduceMotion ? 1 : elapsed)),
                  builder: (context, value, _) => CustomPaint(
                    key: const ValueKey('guided-camera-ring'),
                    painter: CountdownRingPainter(value),
                  ),
                ),
              ),
            ),
          Semantics(
            button: true,
            label: 'Fotografar',
            enabled: enabled,
            hint: enabled ? null : 'Aguardando luz, foco e distância',
            excludeSemantics: true,
            onTap: enabled ? onTap : null,
            child: GestureDetector(
              key: const ValueKey('guided-camera-shutter'),
              onTap: onTap,
              child: AnimatedScale(
                scale:
                    shooting &&
                        !AppMotion.reduceMotion &&
                        !MediaQuery.disableAnimationsOf(context)
                    ? .86
                    : 1,
                duration: AppMotion.durationOf(context, AppMotion.instant),
                child: Container(
                  width: context.density.shutter,
                  height: context.density.shutter,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: enabled || shooting ? Colors.white : Colors.grey,
                    border: Border.all(
                      color: enabled ? context.palette.primary : Colors.white70,
                      width: 4,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
