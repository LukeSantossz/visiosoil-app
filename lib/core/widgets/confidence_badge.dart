import 'package:flutter/material.dart';
import 'package:visiosoil_app/core/theme/app_palette.dart';
import 'package:visiosoil_app/core/theme/app_radius.dart';
import 'package:visiosoil_app/core/theme/app_spacing.dart';
import 'package:visiosoil_app/models/confidence_level.dart';

/// The confidence badge (redesign v11 §3.14, §4): the single source for
/// rendering a confidence score as a level-colored pill. Always carries the
/// label and the percentage — never color alone, not even when [compact],
/// which only renders denser (a smaller icon and horizontal padding); the
/// trello acceptance criterion overrides §4's "só %" compact variant.
/// Renders nothing when [score] is null.
class ConfidenceBadge extends StatelessWidget {
  const ConfidenceBadge({super.key, required this.score, this.compact = false});

  /// Confidence score (0.0 to 1.0).
  final double? score;

  /// When true, renders a denser pill (smaller icon and padding); the label
  /// and percentage still both show.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final score = this.score;
    if (score == null) return const SizedBox.shrink();

    final level = ConfidenceLevel.fromScore(score);
    // A corrupt/non-finite persisted score must not crash: `_floorPercent`
    // throws on NaN/infinity, so drop the percentage and show only the level.
    final pct = score.isFinite ? _floorPercent(score) : null;
    final text = pct != null ? '$pct% · ${level.label}' : level.label;
    final iconSize = compact ? 12.0 : 14.0;
    final horizontalPadding = compact ? AppSpacing.xs : AppSpacing.sm;

    return Semantics(
      label: pct != null
          ? 'Confiança ${level.label.toLowerCase()}, $pct por cento'
          : 'Confiança ${level.label.toLowerCase()}',
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(level.icon, size: iconSize, color: level.foregroundColor(context.palette)),
            const SizedBox(width: AppSpacing.xs),
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: horizontalPadding,
                vertical: AppSpacing.xs,
              ),
              decoration: BoxDecoration(
                color: level.backgroundColor(context.palette),
                borderRadius: AppRadius.borderRadiusPill,
              ),
              child: Text(
                text,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: level.foregroundColor(context.palette),
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Floors the percentage rather than rounding, so it never crosses into the
/// band above its own threshold check (0.749 reads 74%, not 75%). Rounds to
/// 6 decimal places first to absorb double-arithmetic noise — `0.29 * 100`
/// is `28.999999999999996`, which a bare `.floor()` would misread as 28.
int _floorPercent(double score) => ((score * 100 * 1e6).round() / 1e6).floor();
