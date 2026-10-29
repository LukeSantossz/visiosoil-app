import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:visiosoil_app/core/services/classification_failure_copy.dart';
import 'package:visiosoil_app/core/services/classification_report.dart';
import 'package:visiosoil_app/core/theme/app_motion.dart';
import 'package:visiosoil_app/core/theme/app_palette.dart';
import 'package:visiosoil_app/core/theme/app_radius.dart';
import 'package:visiosoil_app/core/theme/app_spacing.dart';
import 'package:visiosoil_app/core/theme/app_typography.dart';
import 'package:visiosoil_app/core/theme/soil_texture_colors.dart';
import 'package:visiosoil_app/core/widgets/confidence_badge.dart';
import 'package:visiosoil_app/core/widgets/status_pill.dart';
import 'package:visiosoil_app/models/soil_record.dart';
import 'package:visiosoil_app/models/confidence_level.dart';

/// A record row (redesign v11 §4 `AnalysisTile`): thumbnail, texture class
/// (or the failure reason, when the photograph was not classified), place and
/// time, and a trailing confidence badge, pending-sync pill, or chevron.
///
/// [onDelete], when given, adds a "Excluir" custom semantics action — a
/// non-gesture equivalent to the swipe a [SwipeToDelete] wrapping this tile
/// offers, for a screen-reader or switch-control user (redesign v11 §8).
/// [dense] shrinks the thumbnail and padding, for a tighter list.
///
/// Home uses the optional sync presentation, and history its own time and
/// confidence metadata with a chevron for sent records; other callers keep
/// the default. While [syncWired] is false no row names a sync status
/// (SPEC 0235).
class AnalysisTile extends StatelessWidget {
  const AnalysisTile({
    super.key,
    required this.record,
    this.onTap,
    this.onDelete,
    this.onLongPress,
    this.onSelect,
    this.dense = false,
    this.showSyncStatus = false,
    this.offline = false,
    this.history = false,
    this.syncWired = false,
  });

  // Below this inner width (a ~344 dp screen) the row stacks even when the
  // measured text would squeeze in: QA saw truncation at 320 dp, and long
  // localized labels leave no margin there. Wider rows rely on the fit check.
  static const double _compactRowWidth = 320;

  final SoilRecord record;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;
  final VoidCallback? onLongPress;

  /// When given, adds a "Selecionar" custom semantics action: the history's
  /// way into a selection that is not a gesture (SPEC 0122, SPEC 0203).
  final VoidCallback? onSelect;
  final bool dense;

  /// Home keeps confidence in metadata and reserves the trailing edge for sync.
  final bool showSyncStatus;
  final bool offline;

  /// History uses time/confidence metadata and a chevron for sent records.
  final bool history;

