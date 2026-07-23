import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:visiosoil_app/core/constants/app_strings.dart';
import 'package:visiosoil_app/core/features/capture/capture_ui_state.dart';
import 'package:visiosoil_app/core/features/capture/widgets/camera_permission_denied_view.dart';
import 'package:visiosoil_app/core/features/capture/widgets/capture_actions.dart';
import 'package:visiosoil_app/core/features/capture/widgets/capture_image_preview.dart';
import 'package:visiosoil_app/core/services/inference_service.dart';
import 'package:visiosoil_app/core/services/permission_service.dart';
import 'package:visiosoil_app/core/theme/app_spacing.dart';
import 'package:visiosoil_app/core/utils/location_service.dart';
import 'package:visiosoil_app/core/widgets/visio_app_bar.dart';
import 'package:visiosoil_app/models/soil_record.dart';
import 'package:visiosoil_app/providers/image_provider.dart';
import 'package:visiosoil_app/providers/inference_provider.dart';
import 'package:visiosoil_app/providers/soil_record_repository_provider.dart';

/// A device location reading: coordinates plus a reverse-geocoded address.
typedef LocationReading = ({double latitude, double longitude, String address});

/// Resolves the current device location, or `null` when unavailable.
typedef LocationResolver = Future<LocationReading?> Function();

/// Opens the camera and returns the captured image, or `null` if cancelled.
typedef CameraImagePicker = Future<XFile?> Function();

/// Reports a camera permission status.
typedef CameraPermissionProbe = Future<AppPermissionStatus> Function();

class CaptureScreen extends ConsumerStatefulWidget {
  const CaptureScreen({
    super.key,
    this.pickFromCamera,
    this.locate,
    this.checkCameraPermission,
    this.requestCameraPermission,
  });

  /// Test seams; each defaults to the real platform implementation.
  final CameraImagePicker? pickFromCamera;
  final LocationResolver? locate;
  final CameraPermissionProbe? checkCameraPermission;
  final CameraPermissionProbe? requestCameraPermission;

  @override
  ConsumerState<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends ConsumerState<CaptureScreen>
    with WidgetsBindingObserver {
  static const Duration _locationTimeout = Duration(seconds: 20);

  /// Single immutable UI state. Every mutation goes through
  /// `setState(() => _state = _state.copyWith(...))` (or a named transition),
  /// replacing the previously scattered booleans, payload fields, and request
  /// token. See [CaptureUiState] for why location and classification are
  /// independent axes rather than one flat enum.
  CaptureUiState _state = const CaptureUiState();

  late final CameraImagePicker _pickFromCamera =
      widget.pickFromCamera ?? _defaultPickFromCamera;
  late final LocationResolver _locate = widget.locate ?? _defaultLocate;
  late final CameraPermissionProbe _checkCameraPermission =
      widget.checkCameraPermission ?? PermissionService.checkCamera;
  late final CameraPermissionProbe _requestCameraPermission =
      widget.requestCameraPermission ?? PermissionService.requestCamera;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Revalidates permission when the app returns to the foreground (e.g. after Settings)
    // Does not revalidate for `restricted` (iOS) since it cannot be changed by the user
    if (state == AppLifecycleState.resumed &&
        _state.cameraPermission == AppPermissionStatus.permanentlyDenied) {
      _recheckCameraPermission();
    }
  }

  Future<XFile?> _defaultPickFromCamera() => ImagePicker().pickImage(
        source: ImageSource.camera,
        // Drop EXIF (including GPS) at the source so stored originals carry no
        // uncontrolled location duplicate; the app never reads image metadata.
        requestFullMetadata: false,
      );

  Future<LocationReading?> _defaultLocate() async {
    final position = await LocationService.getCurrentLocation();
    final address = await LocationService.getAddressFromPosition(position);
    return (
      latitude: position.latitude,
      longitude: position.longitude,
      address: address,
    );
  }

  Future<void> _recheckCameraPermission() async {
    final status = await _checkCameraPermission();
    if (!mounted) return;

    if (status == AppPermissionStatus.granted) {
      setState(() => _state = _state.copyWith(cameraPermission: null));
    }
  }

