import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:visiosoil_app/core/theme/app_density.dart';
import 'package:visiosoil_app/core/theme/app_palette.dart';
import 'package:visiosoil_app/core/theme/app_radius.dart';
import 'package:visiosoil_app/core/theme/app_spacing.dart';
import 'package:visiosoil_app/core/theme/app_typography.dart';
import 'package:visiosoil_app/core/theme/camera_colors.dart';

enum QualityStatus { failed, adjusting, ready }

/// A passive preview reading, announced when it changes. Drawn on the
/// camera's own dark chrome as PNG 10 to 12 measure it (SPEC 0211); Modo Sol
/// keeps a light card.
///
/// It is a live region, announced each time its label changes, so a value
/// that carries a changing number passes its verdict as [spokenValue]
/// (SPEC 0263).
class QualityChip extends StatelessWidget {
  const QualityChip({
    super.key,
    required this.label,
    required this.value,
    required this.status,
    this.spokenValue,
    this.highlight = false,
  });
  final String label;
  final String value;

  /// What the chip announces in place of [value], when [value] carries a
  /// number that changes more often than its verdict.
  final String? spokenValue;
  final QualityStatus status;
  final bool highlight;

  static const _fill = CameraColors.chipFill;
  static const _edge = CameraColors.edge;
  static const _readyEdge = CameraColors.readyEdge;
  static const _muted = CameraColors.muted;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final sun = palette.isSun;
    final dark = AppPalette.dark;
    final text = Theme.of(context).textTheme;
    final (icon, iconColour) = switch (status) {
      QualityStatus.ready => (
        LucideIcons.check,
        sun ? palette.primaryText : dark.statusSent,
      ),
      QualityStatus.failed => (
        LucideIcons.circleAlert,
        sun ? palette.warningText : dark.warning,
      ),
      QualityStatus.adjusting => (
        LucideIcons.ellipsis,
        sun ? palette.onSurfaceVariant : _muted,
      ),
    };
    final edge = highlight ? 2.0 : context.density.borderWidth;
    final inset = math.max(0.0, edge - context.density.borderWidth);
    return Semantics(
      liveRegion: true,
      label: '$label, ${spokenValue ?? value}',
      excludeSemantics: true,
      child: Container(
        // A refused chip's thicker edge eats into its padding, so the chip
        // keeps its size and the panel does not move (PNG 12).
        padding: EdgeInsets.symmetric(
          horizontal: 12 - inset,
          vertical: 8 - inset,
        ),
        decoration: BoxDecoration(
          color: sun ? palette.surface : _fill,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(
            color: highlight
                ? (sun ? palette.warning : dark.warning)
                : status == QualityStatus.ready
                ? (sun ? palette.primary : _readyEdge)
                : (sun ? palette.outline : _edge),
            width: edge,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: iconColour),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    label,
                    style:
                        AppTypography.resized(
                          text.labelLarge!,
                          14,
                          height: 15 / 14,
                        ).copyWith(
                          color: sun ? palette.onSurface : Colors.white,
                          letterSpacing: 0,
                        ),
                  ),
                ),
              ],
            ),
            // The 16 dp icon sets the row; 1 dp more makes PNG 10's 51 dp.
            const SizedBox(height: 1),
            // One line, so the chip's height does not follow its value.
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: text.bodySmall?.copyWith(
                color: sun ? palette.onSurfaceVariant : _muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
