import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:visiosoil_app/core/services/classification_failure_copy.dart';
import 'package:visiosoil_app/core/services/classification_report.dart';
import 'package:visiosoil_app/core/theme/app_motion.dart';
import 'package:visiosoil_app/core/theme/app_palette.dart';
import 'package:visiosoil_app/core/theme/app_radius.dart';
import 'package:visiosoil_app/core/theme/app_spacing.dart';
import 'package:visiosoil_app/core/theme/soil_texture_colors.dart';
import 'package:visiosoil_app/core/widgets/confidence_badge.dart';
import 'package:visiosoil_app/core/widgets/status_pill.dart';
import 'package:visiosoil_app/models/soil_record.dart';

/// A record row (redesign v11 §4 `AnalysisTile`): thumbnail, texture class
/// (or the failure reason, when the photograph was not classified), place and
/// time, and a trailing confidence badge, pending-sync pill, or chevron.
///
/// [onDelete], when given, adds a "Excluir" custom semantics action — a
/// non-gesture equivalent to the swipe a [SwipeToDelete] wrapping this tile
/// offers, for a screen-reader or switch-control user (redesign v11 §8).
/// [dense] shrinks the thumbnail and padding, for a tighter list.
///
/// There is no caller yet: the history screen still renders a thumbnail grid
/// (redesign v11 PR 10 migrates it to this tile).
class AnalysisTile extends StatelessWidget {
  const AnalysisTile({
    super.key,
    required this.record,
    this.onTap,
    this.onDelete,
    this.dense = false,
  });

  // QA saw truncation at 320 dp; the trailing content fit at 360 dp.
  static const double _stackedTrailingWidth = 360;

  final SoilRecord record;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.palette;
    final failure = record.classificationFailure;
    final isPending = record.syncStatus == 'pending';
    final thumbSize = dense ? 48.0 : 56.0;

    return Semantics(
      button: onTap != null,
      label: _semanticsLabel(record, failure, isPending),
      onTap: onTap,
      customSemanticsActions: onDelete != null
          ? {const CustomSemanticsAction(label: 'Excluir'): onDelete!}
          : null,
      child: ExcludeSemantics(
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: dense ? AppSpacing.xs : AppSpacing.sm,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 56),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final stackTrailing =
                        constraints.maxWidth < _stackedTrailingWidth ||
                        MediaQuery.textScalerOf(context).scale(14) > 14;
                    final trailing = _Trailing(
                      record: record,
                      isPending: isPending,
                      failed: failure != null,
                    );
                    return Row(
                      children: [
                        _Thumbnail(
                          record: record,
                          size: thumbSize,
                          failed: failure != null,
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                failure != null
                                    ? 'Não classificada'
                                    : record.displayTextureClass,
                                style: theme.textTheme.titleMedium,
                                maxLines: stackTrailing ? null : 1,
                                overflow: stackTrailing
                                    ? null
                                    : TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                failure != null
                                    ? classificationFailureChip(failure).label
                                    : record.formattedTimestampCompact,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: failure != null
                                      ? palette.error
                                      : palette.onSurfaceVariant,
                                ),
                                maxLines: stackTrailing ? null : 1,
                                overflow: stackTrailing
                                    ? null
                                    : TextOverflow.ellipsis,
                              ),
                              if (stackTrailing) ...[
                                const SizedBox(height: AppSpacing.xs),
                                trailing,
                              ],
                            ],
                          ),
                        ),
                        if (!stackTrailing) ...[
                          const SizedBox(width: AppSpacing.sm),
                          trailing,
                        ],
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A placeholder [AnalysisTile] shown while the record it would show is
/// still loading (redesign v11 §4 `AnalysisTile`'s skeleton state).
class AnalysisTileSkeleton extends StatelessWidget {
  const AnalysisTileSkeleton({super.key, this.dense = false});

  final bool dense;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final thumbSize = dense ? 48.0 : 56.0;

    Widget bar(double width, double height) => Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: palette.surfaceContainerHigh,
        borderRadius: AppRadius.borderRadiusXs,
      ),
    );

    return ExcludeSemantics(
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: dense ? AppSpacing.xs : AppSpacing.sm,
        ),
        child: SizedBox(
          height: 56,
          child: Row(
            children: [
              ClipRRect(
                borderRadius: AppRadius.borderRadiusMd,
                child: bar(thumbSize, thumbSize),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    bar(120, 16),
                    const SizedBox(height: 6),
                    bar(72, 12),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _semanticsLabel(
  SoilRecord record,
  ClassificationFailureCause? failure,
  bool isPending,
) {
  String base;
  if (failure != null) {
    base =
        '${record.formattedTimestampCompact}, '
        '${classificationFailureChip(failure).label}';
  } else {
    final score = record.confidenceScore;
    base = score != null && score.isFinite
        ? '${record.displayTextureClass}, ${record.formattedTimestampCompact}, '
              '${floorConfidencePercent(score)}% de confiança'
        : '${record.displayTextureClass}, ${record.formattedTimestampCompact}';
  }

  return isPending ? '$base, pendente de sincronização' : base;
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({
    required this.record,
    required this.size,
    required this.failed,
  });

  final SoilRecord record;
  final double size;
  final bool failed;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final textureColor = !failed && record.hasClassification
        ? SoilTextureColors.forClass(record.textureClass!)
        : palette.outline;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: AppRadius.borderRadiusMd,
        border: Border.all(color: textureColor, width: palette.edgeWidth),
      ),
      child: ClipRRect(
        borderRadius: AppRadius.borderRadiusMd,
        child: Image.file(
          File(record.imagePath),
          fit: BoxFit.cover,
          cacheWidth: (size * 3).round(),
          frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
            if (wasSynchronouslyLoaded) return child;
            return AnimatedSwitcher(
              duration: AppMotion.durationOf(context, AppMotion.base),
              child: frame != null
                  ? child
                  : _fallback(textureColor, Icons.landscape),
            );
          },
          errorBuilder: (_, _, _) => _fallback(textureColor, Icons.landscape),
        ),
      ),
    );
  }

  Widget _fallback(Color color, IconData icon) => Container(
    color: color.withValues(alpha: 0.3),
    child: Center(
      child: Icon(icon, color: color, size: size * 0.45),
    ),
  );
}

class _Trailing extends StatelessWidget {
  const _Trailing({
    required this.record,
    required this.isPending,
    required this.failed,
  });

  final SoilRecord record;
  final bool isPending;
  final bool failed;

  @override
  Widget build(BuildContext context) {
    if (failed) {
      return Icon(Icons.error_outline, color: context.palette.error, size: 20);
    }
    if (isPending) {
      return const StatusPill(status: StatusPillStatus.pending);
    }
    if (record.confidenceScore != null) {
      return ConfidenceBadge(score: record.confidenceScore, compact: true);
    }
    return Icon(Icons.chevron_right, color: context.palette.outline);
  }
}
