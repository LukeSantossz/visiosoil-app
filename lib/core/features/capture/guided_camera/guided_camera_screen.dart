import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:visiosoil_app/core/features/capture/guided_camera/capture_camera.dart';
import 'package:visiosoil_app/core/features/capture/guided_camera/capture_guidance.dart';
import 'package:visiosoil_app/core/features/capture/guided_camera/capture_guide_overlay.dart';
import 'package:visiosoil_app/core/features/capture/guided_camera/tilt.dart';
import 'package:visiosoil_app/core/features/capture/guided_camera/tilt_source.dart';
import 'package:visiosoil_app/core/theme/app_palette.dart';
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

  /// Whether the screen wants a live camera: false between a release and the
  /// next resume, and after dispose.
  bool _wantCamera = true;
  bool _everInitialized = false;
  bool _shooting = false;
  bool _closed = false;

  final TiltSmoother _smoother = TiltSmoother();
  double? _tilt;
  StreamSubscription<AccelerationSample>? _tiltSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tiltSubscription = ref.read(tiltSourceProvider).samples.listen(
      (sample) {
        final tilt = _smoother.add(sample.x, sample.y, sample.z);
        if (mounted && tilt != _tilt) setState(() => _tilt = tilt);
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
    // Set before the camera opens, so its first frames are already portrait.
    await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    if (!mounted) return;
    await _openCamera();
  }

  Future<void> _openCamera() async {
    if (_initializing || _camera != null || !_wantCamera || _closed) return;
    _initializing = true;
    final generation = _generation;
    final camera = ref.read(captureCameraFactoryProvider)();
    try {
      await camera.initialize();
    } on Exception catch (e, stack) {
      _initializing = false;
      await camera.dispose();
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
      await camera.dispose();
      _reopenIfWanted();
      return;
    }
    setState(() {
      _camera = camera;
      _everInitialized = true;
    });
  }

  /// A stale initialisation finished while the screen wants a camera again:
  /// the resume that arrived meanwhile started none, so start one now.
  void _reopenIfWanted() {
    if (mounted && _wantCamera) unawaited(_openCamera());
  }

  Future<void> _releaseCamera() async {
    _generation++;
    final camera = _camera;
    _camera = null;
    if (mounted) setState(() {});
    await camera?.dispose();
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
        unawaited(_releaseCamera());
    }
  }

  Future<void> _shoot() async {
    final camera = _camera;
    if (_shooting || camera == null) return;
    _shooting = true;
    try {
      final file = await camera.takePicture();
      _pop(GuidedCaptureResult.captured(file));
    } on Exception catch (e, stack) {
      _shooting = false;
      unawaited(ref
          .read(errorReportStoreProvider)
          .record(source: 'guided_camera', error: e, stack: stack));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Não foi possível tirar a foto. Tente de novo.'),
      ));
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
    _generation++;
    final camera = _camera;
    _camera = null;
    unawaited(() async {
      await camera?.dispose();
      // Back to the app's default of every orientation, once the camera is
      // released.
      await SystemChrome.setPreferredOrientations(const []);
    }());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final guidance = guidanceForTilt(_tilt);
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
                      IconButton(
                        key: const ValueKey('guided-camera-close'),
                        tooltip: 'Fechar câmera',
                        iconSize: 32,
                        icon: const Icon(Icons.close, color: Colors.white),
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
