import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:visiosoil_app/core/constants/app_strings.dart';
import 'package:visiosoil_app/core/services/inference_service.dart';
import 'package:visiosoil_app/core/services/permission_service.dart';
import 'package:visiosoil_app/core/theme/app_spacing.dart';
import 'package:visiosoil_app/core/utils/location_service.dart';
import 'package:visiosoil_app/core/widgets/loading_indicator.dart';
import 'package:visiosoil_app/core/widgets/permission_denied_view.dart';
import 'package:visiosoil_app/core/widgets/visio_app_bar.dart';
import 'package:visiosoil_app/core/widgets/visio_button.dart';
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

  bool _isLoading = false;
  bool _isClassifying = false;
  bool _isSaving = false;
  bool _isCapturing = false;
  bool _classificationFailed = false;
  String? _address;
  double? _latitude;
  double? _longitude;
  InferenceResult? _classificationResult;
  AppPermissionStatus? _cameraPermissionStatus;

  /// Monotonic token identifying the current capture. Async results from a
  /// superseded or discarded capture carry a stale token and are ignored.
  int _requestGeneration = 0;

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
        _cameraPermissionStatus == AppPermissionStatus.permanentlyDenied) {
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
      setState(() => _cameraPermissionStatus = null);
    }
  }

  Future<void> _pickImage() async {
    // Re-entry guard: prevents a rapid double tap from opening two pickers
    // (and firing duplicate location/classification work).
    if (_isCapturing) return;
    _isCapturing = true;

    XFile? image;
    try {
      final status = await _checkCameraPermission();
      if (!mounted) return;

      if (status != AppPermissionStatus.granted) {
        final requestStatus = await _requestCameraPermission();
        if (!mounted) return;

        if (requestStatus != AppPermissionStatus.granted) {
          setState(() => _cameraPermissionStatus = requestStatus);
          return;
        }
      }
      // Clears the permission state if granted
      if (_cameraPermissionStatus != null) {
        setState(() => _cameraPermissionStatus = null);
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
      _isCapturing = false;
    }

    if (!mounted || image == null) return;

    ref.read(imageProvider.notifier).setImage(File(image.path));

    // Tags this capture so late results from a superseded one are ignored.
    final generation = ++_requestGeneration;
    setState(() {
      _address = null;
      _latitude = null;
      _longitude = null;
      _classificationResult = null;
      _classificationFailed = false;
    });

    // Runs location and classification in parallel (they are independent)
    await Future.wait([
      _fetchCurrentLocation(generation),
      _classifySoilTexture(image.path, generation),
    ]);
  }

  Future<void> _classifySoilTexture(String imagePath, int generation) async {
    if (mounted) {
      setState(() {
        _isClassifying = true;
        _classificationFailed = false;
      });
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

    if (!mounted || generation != _requestGeneration) return;
    setState(() {
      _classificationResult = result;
      _classificationFailed = result == null;
      _isClassifying = false;
    });
  }

  Future<void> _fetchCurrentLocation(int generation) async {
    if (mounted) setState(() => _isLoading = true);

    LocationReading? reading;
    try {
      reading =
          await _locate().timeout(_locationTimeout, onTimeout: () => null);
    } catch (_) {
      // Location is optional: the record can be saved without coordinates.
      reading = null;
    }

    if (!mounted || generation != _requestGeneration) return;
    setState(() {
      if (reading != null) {
        _latitude = reading.latitude;
        _longitude = reading.longitude;
        _address = reading.address;
      }
      _isLoading = false;
    });
  }

  void _retryClassification() {
    // Mirrors the `_isCapturing`/`_isSaving` guards. The retry chip is only
    // rendered once a classification has failed, so a second tap is already
    // improbable; this closes the same-frame window where two taps hit the
    // chip before the rebuild removes it, each spawning its own isolate.
    if (_isClassifying) return;
    final image = ref.read(imageProvider).file;
    if (image == null) return;
    _classifySoilTexture(image.path, _requestGeneration);
  }

  Future<void> _saveRecord() async {
    // Guard against double-tap
    if (_isSaving) return;

    final selectedImage = ref.read(imageProvider);
    final image = selectedImage.file;
    if (image == null) return;

    // Capture the notifier before the await so the post-save cleanup never
    // touches `ref` after the widget is disposed.
    final imageNotifier = ref.read(imageProvider.notifier);

    setState(() => _isSaving = true);

    var didCreate = false;
    try {
      final String finalAddress = _address ?? AppStrings.addressUnavailable;
      final double? finalLatitude = _latitude;
      final double? finalLongitude = _longitude;

      await ref.read(soilRecordRepositoryProvider).create(
            SoilRecord(
              imagePath: image.path,
              latitude: finalLatitude,
              longitude: finalLongitude,
              address: finalAddress,
              timestamp: DateTime.now().toIso8601String(),
              textureClass: _classificationResult?.textureClass,
              confidenceScore: _classificationResult?.confidenceScore,
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
        setState(() => _isSaving = false);
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
    _requestGeneration++;
    ref.read(imageProvider.notifier).clearImage();
    setState(() {
      _address = null;
      _latitude = null;
      _longitude = null;
      _classificationResult = null;
      _classificationFailed = false;
    });
  }

  void _retryCameraPermission() {
    setState(() => _cameraPermissionStatus = null);
    _pickImage();
  }

  @override
  Widget build(BuildContext context) {
    // Shows the permission denied screen if the camera was blocked
    if (_cameraPermissionStatus != null &&
        _cameraPermissionStatus != AppPermissionStatus.granted) {
      final isRestricted =
          _cameraPermissionStatus == AppPermissionStatus.restricted;
      final isPermanentlyDenied =
          _cameraPermissionStatus == AppPermissionStatus.permanentlyDenied;

      return Scaffold(
        appBar: const VisioAppBar(title: 'Nova Captura'),
        body: PermissionDeniedView(
          icon: Icons.camera_alt,
          title: isRestricted
              ? 'Camera restrita'
              : 'Acesso a camera necessario',
          description: isRestricted
              ? 'O acesso a camera esta restrito por configuracoes do dispositivo (controle parental ou MDM). Contacte o administrador.'
              : 'Para capturar fotos de amostras de solo, o VisioSoil precisa de acesso a camera do dispositivo.',
          isPermanentlyDenied: isPermanentlyDenied || isRestricted,
          onRetry: isRestricted ? null : _retryCameraPermission,
        ),
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
                child: _ImagePreview(
                  image: image,
                  isLoading: _isLoading,
                  isClassifying: _isClassifying,
                  address: _address,
                  classificationResult: _classificationResult,
                  classificationFailed: _classificationFailed,
                  onRetryClassification: _retryClassification,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              // Action buttons
              if (!hasImage) ...[
                VisioButton(
                  label: 'Câmera',
                  icon: Icons.camera_alt,
                  onPressed: _pickImage,
                  expanded: true,
                ),
              ] else ...[
                VisioButton(
                  label: 'Salvar Registro',
                  icon: Icons.check,
                  onPressed: (_isLoading || _isClassifying || _isSaving) ? null : _saveRecord,
                  isLoading: _isLoading || _isClassifying || _isSaving,
                  expanded: true,
                ),
                const SizedBox(height: AppSpacing.sm),
                VisioButton(
                  label: 'Descartar',
                  icon: Icons.close,
                  onPressed: _discardImage,
                  variant: VisioButtonVariant.secondary,
                  expanded: true,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ImagePreview extends StatelessWidget {
  const _ImagePreview({
    required this.image,
    required this.isLoading,
    required this.isClassifying,
    this.address,
    this.classificationResult,
    this.classificationFailed = false,
    this.onRetryClassification,
  });

  final File? image;
  final bool isLoading;
  final bool isClassifying;
  final String? address;
  final InferenceResult? classificationResult;
  final bool classificationFailed;
  final VoidCallback? onRetryClassification;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (image == null) {
      return Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.add_a_photo,
                size: 64,
                color: theme.colorScheme.onSurfaceVariant.withValues(
                  alpha: 0.5,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Selecione uma imagem',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.file(
            image!,
            fit: BoxFit.cover,
            width: double.infinity,
          ),
          // Gradient for chip legibility
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 100,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.6),
                  ],
                ),
              ),
            ),
          ),
          // Info chips
          Positioned(
            left: AppSpacing.sm,
            right: AppSpacing.sm,
            bottom: AppSpacing.sm,
            child: Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                _buildLocationChip(theme),
                _buildClassificationChip(theme),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLocationChip(ThemeData theme) {
    if (isLoading) {
      return _InfoChip(
        icon: Icons.location_on,
        label: 'Localizando...',
        isLoading: true,
      );
    }
    return _InfoChip(
      icon: Icons.location_on,
      label: address ?? 'Sem localização',
    );
  }

  Widget _buildClassificationChip(ThemeData theme) {
    if (isClassifying) {
      return _InfoChip(
        icon: Icons.eco,
        label: 'Classificando...',
        isLoading: true,
      );
    }
    if (classificationResult != null) {
      final confidence = (classificationResult!.confidenceScore * 100)
          .toStringAsFixed(0);
      return _InfoChip(
        icon: Icons.eco,
        label: '${classificationResult!.textureClass} · $confidence%',
      );
    }
    if (classificationFailed) {
      return GestureDetector(
        key: const Key('retryClassification'),
        onTap: onRetryClassification,
        child: const _InfoChip(
          icon: Icons.refresh,
          label: 'Classificação falhou · tocar para repetir',
        ),
      );
    }
    return const _InfoChip(
      icon: Icons.eco_outlined,
      label: 'Classificação indisponível',
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({
    required this.icon,
    required this.label,
    this.isLoading = false,
  });

  final IconData icon;
  final String label;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isLoading)
            const SizedBox(
              width: 14,
              height: 14,
              child: LoadingIndicator(size: 14, strokeWidth: 1.5),
            )
          else
            Icon(icon, size: 14, color: Colors.white),
          const SizedBox(width: AppSpacing.xs),
          Flexible(
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Colors.white,
                  ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