  Future<void> _pickImage() async {
    // Re-entry guard: prevents a rapid double tap from opening two pickers
    // (and firing duplicate location/classification work).
    if (_state.isCapturing) return;
    _state = _state.copyWith(isCapturing: true);

    XFile? image;
    try {
      final status = await _checkCameraPermission();
      if (!mounted) return;

      if (status != AppPermissionStatus.granted) {
        final requestStatus = await _requestCameraPermission();
        if (!mounted) return;

        if (requestStatus != AppPermissionStatus.granted) {
          setState(
              () => _state = _state.copyWith(cameraPermission: requestStatus));
          return;
        }
      }
      // Clears the permission state if granted
      if (_state.cameraPermission != null) {
        setState(() => _state = _state.copyWith(cameraPermission: null));
      }

      image = await _pickFromCamera();
    } catch (e) {
      developer.log('Camera capture failed: $e', name: 'CaptureScreen');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível abrir a câmera.')),
        );
      }
      return;
    } finally {
      _state = _state.copyWith(isCapturing: false);
    }

    if (!mounted || image == null) return;

    ref.read(imageProvider.notifier).setImage(File(image.path));

    // Tags this capture so late results from a superseded one are ignored.
    final generation = _state.generation + 1;
    setState(() => _state = _state.startingCapture(generation));

    // Runs location and classification in parallel (they are independent)
    await Future.wait([
      _fetchCurrentLocation(generation),
      _classifySoilTexture(image.path, generation),
    ]);
  }

  Future<void> _classifySoilTexture(String imagePath, int generation) async {
    if (mounted) {
      setState(() => _state =
          _state.copyWith(classification: ClassificationStatus.running));
    }

    InferenceResult? result;
    try {
      final inferenceService = ref.read(inferenceServiceProvider);
      // No deadline here: `classify` owns the only one, because it holds the
      // isolate handle and can stop the work. A second timeout at this layer
      // would abandon the future while the isolate kept running.
      result = await inferenceService.classify(imagePath);
    } catch (e) {
      developer.log('Classification failed: $e', name: 'CaptureScreen');
      result = null;
    }

    if (!mounted || generation != _state.generation) return;
    setState(() => _state = _state.copyWith(
          classificationResult: result,
          classification: result == null
              ? ClassificationStatus.failed
              : ClassificationStatus.done,
        ));
  }

  Future<void> _fetchCurrentLocation(int generation) async {
    if (mounted) {
      setState(() => _state = _state.copyWith(location: LocationStatus.loading));
    }

    LocationReading? reading;
    try {
      reading =
          await _locate().timeout(_locationTimeout, onTimeout: () => null);
    } catch (_) {
      // Location is optional: the record can be saved without coordinates.
      reading = null;
    }

    if (!mounted || generation != _state.generation) return;
    setState(() {
      if (reading != null) {
        _state = _state.copyWith(
          location: LocationStatus.resolved,
          latitude: reading.latitude,
          longitude: reading.longitude,
          address: reading.address,
        );
      } else {
        _state = _state.copyWith(location: LocationStatus.unavailable);
      }
    });
  }

  void _retryClassification() {
    // Mirrors the `_isCapturing`/`_isSaving` guards. The retry chip is only
    // rendered once a classification has failed, so a second tap is already
    // improbable; this closes the same-frame window where two taps hit the
    // chip before the rebuild removes it, each spawning its own isolate.
    if (_state.isClassifying) return;
    final image = ref.read(imageProvider).file;
    if (image == null) return;
    _classifySoilTexture(image.path, _state.generation);
  }

  Future<void> _saveRecord() async {
    // Guard against double-tap
    if (_state.isSaving) return;

    final selectedImage = ref.read(imageProvider);
    final image = selectedImage.file;
    if (image == null) return;

    // Capture the notifier before the await so the post-save cleanup never
    // touches `ref` after the widget is disposed.
    final imageNotifier = ref.read(imageProvider.notifier);

    setState(() => _state = _state.copyWith(isSaving: true));

    var didCreate = false;
    try {
      final String finalAddress = _state.address ?? AppStrings.addressUnavailable;
      final double? finalLatitude = _state.latitude;
      final double? finalLongitude = _state.longitude;

      await ref.read(soilRecordRepositoryProvider).create(
            SoilRecord(
              imagePath: image.path,
              latitude: finalLatitude,
              longitude: finalLongitude,
              address: finalAddress,
              timestamp: DateTime.now().toIso8601String(),
              textureClass: _state.classificationResult?.textureClass,
              confidenceScore: _state.classificationResult?.confidenceScore,
            ),
          );
      didCreate = true;
    } catch (e) {
      // A repository write failure must not leave the user without feedback:
      // surface it and keep the image (no clearImage/pop) so they can retry.
      developer.log('Save failed: $e', name: 'CaptureScreen');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('Não foi possível salvar o registro. Tente novamente.'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _state = _state.copyWith(isSaving: false));
      }
    }

    // Only after a confirmed write, and outside the try so a post-save UI error
    // is never mis-reported as a save failure (which would prompt a retry and
    // write a duplicate). Clear via the captured notifier — even if the screen
    // was disposed mid-save — but only if the provider still holds the photo we
    // saved, so a slow write finishing after a newer capture does not wipe it.
    // Only the snackbar/pop need the widget still mounted.
    if (didCreate) {
      imageNotifier.clearIfPath(image.path);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Registro salvo com sucesso!')),
        );
        context.pop();
      }
    }
  }

  void _discardImage() {
    // Invalidates any in-flight location/classification work for this capture.
    final generation = _state.generation + 1;
    ref.read(imageProvider.notifier).clearImage();
    setState(() => _state = _state.startingCapture(generation));
  }

  void _retryCameraPermission() {
    setState(() => _state = _state.copyWith(cameraPermission: null));
    _pickImage();
  }

  @override
  Widget build(BuildContext context) {
    // Shows the permission denied screen if the camera was blocked
    final cameraPermission = _state.cameraPermission;
    if (cameraPermission != null &&
        cameraPermission != AppPermissionStatus.granted) {
      return CameraPermissionDeniedView(
        status: cameraPermission,
        onRetry: _retryCameraPermission,
      );
    }

    final selectedImage = ref.watch(imageProvider);
    final image = selectedImage.file;
    final hasImage = selectedImage.hasImage;

    return Scaffold(
      appBar: const VisioAppBar(title: 'Nova Captura'),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Image preview
              Expanded(
                child: CaptureImagePreview(
                  image: image,
                  isLoading: _state.isLocating,
                  isClassifying: _state.isClassifying,
                  address: _state.address,
                  classificationResult: _state.classificationResult,
                  classificationFailed: _state.classificationFailed,
                  onRetryClassification: _retryClassification,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              CaptureActions(
                hasImage: hasImage,
                isBusy: _state.isLocating ||
                    _state.isClassifying ||
                    _state.isSaving,
                onCapture: _pickImage,
                onSave: _saveRecord,
                onDiscard: _discardImage,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
