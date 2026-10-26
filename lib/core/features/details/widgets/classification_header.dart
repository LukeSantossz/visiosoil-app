import 'package:flutter/material.dart';
import 'package:visiosoil_app/core/constants/app_strings.dart';
import 'package:visiosoil_app/core/theme/app_palette.dart';
import 'package:visiosoil_app/core/theme/app_radius.dart';
import 'package:visiosoil_app/core/theme/app_spacing.dart';
import 'package:visiosoil_app/core/utils/formatters.dart';
import 'package:visiosoil_app/core/widgets/confidence_badge.dart';
import 'package:visiosoil_app/core/widgets/confidence_bar.dart';
import 'package:visiosoil_app/models/confidence_level.dart';
import 'package:visiosoil_app/models/soil_record.dart';

/// The result screen's header (redesign v11 §3.6, SPEC 0194, PNG 14 as
/// SPEC 0202 measures it): the date chip, the overline, the texture class,
/// the label-only badge, the five-segment bar and the percent and, for low
/// or moderate confidence, an advisory banner.
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
    final showBanner =
        hasScore &&
        (level == ConfidenceLevel.low || level == ConfidenceLevel.moderate);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _DateChip(text: Formatters.timestampDotted(record.timestamp)),
        const SizedBox(height: 28),
        Text(
          AppStrings.resultOverline,
          style: theme.textTheme.bodySmall?.copyWith(
            color: context.palette.textTertiary,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(record.displayTextureClass, style: theme.textTheme.headlineMedium),
        if (hasScore) ...[
          const SizedBox(height: 14),
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
    // onSurface at 75 % with white tabular figures (PNG 14, SPEC 0202).
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: context.palette.onSurface.withValues(alpha: 0.75),
        borderRadius: AppRadius.borderRadiusSm,
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          fontSize: 12.5,
          fontWeight: FontWeight.w500,
          letterSpacing: 0,
          height: 15 / 12.5,
          color: context.palette.background,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

/// The label-only badge, the five-segment bar and the percent on the right
/// (PNG 14, SPEC 0202); the badge sits above the bar where the footer stacks
/// too, so a wide badge never squeezes the bar out.
class _ConfidenceRow extends StatelessWidget {
  const _ConfidenceRow({required this.score});

  final double score;

  @override
  Widget build(BuildContext context) {
    final level = ConfidenceLevel.fromScore(score);
    final pct = score.isFinite ? floorConfidencePercent(score) : null;
    final badge = _LevelBadge(level: level, percent: pct);
    final percent = pct == null
        ? null
        : ExcludeSemantics(
            child: Text(
              '$pct%',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontSize: 13,
                color: context.palette.onSurfaceVariant,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          );
    final bar = SegmentedConfidenceBar(score: score);
    if (resultStacks(context)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          badge,
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(child: bar),
              if (percent != null) ...[
                const SizedBox(width: AppSpacing.md),
                percent,
              ],
            ],
          ),
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
          if (percent != null) ...[
            const SizedBox(width: AppSpacing.md),
            percent,
          ],
        ],
      ),
    );
  }
}

/// "Confiança alta" on the level's container, no icon (PNG 14, SPEC 0202);
/// it announces the level with the percent the row shows beside it.
class _LevelBadge extends StatelessWidget {
  const _LevelBadge({required this.level, required this.percent});

  final ConfidenceLevel level;
  final int? percent;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final label = switch (level) {
      ConfidenceLevel.high => AppStrings.confidenceHigh,
      ConfidenceLevel.moderate => AppStrings.confidenceModerate,
      ConfidenceLevel.low => AppStrings.confidenceLow,
    };
    final (fill, ink) = switch (level) {
      ConfidenceLevel.high => (palette.selected, palette.primaryText),
      ConfidenceLevel.moderate => (
        palette.warningContainer,
        palette.onWarningContainer,
      ),
      ConfidenceLevel.low => (palette.errorContainer, palette.onErrorContainer),
    };
    return Semantics(
      label: percent == null
          ? 'Confiança ${level.label.toLowerCase()}'
          : 'Confiança ${level.label.toLowerCase()}, $percent por cento',
      child: ExcludeSemantics(
        child: Container(
          constraints: BoxConstraints(minHeight: palette.isSun ? 28 : 24),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(6),
            border: palette.isSun
                ? Border.all(color: palette.onSurface, width: 2)
                : null,
          ),
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              fontSize: palette.isSun ? 14 : 12,
              height: 1.2,
              letterSpacing: 0,
              fontWeight: FontWeight.w600,
              color: ink,
            ),
          ),
        ),
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
          Icon(
            level.icon,
            size: 20,
            color: level.foregroundColor(context.palette),
          ),
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
