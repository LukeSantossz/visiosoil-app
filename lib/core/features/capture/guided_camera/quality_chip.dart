import 'package:flutter/material.dart';
import 'package:visiosoil_app/core/theme/app_palette.dart';
import 'package:visiosoil_app/core/theme/app_density.dart';
import 'package:visiosoil_app/core/theme/app_radius.dart';
import 'package:visiosoil_app/core/theme/app_spacing.dart';

enum QualityStatus { failed, adjusting, ready }

/// A passive preview reading, announced when it changes.
class QualityChip extends StatelessWidget {
  const QualityChip({
    super.key,
    required this.label,
    required this.value,
    required this.status,
    this.highlight = false,
  });
  final String label;
  final String value;
  final QualityStatus status;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final foreground = palette.isSun ? palette.onSurface : Colors.white;
    final accent = status == QualityStatus.ready
        ? palette.primaryText
        : palette.onWarningContainer;
    return Semantics(
      liveRegion: true,
      label: '$label, $value',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: palette.isSun ? palette.surface : AppPalette.dark.surface,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(
            color: highlight
                ? palette.warning
                : status == QualityStatus.ready
                ? palette.primary
                : palette.outline,
            width: highlight ? 2 : context.density.borderWidth,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(
                  switch (status) {
                    QualityStatus.ready => Icons.check,
                    QualityStatus.failed => Icons.error_outline,
                    QualityStatus.adjusting => Icons.more_horiz,
                  },
                  size: 16,
                  color: palette.isSun
                      ? accent
                      : status == QualityStatus.ready
                      ? AppPalette.dark.primaryText
                      : AppPalette.dark.onWarningContainer,
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    label,
                    style: Theme.of(
                      context,
                    ).textTheme.labelLarge?.copyWith(color: foreground),
                  ),
                ),
              ],
            ),
            Text(
              value,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: foreground),
            ),
          ],
        ),
      ),
    );
  }
}
