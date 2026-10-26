import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:visiosoil_app/core/theme/app_density.dart';
import 'package:visiosoil_app/core/theme/app_palette.dart';
import 'package:visiosoil_app/core/theme/app_typography.dart';

enum QualityStatus { failed, adjusting, ready }

/// A passive preview reading, announced when it changes. Drawn on the
/// camera's own dark chrome as PNG 10 to 12 measure it (SPEC 0211); Modo Sol
/// keeps a light card.
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

  static const _fill = Color(0xFF1C1C1C);
  static const _edge = Color(0xFF333333);
  static const _readyEdge = Color(0xFF3C5E46);
  static const _muted = Color(0xFFBDBDBD);

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
      label: '$label, $value',
      excludeSemantics: true,
      child: Container(
        // A refused chip's thicker edge eats into its padding, so the chip
        // keeps its size and the panel does not move (PNG 12).
        padding: EdgeInsets.symmetric(
          horizontal: 10 - inset,
          vertical: 8 - inset,
        ),
        decoration: BoxDecoration(
          color: sun ? palette.surface : _fill,
          borderRadius: BorderRadius.circular(8),
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
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    label,
                    style:
                        AppTypography.resized(
                          text.labelLarge!,
                          13,
                          height: 15 / 13,
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
            Text(
              value,
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