  /// Whether a sync backend can send the record. Without one every record is
  /// `pending` forever, so the row shows it as a sent row (SPEC 0235).
  final bool syncWired;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.palette;
    final failure = record.classificationFailure;
    final isPending = syncWired && record.syncStatus == 'pending';
    final showDot = syncWired && (!offline || isPending);
    // Home's rows hold a 40 dp photograph and history's a 56 dp one (PNG 08
    // and 16, SPEC 0203).
    final thumbSize = showSyncStatus
        ? 40.0
        : history
        ? 56.0
        : dense
        ? 48.0
        : 56.0;
    final titleStyle = history
        ? theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w500)
        // Início keeps 16/22 in Modo Sol too, so its rows repeat every 64 dp
        // (PNG 25, SPEC 0213).
        : showSyncStatus
        ? AppTypography.resized(
            theme.textTheme.titleMedium!,
            16,
            height: 22 / 16,
          )
        : theme.textTheme.titleMedium;
    final metadataStyle = showSyncStatus
        ? AppTypography.tabular(
            theme.textTheme.bodySmall!.copyWith(
              fontSize: 13,
              height: 18 / 13,
              color: palette.onSurfaceVariant,
            ),
          )
        : theme.textTheme.bodySmall?.copyWith(
            color: history ? palette.textTertiary : palette.onSurfaceVariant,
          );
    final status = StatusPill(
      status: isPending
          ? StatusPillStatus.pending
          : record.syncStatus == 'error'
          ? StatusPillStatus.error
          : StatusPillStatus.sent,
    );

    return Semantics(
      button: onTap != null,
      label: showSyncStatus
          ? '${failure != null ? classificationFailureChip(failure).label : record.displayTextureClass}, ${_homeMetadata(record, syncWired).replaceFirst('%', '% de confiança')}${isPending
                ? ', pendente de sincronização'
                : !showDot
                ? ''
                : record.syncStatus == 'error'
                ? ', Erro'
                : ', Enviada'}'
          : _semanticsLabel(record, failure, isPending),
      onTap: onTap,
      customSemanticsActions: onDelete != null || onSelect != null
          ? {
              const CustomSemanticsAction(label: 'Selecionar'): ?onSelect,
              const CustomSemanticsAction(label: 'Excluir'): ?onDelete,
            }
          : null,
      child: ExcludeSemantics(
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            onLongPress: onLongPress,
            child: Padding(
              // Home's rows every 64 dp with their rule, and history's 72 dp
              // one, the history row flush with the list's margins (PNG 08
              // and 16, SPEC 0203, SPEC 0210).
              padding: showSyncStatus
                  ? const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg,
                      vertical: 11.5,
                    )
                  : history
                  ? const EdgeInsets.symmetric(vertical: AppSpacing.sm)
                  : EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: dense ? AppSpacing.xs : AppSpacing.sm,
                    ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: showSyncStatus || history ? thumbSize : 56,
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final textScaler = MediaQuery.textScalerOf(context);
                    double textWidth(String text, TextStyle? style) {
                      final painter = TextPainter(
                        text: TextSpan(
                          text: text,
                          style: DefaultTextStyle.of(
                            context,
                          ).style.merge(style),
                        ),
                        textDirection: Directionality.of(context),
                        textScaler: textScaler,
                      )..layout();
                      final width = painter.width;
                      painter.dispose();
                      return width;
                    }

                    final title = failure != null
                        ? 'Não classificada'
                        : record.displayTextureClass;
                    final metadata = failure != null
                        ? classificationFailureChip(failure).label
                        : showSyncStatus
                        ? _homeMetadata(record, syncWired)
                        : history
                        ? _historyMetadata(record)
                        : record.formattedTimestampCompact;
                    final titleWidth = textWidth(title, titleStyle);
                    final dateWidth = textWidth(metadata, metadataStyle);
                    final columnWidth = titleWidth > dateWidth
                        ? titleWidth
                        : dateWidth;
                    final pillStyle = theme.textTheme.labelSmall?.copyWith(
                      fontSize: palette.isSun ? 14 : 12,
                      fontWeight: FontWeight.w600,
                    );
                    double statusWidth(StatusPillStatus status) =>
                        textWidth(status.label, pillStyle) +
                        16 +
                        AppSpacing.xs +
                        2 * AppSpacing.sm +
                        (palette.isSun ? 4 : 0);
                    final score = record.confidenceScore;
                    final double trailingWidth;
                    if (showSyncStatus) {
                      trailingWidth = !showDot
                          ? 0
                          : _StatusDot.dotWidth +
                                textWidth(
                                  status.status.label,
                                  _StatusDot.labelStyle(context),
                                );
                    } else if (failure != null) {
                      trailingWidth = 20;
                    } else if (isPending) {
                      trailingWidth = statusWidth(StatusPillStatus.pending);
                    } else if (score != null) {
                      final label = ConfidenceLevel.fromScore(score).label;
                      final text = score.isFinite
                          ? '${floorConfidencePercent(score)}% · $label'
                          : label;
                      trailingWidth =
                          textWidth(text, pillStyle?.copyWith(height: 1)) +
                          12 +
                          AppSpacing.xs +
                          2 * AppSpacing.xs +
                          (palette.isSun ? 4 : 0);
                    } else {
                      trailingWidth = IconTheme.of(context).size ?? 24;
                    }
                    // Home keeps its row on one line, ellipsing the text,
                    // as PNG 08 draws it (SPEC 0203); only large text or a
                    // narrow phone stacks it.
                    final needsStack =
                        textScaler.scale(1) >= 1.3 ||
                        constraints.maxWidth < _compactRowWidth ||
                        (!showSyncStatus &&
                            thumbSize +
                                    AppSpacing.md +
                                    columnWidth +
                                    AppSpacing.sm +
                                    trailingWidth >
                                constraints.maxWidth);
                    final stackStatus = showSyncStatus && needsStack;
                    final stackTrailing =
                        !showSyncStatus && !history && needsStack;
                    // History moves its trailing content below the row,
                    // aligned to the end, instead of into the text column;
                    // a pending row also does when its pill leaves the text
                    // too little room, as Modo Sol's can (review of #437).
                    final stackBelow =
                        history &&
                        (constraints.maxWidth < 300 ||
                            textScaler.scale(1) >= 1.3 ||
                            (isPending && failure == null && needsStack));
                    final wrapText = stackTrailing || stackBelow;
                    final trailing = history && !isPending && failure == null
                        ? Icon(
                            LucideIcons.chevronRight,
                            size: 24,
                            color: palette.onSurface,
                          )
                        : _Trailing(
                            record: record,
                            isPending: isPending,
                            failed: failure != null,
                          );
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
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
                                    style: titleStyle,
                                    maxLines: stackStatus || wrapText
                                        ? null
                                        : 1,
                                    overflow: wrapText
                                        ? null
                                        : TextOverflow.ellipsis,
                                  ),
                                  if (!showSyncStatus && !history)
                                    const SizedBox(height: 2),
                                  Text(
                                    failure != null
                                        ? classificationFailureChip(
                                            failure,
                                          ).label
                                        : showSyncStatus
                                        ? _homeMetadata(record, syncWired)
                                        : history
                                        ? _historyMetadata(record)
                                        : record.formattedTimestampCompact,
                                    style: metadataStyle?.copyWith(
                                      color: failure != null
                                          ? palette.error
                                          : null,
                                    ),
                                    maxLines: stackStatus || wrapText
                                        ? null
                                        : 1,
                                    overflow: wrapText
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
                            if (!stackTrailing && !stackBelow) ...[
                              const SizedBox(width: AppSpacing.sm),
                              if (showSyncStatus)
                                if (!stackStatus && showDot)
                                  _StatusDot(status: status.status)
                                else
                                  const SizedBox.shrink()
                              else
                                trailing,
                            ],
                          ],
                        ),
                        if (stackBelow)
                          Align(
                            alignment: Alignment.centerRight,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: trailing,
                            ),
                          ),
                        if (stackStatus && showDot) ...[
                          const SizedBox(height: AppSpacing.xs),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: _StatusDot(status: status.status),
                          ),
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

