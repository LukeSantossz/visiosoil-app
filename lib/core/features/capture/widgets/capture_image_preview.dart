import 'dart:io';

import 'package:flutter/material.dart';
import 'package:visiosoil_app/core/services/inference_service.dart';
import 'package:visiosoil_app/core/theme/app_spacing.dart';
import 'package:visiosoil_app/core/widgets/loading_indicator.dart';

/// The capture screen's image area: a placeholder before a photo is taken, and
/// once one exists the photo overlaid with the location and classification info
/// chips (each reflecting its own loading / result / failed state).
class CaptureImagePreview extends StatelessWidget {
  const CaptureImagePreview({
    super.key,
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
                _buildLocationChip(),
                _buildClassificationChip(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLocationChip() {
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

  Widget _buildClassificationChip() {
    if (isClassifying) {
      return _InfoChip(
        icon: Icons.eco,
        label: 'Classificando...',
        isLoading: true,
      );
    }
    if (classificationResult != null) {
      final confidence =
          (classificationResult!.confidenceScore * 100).toStringAsFixed(0);
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
