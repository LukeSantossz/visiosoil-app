import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:visiosoil_app/core/constants/storage_keys.dart';
import 'package:visiosoil_app/core/theme/app_spacing.dart';
import 'package:visiosoil_app/core/utils/location_service.dart';
import 'package:visiosoil_app/core/widgets/loading_indicator.dart';
import 'package:visiosoil_app/core/widgets/visio_app_bar.dart';
import 'package:visiosoil_app/core/widgets/visio_button.dart';
import 'package:visiosoil_app/models/soil_record.dart';
import 'package:visiosoil_app/providers/image_provider.dart';

class CaptureScreen extends ConsumerStatefulWidget {
  const CaptureScreen({super.key});

  @override
  ConsumerState<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends ConsumerState<CaptureScreen> {
  bool _isLoading = false;
  String? _address;
  double? _latitude;
  double? _longitude;

  Future<void> _pickImage(ImageSource source) async {
    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: source);

    if (image == null) return;

    ref.read(imageProvider.notifier).setImage(File(image.path), source);

    setState(() {
      _address = null;
      _latitude = null;
      _longitude = null;
    });

    // Apenas imagens da câmera devem acionar geolocalização.
    if (source == ImageSource.camera) {
      await _fetchCurrentLocation();
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
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Não foi possível obter a localização.'),
          ),
        );
      }
    }
  }

  Future<void> _saveRecord() async {
    final selectedImage = ref.read(imageProvider);
    final image = selectedImage.file;
    if (image == null) return;

    final isGallery = selectedImage.source == ImageSource.gallery;

    final String? finalAddress = isGallery
        ? null
        : (_address ?? 'Localização não disponível');
    final double? finalLatitude = isGallery ? null : _latitude;
    final double? finalLongitude = isGallery ? null : _longitude;

    final box = Hive.box<SoilRecord>(StorageKeys.soilRecordsBox);
    box.add(
      SoilRecord(
        imagePath: image.path,
        latitude: finalLatitude,
        longitude: finalLongitude,
        address: finalAddress,
        timestamp: DateTime.now().toIso8601String(),
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
    });
  }

  @override
  Widget build(BuildContext context) {
    final selectedImage = ref.watch(imageProvider);
    final image = selectedImage.file;
    final hasImage = selectedImage.hasImage;
    final isFromGallery = selectedImage.source == ImageSource.gallery;

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
                  address: _address,
                  isFromGallery: isFromGallery,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              // Botões de ação
              if (!hasImage) ...[
                Row(
                  children: [
                    Expanded(
                      child: VisioButton(
                        label: 'Câmera',
                        icon: Icons.camera_alt,
                        onPressed: () => _pickImage(ImageSource.camera),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: VisioButton(
                        label: 'Galeria',
                        icon: Icons.photo_library,
                        onPressed: () => _pickImage(ImageSource.gallery),
                        variant: VisioButtonVariant.secondary,
                      ),
                    ),
                  ],
                ),
              ] else ...[
                VisioButton(
                  label: 'Salvar Registro',
                  icon: Icons.check,
                  onPressed: _isLoading ? null : _saveRecord,
                  isLoading: _isLoading,
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
    required this.isFromGallery,
    this.address,
  });

  final File? image;
  final bool isLoading;
  final String? address;
  final bool isFromGallery;

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

    return Column(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image.file(
              image!,
              fit: BoxFit.cover,
              width: double.infinity,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        // Localização
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isFromGallery) ...[
                Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 20,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      'Localização indisponível',
                      style: theme.textTheme.titleSmall,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Imagens da galeria não recebem coordenadas GPS para preservar a confiabilidade do registro.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ] else ...[
                if (isLoading)
                  Row(
                    children: [
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: LoadingIndicator(size: 20, strokeWidth: 2),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Text(
                        'Obtendo localização...',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  )
                else
                  Row(
                    children: [
                      Icon(
                        Icons.location_on,
                        size: 20,
                        color: address != null
                            ? theme.colorScheme.primary
                            : theme.colorScheme.error,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          address ?? 'Localização não disponível',
                          style: theme.textTheme.bodyMedium,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
