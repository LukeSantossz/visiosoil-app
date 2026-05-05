import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:visiosoil_app/core/theme/app_colors.dart';
import 'package:visiosoil_app/core/theme/app_radius.dart';
import 'package:visiosoil_app/core/theme/app_spacing.dart';
import 'package:visiosoil_app/core/theme/soil_texture_colors.dart';
import 'package:visiosoil_app/models/confidence_level.dart';
import 'package:visiosoil_app/models/soil_record.dart';

/// Tela de resultado apos classificacao.
///
/// Recebe um [SoilRecord] via [GoRouter.extra] (ja persistido com id).
class ResultScreen extends ConsumerWidget {
  const ResultScreen({super.key, required this.record});

  final SoilRecord record;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final level = ConfidenceLevel.fromScore(record.confidenceScore);
    final textureColor = record.hasClassification
        ? SoilTextureColors.forClass(record.textureClass!)
        : AppColors.outline;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Success icon
                const SizedBox(height: AppSpacing.lg),
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: level.backgroundColor,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(level.icon, size: 32, color: level.foregroundColor),
                ),
                const SizedBox(height: AppSpacing.lg),

                // Title
                Text(
                  'Analise concluida',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxl),

                // Classification card
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: AppRadius.borderRadiusLg,
                    border: Border.all(
                      color: textureColor.withValues(alpha: 0.4),
                      width: 2,
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x0A1A1C19),
                        blurRadius: 8,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      // Color dot + class name
                      Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          color: textureColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        record.displayTextureClass,
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      // Confidence badge
                      _ConfidenceBadge(score: record.confidenceScore, level: level),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),

                // Photo thumbnail
                if (record.imagePath.isNotEmpty)
                  ClipRRect(
                    borderRadius: AppRadius.borderRadiusMd,
                    child: SizedBox(
                      height: 160,
                      width: double.infinity,
                      child: Image.file(
                        File(record.imagePath),
                        fit: BoxFit.cover,
                        cacheHeight: 480,
                        errorBuilder: (_, _, _) => Container(
                          color: AppColors.surfaceVariant,
                          child: const Center(
                            child: Icon(Icons.broken_image, size: 32),
                          ),
                        ),
                      ),
                    ),
                  ),

                // Low/moderate banner
                if (level == ConfidenceLevel.low) ...[
                  const SizedBox(height: AppSpacing.lg),
                  _WarningBanner(
                    color: level.backgroundColor,
                    borderColor: AppColors.error.withValues(alpha: 0.3),
                    icon: level.icon,
                    iconColor: level.foregroundColor,
                    text: 'Confianca baixa. Considere refazer a captura.',
                    textColor: level.foregroundColor,
                  ),
                ] else if (level == ConfidenceLevel.moderate) ...[
                  const SizedBox(height: AppSpacing.lg),
                  _WarningBanner(
                    color: level.backgroundColor,
                    borderColor: AppColors.warning.withValues(alpha: 0.3),
                    icon: level.icon,
                    iconColor: level.foregroundColor,
                    text: 'Resultado com confianca moderada.',
                    textColor: level.foregroundColor,
                  ),
                ],

                const SizedBox(height: AppSpacing.xxl),

                // Action buttons
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Plano de manejo em breve')),
                      );
                    },
                    icon: const Icon(Icons.auto_awesome_outlined),
                    label: const Text('Ver plano de manejo'),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => context.go('/capture'),
                    icon: const Icon(Icons.camera_alt_outlined),
                    label: const Text('Nova analise'),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                SizedBox(
                  width: double.infinity,
                  child: TextButton.icon(
                    onPressed: () {
                      if (record.id != null) {
                        context.go('/details', extra: record.id!);
                      } else {
                        context.go('/');
                      }
                    },
                    icon: const Icon(Icons.visibility_outlined),
                    label: const Text('Ver detalhes'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// --- Confidence Badge ---

class _ConfidenceBadge extends StatelessWidget {
  const _ConfidenceBadge({required this.score, required this.level});

  final double? score;
  final ConfidenceLevel level;

  @override
  Widget build(BuildContext context) {
    if (score == null) return const SizedBox.shrink();

    final pct = (score! * 100).round();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: level.backgroundColor,
        borderRadius: AppRadius.borderRadiusPill,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(level.icon, size: 16, color: level.foregroundColor),
          const SizedBox(width: 6),
          Text(
            '$pct% · ${level.label}',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: level.foregroundColor,
                ),
          ),
        ],
      ),
    );
  }
}

// --- Warning Banner ---

class _WarningBanner extends StatelessWidget {
  const _WarningBanner({
    required this.color,
    required this.borderColor,
    required this.icon,
    required this.iconColor,
    required this.text,
    required this.textColor,
  });

  final Color color;
  final Color borderColor;
  final IconData icon;
  final Color iconColor;
  final String text;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: color,
        borderRadius: AppRadius.borderRadiusMd,
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: iconColor),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: textColor,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
