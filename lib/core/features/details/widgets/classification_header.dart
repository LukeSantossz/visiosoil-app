import 'package:flutter/material.dart';
import 'package:visiosoil_app/core/features/capture/widgets/classification_failure_chip.dart';
import 'package:visiosoil_app/core/theme/app_palette.dart';
import 'package:visiosoil_app/core/theme/app_radius.dart';
import 'package:visiosoil_app/core/theme/app_spacing.dart';
import 'package:visiosoil_app/core/theme/soil_texture_colors.dart';
import 'package:visiosoil_app/core/widgets/confidence_badge.dart';
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

  // Approved copy (redesign v11 §3.14, decision 14.2).
  String _bannerMessage(ConfidenceLevel level) => level == ConfidenceLevel.low
      ? 'O modelo não está seguro. Refaça a foto na sombra, com a amostra '
          'preenchendo a moldura.'
      : 'Resultado provável. Se puder, refaça a foto para confirmar.';
}

class _TextureNameRow extends StatelessWidget {
  const _TextureNameRow({required this.record});

  final SoilRecord record;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final failure = record.classificationFailure;
    final textureColor = record.hasClassification
        ? SoilTextureColors.forClass(record.textureClass!)
        : context.palette.outline;

    return Row(
      children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(color: textureColor, shape: BoxShape.circle),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                record.displayTextureClass,
                style: theme.textTheme.headlineMedium,
              ),
              // Why it was not classified, in the capture chip's words
              // (SPEC 0173).
              if (!record.hasClassification && failure != null)
                Text(
                  classificationFailureChip(failure).label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: context.palette.onSurfaceVariant,
                  ),
                ),
            ],
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

    return Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (record.hasClassification)
          ConfidenceBadge(score: record.confidenceScore, fullLabel: true),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.access_time,
                size: 14, color: context.palette.onSurfaceVariant),
            const SizedBox(width: AppSpacing.xs),
            Flexible(
              child: Text(
                record.formattedTimestampCompact,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: context.palette.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Shared advisory banner for low/moderate confidence. Colors come from [level];
/// the border tint is the level's semantic color (error for low, warning for
/// moderate), and in high contrast its text color (SPEC 0135). Replaces the
/// previously duplicated low/moderate inline banners.
class _ConfidenceBanner extends StatelessWidget {
  const _ConfidenceBanner({required this.level, required this.message});

  final ConfidenceLevel level;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = level.accentColor(context.palette);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: level.backgroundColor(context.palette),
        borderRadius: AppRadius.borderRadiusMd,
        border: Border.all(
          color: context.palette.bannerBorder(
            accent: accent,
            onContainer: level.foregroundColor(context.palette),
          ),
          width: context.palette.edgeWidth,
        ),
      ),
      child: Row(
        children: [
          Icon(level.icon, size: 20, color: level.foregroundColor(context.palette)),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: level.foregroundColor(context.palette),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