String _homeMetadata(SoilRecord record, bool syncWired) {
  final date = DateTime.tryParse(record.timestamp)?.toLocal();
  var timestamp = record.formattedTimestampCompact;
  if (date != null) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(date.year, date.month, date.day);
    final time =
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    timestamp = day == today
        ? 'hoje $time'
        : day == today.subtract(const Duration(days: 1))
        ? 'ontem $time'
        : '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')} $time';
  }
  final score = record.confidenceScore;
  final confidence =
      score != null &&
          score.isFinite &&
          record.classificationFailure == null &&
          !(syncWired && record.syncStatus == 'error')
      ? '${floorConfidencePercent(score)}%'
      : '—';
  return '$timestamp · $confidence';
}

String _historyMetadata(SoilRecord record) {
  final date = DateTime.tryParse(record.timestamp)?.toLocal();
  final time = date == null
      ? record.formattedTimestampCompact
      : '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  final score = record.confidenceScore;
  return score != null && score.isFinite
      ? '$time · ${floorConfidencePercent(score)}% de confiança'
      : time;
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

    // Radius 8 and no edge outside Modo Sol (PNG 08 and 16, SPEC 0203).
    return Container(
      key: const Key('analysis-thumbnail'),
      width: size,
      height: size,
      foregroundDecoration: palette.highContrast
          ? BoxDecoration(
              borderRadius: AppRadius.borderRadiusSm,
              border: Border.all(color: textureColor, width: palette.edgeWidth),
            )
          : null,
      child: ClipRRect(
        borderRadius: AppRadius.borderRadiusSm,
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

/// Home's sync status: a 7 dp dot and the word, both in the status colour
/// (PNG 08, SPEC 0203).
class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.status});

  final StatusPillStatus status;

  static const double dotWidth = 7 + 6;

  static TextStyle? labelStyle(BuildContext context) => Theme.of(context)
      .textTheme
      .bodySmall
      ?.copyWith(fontSize: 13, height: 18 / 13, fontWeight: FontWeight.w600);

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final color = switch (status) {
      StatusPillStatus.sent => palette.statusSent,
      StatusPillStatus.pending => palette.statusPending,
      StatusPillStatus.error => palette.statusError,
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          key: const Key('status-dot'),
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(status.label, style: labelStyle(context)?.copyWith(color: color)),
      ],
    );
  }
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
