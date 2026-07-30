import 'package:flutter/material.dart';
import 'package:visiosoil_app/core/theme/app_colors.dart';
import 'package:visiosoil_app/core/theme/app_radius.dart';
import 'package:visiosoil_app/core/theme/app_spacing.dart';

/// The home's primary capture call-to-action per the design system: a green
/// hero card (primary fill, xl corners, brand green glow) with an eyebrow, a
/// headline, and a full-width white "Nova análise" button. Replaces the former
/// dark capture card.
class HeroCaptureCard extends StatelessWidget {
  const HeroCaptureCard({super.key, required this.onCapture});

  final VoidCallback onCapture;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        0,
      ),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: AppColors.primary,
          borderRadius: AppRadius.borderRadiusXl,
          boxShadow: const [
            BoxShadow(
              color: AppColors.shadowBrand,
              blurRadius: 12,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.auto_awesome,
                  size: 18,
                  color: AppColors.onPrimary,
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  'ANÁLISE INSTANTÂNEA',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: AppColors.onPrimary,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Aponte para o solo e descubra a textura em segundos',
              style: theme.textTheme.headlineSmall?.copyWith(
                color: AppColors.onPrimary,
                height: 1.25,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            _CaptureButton(onCapture: onCapture),
          ],
        ),
      ),
    );
  }
}

/// The white capture button inside the green hero card. Built here rather than
/// via VisioButton because none of its variants render white-on-primary; keeps
/// VisioButton's API unchanged.
class _CaptureButton extends StatelessWidget {
  const _CaptureButton({required this.onCapture});

  final VoidCallback onCapture;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: AppRadius.borderRadiusPill,
          boxShadow: const [
            BoxShadow(
              color: AppColors.shadowElevated,
              blurRadius: 30,
              offset: Offset(0, 10),
            ),
          ],
        ),
        child: ElevatedButton.icon(
          onPressed: onCapture,
          icon: const Icon(Icons.camera_alt, size: 20),
          label: const Text('Nova análise'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: AppColors.primary,
            elevation: 0,
            shadowColor: Colors.transparent,
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
            shape: const StadiumBorder(),
            textStyle: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ),
    );
  }
}
