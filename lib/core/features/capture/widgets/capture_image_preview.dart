import 'dart:io';

import 'package:flutter/material.dart';
import 'package:visiosoil_app/core/constants/app_strings.dart';
import 'package:visiosoil_app/core/features/capture/widgets/classification_failure_chip.dart';
import 'package:visiosoil_app/core/services/classification_report.dart';
import 'package:visiosoil_app/core/services/inference_service.dart';
import 'package:visiosoil_app/core/theme/app_motion.dart';
import 'package:visiosoil_app/core/theme/app_radius.dart';
import 'package:visiosoil_app/core/theme/app_spacing.dart';
import 'package:visiosoil_app/core/utils/formatters.dart';
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
    this.classificationPhase,
    this.address,
    this.latitude,
    this.longitude,
    this.classificationResult,
    this.classificationFailed = false,
    this.classificationFailureCause,
    this.onRetryClassification,
  });

  final File? image;
  final bool isLoading;
  final bool isClassifying;

  /// The step the running classification is in; null before the first one
  /// arrives, which keeps "Classificando..." (SPEC 0116).
  final ClassificationPhase? classificationPhase;
  final String? address;

  /// The reading's coordinates, shown when the address lookup failed but GPS
  /// answered, as details and home already do (SPEC 0114).
  final double? latitude;
  final double? longitude;
  final InferenceResult? classificationResult;
  final bool classificationFailed;

  /// Why the classification failed, which picks the chip's copy and whether it
  /// offers a retry. Null keeps the generic retry chip.
  final ClassificationFailureCause? classificationFailureCause;
  final VoidCallback? onRetryClassification;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (image == null) {
      return Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(AppRadius.lg),
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
      borderRadius: BorderRadius.circular(AppRadius.lg),
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
                _crossfade(context, _buildLocationChip()),
                // A live region, so a screen reader announces each new phase
                // and the verdict that follows (SPEC 0116).
                Semantics(
                  liveRegion: true,
                  child: _crossfade(context, _buildClassificationChip()),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // A chip crossfades into the next over AppMotion.base, since each chip is
  // keyed by its label. The outgoing one is drawn but neither announced nor
  // tappable, so the live region reads only the new label and a fading retry
  // chip takes no tap (SPEC 0134).
  Widget _crossfade(BuildContext context, Widget chip) {
    if (MediaQuery.disableAnimationsOf(context)) return chip;
    return AnimatedSwitcher(
      duration: AppMotion.base,
      transitionBuilder: _fade,
      layoutBuilder: (current, previous) => Stack(
        alignment: AlignmentDirectional.centerStart,
        children: [
          for (final child in previous) _inSwitcher(child, outgoing: true),
          if (current != null) _inSwitcher(current, outgoing: false),
        ],
      ),
      child: chip,
    );
  }

  // Keyed by its own animation, not by the chip's label: a label that returns
  // while its last chip is still fading out is a second, distinct transition.
  static Widget _fade(Widget child, Animation<double> animation) =>
      FadeTransition(key: ObjectKey(animation), opacity: animation, child: child);

  // One wrapper for both roles, keyed by the transition, so a chip that turns
  // outgoing keeps its element.
  static Widget _inSwitcher(Widget child, {required bool outgoing}) =>
      IgnorePointer(
        key: child.key,
        ignoring: outgoing,
        child: ExcludeSemantics(excluding: outgoing, child: child),
      );

  Widget _buildLocationChip() {
    if (isLoading) {
      return _InfoChip(
        icon: Icons.location_on,
        label: 'Localizando...',
        isLoading: true,
      );
    }
    return _InfoChip(icon: Icons.location_on, label: _locationLabel());
  }

  String _locationLabel() {
    final address = this.address;
    if (address != null &&
        address.isNotEmpty &&
        address != AppStrings.addressUnavailable) {
      return address;
    }
    final latitude = this.latitude;
    final longitude = this.longitude;
    if (latitude != null && longitude != null) {
      return Formatters.coordinates(latitude, longitude);
    }
    return 'Sem localização';
  }

  Widget _buildClassificationChip() {
    if (isClassifying) {
      return _InfoChip(
        icon: Icons.eco,
        label: _phaseLabel(classificationPhase),
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
      final cause = classificationFailureCause;
      if (cause == null) {
        return _retryChip('Classificação falhou · tocar para repetir');
      }
      final chip = classificationFailureChip(cause);
      if (chip.retryable) return _retryChip(chip.label);
      // Running the same file again would return the same cause, so the chip
      // says what to change and offers no tap (SPEC 0105).
      return _InfoChip(icon: Icons.info_outline, label: chip.label);
    }
    return _InfoChip(
      icon: Icons.eco_outlined,
      label: 'Classificação indisponível',
    );
  }

  static String _phaseLabel(ClassificationPhase? phase) => switch (phase) {
        null => 'Classificando...',
        ClassificationPhase.readingPhotograph => 'Lendo a foto...',
        ClassificationPhase.findingSheet => 'Procurando a folha A4...',
        ClassificationPhase.describingTexture => 'Descrevendo a textura...',
        ClassificationPhase.scoring => 'Calculando a classe...',
      };

  // A button read by its text, with ink and a 48 dp target around the chip,
  // which keeps its own size (SPEC 0118).
  Widget _retryChip(String label) => MergeSemantics(
        key: ValueKey<String>(label),
        child: Semantics(
          button: true,
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              key: const Key('retryClassification'),
              borderRadius: BorderRadius.circular(AppRadius.lg),
              onTap: onRetryClassification,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Align(
                  widthFactor: 1,
                  child: _InfoChip(icon: Icons.refresh, label: label),
                ),
              ),
            ),
          ),
        ),
      );
}

class _InfoChip extends StatelessWidget {
  // Keyed by its label, so a new label is a new chip to crossfade to.
  _InfoChip({
    required this.icon,
    required this.label,
    this.isLoading = false,
  }) : super(key: ValueKey<String>(label));

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
        borderRadius: BorderRadius.circular(AppRadius.lg),
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
            ),
          ),
        ],
      ),
    );
  }
}
