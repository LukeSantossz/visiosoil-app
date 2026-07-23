import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:visiosoil_app/core/theme/app_colors.dart';
import 'package:visiosoil_app/core/theme/app_radius.dart';
import 'package:visiosoil_app/core/theme/soil_texture_colors.dart';
import 'package:visiosoil_app/models/soil_record.dart';

/// The "Última análise" card on the home screen: a tappable summary of the most
/// recent record that opens its details. Renders nothing until a record exists.
class LastAnalysisSection extends StatelessWidget {
  const LastAnalysisSection({super.key, required this.latestAsync});

  final AsyncValue<SoilRecord?> latestAsync;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final record = latestAsync.value;

    if (record == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'ÚLTIMA ANÁLISE',
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
              color: AppColors.onSurface,
            ),
          ),
          const SizedBox(height: 10),
          _AnalysisCard(record: record),
        ],
      ),
    );
  }
}

class _AnalysisCard extends StatelessWidget {
  const _AnalysisCard({required this.record});

  final SoilRecord record;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: record.id != null
          ? () => context.push('/details', extra: record.id!)
          : null,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: AppRadius.borderRadiusLg,
          boxShadow: const [
            BoxShadow(
              color: AppColors.shadowCard,
              blurRadius: 3,
              offset: Offset(0, 1),
            ),
          ],
          border:
              Border.all(color: AppColors.outlineVariant.withValues(alpha: 0.4)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Row(
          children: [
            _AnalysisThumbnail(record: record),
            const SizedBox(width: 12),
            Expanded(child: _AnalysisInfo(record: record)),
            const SizedBox(width: 12),
          ],
        ),
      ),
    );
  }
}

class _AnalysisThumbnail extends StatelessWidget {
  const _AnalysisThumbnail({required this.record});

  final SoilRecord record;

  @override
  Widget build(BuildContext context) {
    final textureColor = record.hasClassification
        ? SoilTextureColors.forClass(record.textureClass!)
        : AppColors.outline;

    return SizedBox(
      width: 84,
      height: 84,
      child: Image.file(
        File(record.imagePath),
        fit: BoxFit.cover,
        cacheWidth: 252,
        errorBuilder: (_, _, _) => Container(
          color: textureColor.withValues(alpha: 0.3),
          child: Icon(Icons.landscape, color: textureColor, size: 32),
        ),
      ),
    );
  }
}

class _AnalysisInfo extends StatelessWidget {
  const _AnalysisInfo({required this.record});

  final SoilRecord record;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                record.displayTextureClass,
                style: theme.textTheme.titleSmall?.copyWith(letterSpacing: -0.2),
              ),
              if (record.confidenceScore != null) ...[
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.primaryContainer,
                    borderRadius: AppRadius.borderRadiusPill,
                  ),
                  child: Text(
                    record.formattedConfidence,
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppColors.onPrimaryContainer,
                      fontSize: 10,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 2),
          Text(
            record.formattedTimestampCompact,
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Text(
                'Ver detalhes',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.arrow_forward, size: 11, color: AppColors.primary),
            ],
          ),
        ],
      ),
    );
  }
}
