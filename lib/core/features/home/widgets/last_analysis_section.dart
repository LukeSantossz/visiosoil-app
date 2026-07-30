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

/// The home's last-analysis section per the design system: a title with a
/// "Ver tudo" link that opens the History tab, over a tappable record row for
/// the most recent classified record. Renders nothing until a record exists.
class LastAnalysisSection extends StatelessWidget {
  const LastAnalysisSection({
    super.key,
    required this.latestAsync,
    required this.onSeeAll,
  });

  final AsyncValue<SoilRecord?> latestAsync;

  /// Opens the full history (the History tab).
  final VoidCallback onSeeAll;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final record = latestAsync.value;

    if (record == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.xl,
        AppSpacing.lg,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Última análise', style: theme.textTheme.titleMedium),
              TextButton(
                onPressed: onSeeAll,
                child: const Text('Ver tudo'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          _RecordRow(record: record),
        ],
      ),
    );
  }
}

/// Tappable summary row for the latest record, opening its details.
class _RecordRow extends StatelessWidget {
  const _RecordRow({required this.record});

  final SoilRecord record;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: record.id != null
          ? () => context.push('/details', extra: record.id!)
          : null,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: AppRadius.borderRadiusLg,
          border: Border.all(
            color: AppColors.outlineVariant.withValues(alpha: 0.5),
          ),
          boxShadow: const [
            BoxShadow(
              color: AppColors.shadowCard,
              blurRadius: 3,
              offset: Offset(0, 1),
            ),
          ],
        ),
        child: Row(
          children: [
            _Thumbnail(record: record),
            const SizedBox(width: AppSpacing.md),
            Expanded(child: _RecordInfo(record: record)),
            const Icon(
              Icons.chevron_right,
              color: AppColors.outline,
            ),
          ],
        ),
      ),
    );
  }
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.record});

  final SoilRecord record;

  @override
  Widget build(BuildContext context) {
    final textureColor = record.hasClassification
        ? SoilTextureColors.forClass(record.textureClass!)
        : AppColors.outline;

    return ClipRRect(
      borderRadius: AppRadius.borderRadiusMd,
      child: SizedBox(
        width: 48,
        height: 48,
        child: Image.file(
          File(record.imagePath),
          fit: BoxFit.cover,
          cacheWidth: 144,
          errorBuilder: (_, _, _) => Container(
            color: textureColor.withValues(alpha: 0.3),
            child: Icon(Icons.landscape, color: textureColor, size: 24),
          ),
        ),
      ),
    );
  }
}

class _RecordInfo extends StatelessWidget {
  const _RecordInfo({required this.record});

  final SoilRecord record;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final place = record.hasValidAddress
        ? record.address!
        : (record.hasCoordinates
              ? record.formattedCoordinates
              : 'Sem localização');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          record.displayTextureClass,
          style: theme.textTheme.titleMedium,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 2),
        Row(
          children: [
            const Icon(
              Icons.location_on,
              size: 14,
              color: AppColors.onSurfaceVariant,
            ),
            const SizedBox(width: AppSpacing.xs),
            Flexible(
              child: Text(
                '$place · ${record.formattedTimestampCompact}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
        if (record.confidenceScore != null) ...[
          const SizedBox(height: AppSpacing.sm),
          _ConfidenceChip(score: record.confidenceScore!),
        ],
      ],
    );
  }
}

class _ConfidenceChip extends StatelessWidget {
  const _ConfidenceChip({required this.score});

  final double score;

  @override
  Widget build(BuildContext context) {
    final level = ConfidenceLevel.fromScore(score);
    // A corrupt/non-finite persisted score must not crash the home: `.round()`
    // throws on NaN/infinity, so drop the percentage and show only the level.
    final label = score.isFinite
        ? '${(score * 100).round()}% · ${level.label}'
        : level.label;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: level.backgroundColor,
        borderRadius: AppRadius.borderRadiusPill,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(level.icon, size: 12, color: level.foregroundColor),
          const SizedBox(width: AppSpacing.xs),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: level.foregroundColor,
                ),
          ),
        ],
      ),
    );
  }
}
