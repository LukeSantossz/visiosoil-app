import 'package:flutter/material.dart';
import 'package:visiosoil_app/core/theme/app_motion.dart';
import 'package:visiosoil_app/core/theme/app_palette.dart';
import 'package:visiosoil_app/core/theme/app_radius.dart';
import 'package:visiosoil_app/models/confidence_level.dart';

/// The confidence progress bar (redesign v11 §3.14, §4 `ConfidenceBar`): a
/// pill-shaped track that fills to [score] in the level's accent color. When
/// [animate], the fill animates from 0 over [AppMotion.reveal] (closest named
/// token to the mock's 600 ms), honoring [AppMotion.durationOf] for reduced
/// motion.
class ConfidenceBar extends StatelessWidget {
  const ConfidenceBar({super.key, required this.score, this.animate = true});

  /// Confidence score (0.0 to 1.0).
  final double score;

  /// Whether the fill animates in, or renders at its final width.
  final bool animate;

  static const double _height = 8;

  @override
  Widget build(BuildContext context) {
    final level = ConfidenceLevel.fromScore(score);
    final fraction = score.isFinite ? score.clamp(0.0, 1.0) : 0.0;
    // The icon amber fails 3:1 against the light track (SPEC 0185).
    final fillColor = level == ConfidenceLevel.moderate
        ? context.palette.warningText
        : level.accentColor(context.palette);
    final track = context.palette.surfaceContainerHigh;

    // Childless, so it has no intrinsic size: heightFactor: 1 below gives it
    // a tight height, or FractionallySizedBox would collapse it to zero.
    final fill = DecoratedBox(decoration: BoxDecoration(color: fillColor));

    return ClipRRect(
      borderRadius: AppRadius.borderRadiusPill,
      child: Container(
        height: _height,
        color: track,
        alignment: Alignment.centerLeft,
        child: animate
            ? TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: fraction),
                duration: AppMotion.durationOf(context, AppMotion.reveal),
                curve: AppMotion.emphasized,
                builder: (context, value, child) => FractionallySizedBox(
                  widthFactor: value,
                  heightFactor: 1,
                  child: child,
                ),
                child: fill,
              )
            : FractionallySizedBox(
                widthFactor: fraction,
                heightFactor: 1,
                child: fill,
              ),
      ),
    );
  }
}
