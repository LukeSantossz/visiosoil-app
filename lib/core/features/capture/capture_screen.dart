import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
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

class CaptureScreen extends ConsumerStatefulWidget {
  const CaptureScreen({super.key});

  @override
  ConsumerState<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends ConsumerState<CaptureScreen>
    with WidgetsBindingObserver {
  bool _isLoading = false;
  bool _isClassifying = false;
  String? _address;
  double? _latitude;
  double? _longitude;
  InferenceResult? _classificationResult;
  AppPermissionStatus? _cameraPermissionStatus;

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
    // Revalida permissao quando o app volta ao foreground (ex: apos Settings)
    // Nao revalida para `restricted` (iOS) pois nao pode ser alterado pelo usuario
    if (state == AppLifecycleState.resumed &&
        _cameraPermissionStatus == AppPermissionStatus.permanentlyDenied) {
      _recheckCameraPermission();
    }
  }

  Future<void> _recheckCameraPermission() async {
    final status = await PermissionService.checkCamera();
    if (!mounted) return;

    if (status == AppPermissionStatus.granted) {
      setState(() => _cameraPermissionStatus = null);
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    // Verifica permissao de camera antes de abrir
    if (source == ImageSource.camera) {
      final status = await PermissionService.checkCamera();
      if (!mounted) return;

      if (status != AppPermissionStatus.granted) {
        final requestStatus = await PermissionService.requestCamera();
        if (!mounted) return;

        if (requestStatus != AppPermissionStatus.granted) {
          setState(() => _cameraPermissionStatus = requestStatus);
          return;
        }
      }
      // Limpa estado de permissao se concedida
      if (_cameraPermissionStatus != null) {
        setState(() => _cameraPermissionStatus = null);
      }
    }

    final picker = ImagePicker();
    // TODO(v2): reativar galeria
    // await picker.pickImage(source: ImageSource.gallery);
    final XFile? image = await picker.pickImage(source: source);

    if (!mounted || image == null) return;

    ref.read(imageProvider.notifier).setImage(File(image.path), source);

    setState(() {
      _address = null;
      _latitude = null;
      _longitude = null;
      _classificationResult = null;
    });

    // TODO(v2): reativar galeria — Task 15: geolocalização somente para `ImageSource.camera`.
    // if (source == ImageSource.camera) {
    // Executa localização e classificação em paralelo (são independentes)
    await Future.wait([
      _fetchCurrentLocation(),
      _classifySoilTexture(image.path),
    ]);
    // }
  }

  Future<void> _classifySoilTexture(String imagePath) async {
    setState(() => _isClassifying = true);

    try {
      final inferenceService = ref.read(inferenceServiceProvider);
      final result = await inferenceService.classify(imagePath);

      if (mounted) {
        setState(() {
          _classificationResult = result;
          _isClassifying = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isClassifying = false);
      }
    }
  }

  Future<void> _fetchCurrentLocation() async {
    setState(() => _isLoading = true);

    try {
      final position = await LocationService.getCurrentLocation();
      final address = await LocationService.getAddressFromPosition(position);

      if (mounted) {
        setState(() {
          _latitude = position.latitude;
          _longitude = position.longitude;
          _address = address;
          _isLoading = false;
        });
      }
    } catch (e) {
      // Localizacao negada ou indisponivel: app funciona sem GPS
      // O registro sera salvo com coordenadas null
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _saveRecord() async {
    final selectedImage = ref.read(imageProvider);
    final image = selectedImage.file;
    if (image == null) return;

    // TODO(v2): reativar galeria — Task 15: sem coordenadas quando a origem é galeria.
    // final isGallery = selectedImage.source == ImageSource.gallery;
    // final String? finalAddress = isGallery
    //     ? null
    //     : (_address ?? 'Localização não disponível');
    // final double? finalLatitude = isGallery ? null : _latitude;
    // final double? finalLongitude = isGallery ? null : _longitude;
    final String finalAddress =
        _address ?? 'Localização não disponível';
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

    ref.read(imageProvider.notifier).clearImage();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Registro salvo com sucesso!')),
      );
      context.pop();
    }
  }

  void _discardImage() {
    ref.read(imageProvider.notifier).clearImage();
    setState(() {
      _address = null;
      _latitude = null;
      _longitude = null;
      _classificationResult = null;
    });
  }

  void _retryCameraPermission() {
    setState(() => _cameraPermissionStatus = null);
    _pickImage(ImageSource.camera);
  }

  @override
  Widget build(BuildContext context) {
    // Mostra tela de permissao negada se camera foi bloqueada
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
    // TODO(v2): reativar galeria
    // final isFromGallery = selectedImage.source == ImageSource.gallery;

    return Scaffold(
      appBar: const VisioAppBar(title: 'Nova Captura'),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Preview da imagem
              Expanded(
                child: _ImagePreview(
                  image: image,
                  isLoading: _isLoading,
                  isClassifying: _isClassifying,
                  address: _address,
                  classificationResult: _classificationResult,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              // Botões de ação
              if (!hasImage) ...[
                // TODO(v2): reativar galeria — opção `ImageSource.gallery` na UI.
                // Row(
                //   children: [
                //     Expanded(
                //       child: VisioButton(
                //         label: 'Câmera',
                //         icon: Icons.camera_alt,
                //         onPressed: () => _pickImage(ImageSource.camera),
                //       ),
                //     ),
                //     const SizedBox(width: AppSpacing.md),
                //     Expanded(
                //       child: VisioButton(
                //         label: 'Galeria',
                //         icon: Icons.photo_library,
                //         onPressed: () => _pickImage(ImageSource.gallery),
                //         variant: VisioButtonVariant.secondary,
                //       ),
                //     ),
                //   ],
                // ),
                VisioButton(
                  label: 'Câmera',
                  icon: Icons.camera_alt,
                  onPressed: () => _pickImage(ImageSource.camera),
                  expanded: true,
                ),
              ] else ...[
                VisioButton(
                  label: 'Salvar Registro',
                  icon: Icons.check,
                  onPressed: (_isLoading || _isClassifying) ? null : _saveRecord,
                  isLoading: _isLoading || _isClassifying,
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
  });

  final File? image;
  final bool isLoading;
  final bool isClassifying;
  final String? address;
  final InferenceResult? classificationResult;

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
          // Gradient para legibilidade dos chips
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
          // Chips de info
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
