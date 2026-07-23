import 'package:flutter/material.dart';
import 'package:visiosoil_app/core/theme/app_colors.dart';
import 'package:visiosoil_app/core/theme/app_radius.dart';
import 'package:visiosoil_app/core/theme/app_spacing.dart';
import 'package:visiosoil_app/core/theme/soil_texture_colors.dart';
import 'package:visiosoil_app/models/confidence_level.dart';
import 'package:visiosoil_app/models/soil_record.dart';

/// The details screen's classification header: texture class + color dot, a
/// confidence badge with the timestamp, and (for low/moderate confidence) an
/// advisory banner.
class ClassificationHeader extends StatelessWidget {
  const ClassificationHeader({super.key, required this.record});

  final SoilRecord record;

  @override
  Widget build(BuildContext context) {
    final level = ConfidenceLevel.fromScore(record.confidenceScore);
    final showBanner = record.hasClassification &&
        (level == ConfidenceLevel.low || level == ConfidenceLevel.moderate);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _TextureNameRow(record: record),
        const SizedBox(height: AppSpacing.sm),
        _BadgeTimestampRow(record: record),
        if (showBanner) ...[
          const SizedBox(height: AppSpacing.md),
          _ConfidenceBanner(level: level, message: _bannerMessage(level)),
        ],
      ],
    );
  }

  String _bannerMessage(ConfidenceLevel level) => level == ConfidenceLevel.low
      ? 'Confianca baixa. Considere refazer a captura com melhor '
          'iluminacao e enquadramento.'
      : 'Confianca moderada. O resultado pode nao refletir a textura real.';
}

class _TextureNameRow extends StatelessWidget {
  const _TextureNameRow({required this.record});

  final SoilRecord record;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textureColor = record.hasClassification
        ? SoilTextureColors.forClass(record.textureClass!)
        : AppColors.outline;

    return Row(
      children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(color: textureColor, shape: BoxShape.circle),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            record.displayTextureClass,
            style: theme.textTheme.headlineMedium,
          ),
        ),
      ],
    );
  }
}

class _BadgeTimestampRow extends StatelessWidget {
  const _BadgeTimestampRow({required this.record});

  final SoilRecord record;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        if (record.hasClassification) ...[
          _ConfidenceBadge(score: record.confidenceScore),
          const SizedBox(width: AppSpacing.md),
        ],
        Icon(Icons.access_time, size: 14, color: AppColors.onSurfaceVariant),
        const SizedBox(width: AppSpacing.xs),
        Flexible(
          child: Text(
            record.formattedTimestampCompact,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

class _ConfidenceBadge extends StatelessWidget {
  const _ConfidenceBadge({required this.score});

  final double? score;

  @override
  Widget build(BuildContext context) {
    if (score == null) return const SizedBox.shrink();

    final level = ConfidenceLevel.fromScore(score);
    final pct = (score! * 100).round();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(level.icon, size: 14, color: level.foregroundColor),
        const SizedBox(width: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: level.backgroundColor,
            borderRadius: AppRadius.borderRadiusPill,
          ),
          child: Text(
            '$pct% · ${level.label}',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: level.foregroundColor,
                ),
          ),
        ),
      ],
    );
  }
}

/// Shared advisory banner for low/moderate confidence. Colors come from [level];
/// the border tint is the level's semantic color (error for low, warning for
/// moderate). Replaces the previously duplicated low/moderate inline banners.
class _ConfidenceBanner extends StatelessWidget {
  const _ConfidenceBanner({required this.level, required this.message});

  final ConfidenceLevel level;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final borderColor =
        level == ConfidenceLevel.low ? AppColors.error : AppColors.warning;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: level.backgroundColor,
        borderRadius: AppRadius.borderRadiusMd,
        border: Border.all(color: borderColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(level.icon, size: 20, color: level.foregroundColor),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: level.foregroundColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
