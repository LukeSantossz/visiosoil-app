import 'package:flutter/material.dart';
import 'package:visiosoil_app/core/constants/app_strings.dart';
import 'package:visiosoil_app/core/theme/app_palette.dart';
import 'package:visiosoil_app/core/theme/app_radius.dart';
import 'package:visiosoil_app/core/theme/app_spacing.dart';
import 'package:visiosoil_app/core/theme/soil_texture_colors.dart';
import 'package:visiosoil_app/core/utils/formatters.dart';
import 'package:visiosoil_app/core/widgets/confidence_badge.dart';
import 'package:visiosoil_app/core/widgets/confidence_bar.dart';
import 'package:visiosoil_app/models/confidence_level.dart';
import 'package:visiosoil_app/models/soil_record.dart';

/// The result screen's header (redesign v11 §3.6, SPEC 0194): the date chip,
/// the overline, the texture class, the full confidence badge beside the
/// confidence bar and, for low or moderate confidence, an advisory banner.
/// It describes a classified record; an unclassified one shows
/// `ResultErrorBlock` instead.
class ClassificationHeader extends StatelessWidget {
  const ClassificationHeader({super.key, required this.record});

  final SoilRecord record;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final level = ConfidenceLevel.fromScore(record.confidenceScore);
    final hasScore = record.confidenceScore != null;
    final showBanner = hasScore &&
        (level == ConfidenceLevel.low || level == ConfidenceLevel.moderate);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _DateChip(text: Formatters.timestampDotted(record.timestamp)),
        const SizedBox(height: AppSpacing.md),
        Text(
          AppStrings.resultOverline,
          style: theme.textTheme.labelMedium?.copyWith(
            color: context.palette.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        // The class's colour, as history and compare mark it.
        Row(
          children: [
            Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: SoilTextureColors.forClass(record.textureClass!),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                record.displayTextureClass,
                style: theme.textTheme.headlineMedium,
              ),
            ),
          ],
        ),
        if (hasScore) ...[
          const SizedBox(height: AppSpacing.sm),
          _ConfidenceRow(score: record.confidenceScore!),
        ],
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

class _DateChip extends StatelessWidget {
  const _DateChip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: context.palette.inverseSurface,
        borderRadius: AppRadius.borderRadiusSm,
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: context.palette.onInverseSurface,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

/// The badge beside the bar, stacked where the footer stacks too, so a wide
/// badge never squeezes the bar out.
class _ConfidenceRow extends StatelessWidget {
  const _ConfidenceRow({required this.score});

  final double score;

  @override
  Widget build(BuildContext context) {
    final badge = ConfidenceBadge(score: score, fullLabel: true);
    final bar = ConfidenceBar(score: score);
    if (resultStacks(context)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          badge,
          const SizedBox(height: AppSpacing.sm),
          bar,
        ],
      );
    }
    // The badge takes what it needs up to 60 % and wraps beyond it
    // (SPEC 0187); the bar takes the rest.
    return LayoutBuilder(
      builder: (context, constraints) => Row(
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: constraints.maxWidth * 0.6),
            child: badge,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(child: bar),
        ],
      ),
    );
  }
}

/// Whether the result's side-by-side pieces stack: from a 1.3× text scale
/// (redesign v11 §8) and on a screen 360 dp wide or less (§10).
bool resultStacks(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(1) >= 1.3 ||
    MediaQuery.sizeOf(context).width <= 360;

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
